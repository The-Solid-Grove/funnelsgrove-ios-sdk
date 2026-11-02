import Foundation

/// Answers URLSession requests from a queue of canned responses and records the requests.
final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    // URLSession calls startLoading on its own thread while tests read `requests`.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var queuedHandlers: [Handler] = []
    nonisolated(unsafe) private static var recordedRequests: [URLRequest] = []

    static var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    static func reset() {
        lock.withLock {
            queuedHandlers = []
            recordedRequests = []
        }
    }

    private static func enqueue(_ handler: @escaping Handler) {
        lock.withLock { queuedHandlers.append(handler) }
    }

    private static func record(_ request: URLRequest) -> Handler? {
        lock.withLock {
            recordedRequests.append(request)
            return queuedHandlers.isEmpty ? nil : queuedHandlers.removeFirst()
        }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func respond(_ statusCode: Int, json: String, headers: [String: String] = [:]) {
        enqueue { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers.merging(["Content-Type": "application/json"]) { current, _ in current }
            )!
            return (response, Data(json.utf8))
        }
    }

    static func fail(_ code: URLError.Code) {
        enqueue { _ in throw URLError(code) }
    }

    /// Leaves the next request unanswered until its task is cancelled.
    static func hang() {
        enqueue { _ in throw Hang() }
    }

    private struct Hang: Error {}

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.record(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch is Hang {
            return
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLRequest {
    /// URLSession hands the body to URL protocols as a stream.
    func jsonBody() -> [String: String]? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: String]
    }
}
