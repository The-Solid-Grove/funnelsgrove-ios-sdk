import Foundation

typealias Sleep = @Sendable (TimeInterval) async throws -> Void

func sleepSeconds(_ seconds: TimeInterval) async throws {
    // UInt64 traps on negative or non-finite values.
    guard seconds.isFinite, seconds > 0 else { return }
    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

struct VerifySubscriptionResponse: Decodable, Equatable, Sendable {
    struct User: Decodable, Equatable, Sendable {
        let userId: String

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
        }
    }

    let active: Bool
    let test: Bool
    let user: User?
}

protocol FunnelsGroveAPI: Sendable {
    func verifySubscription(userId: String) async throws -> VerifySubscriptionResponse
    func trackLogin(userId: String) async throws
}

/// Calls the FunnelsGrove public SDK API with the project's publishable key.
struct FunnelsGroveClient: FunnelsGroveAPI {
    /// A 503 asking to wait longer than this is reported instead of retried.
    static let maxRetryAfter: TimeInterval = 10

    let baseURL: URL
    let publishableKey: String
    var session: URLSession = .shared
    var sleep: Sleep = sleepSeconds

    func verifySubscription(userId: String) async throws -> VerifySubscriptionResponse {
        let (data, response) = try await send("sdk/public/users/verify_subscription", userId: userId)
        try check(response)
        do {
            return try JSONDecoder().decode(VerifySubscriptionResponse.self, from: data)
        } catch {
            throw FunnelsGroveError.server(statusCode: response.statusCode)
        }
    }

    /// FunnelsGrove records one login per user, funnel and environment, so a repeated or retried call adds nothing.
    func trackLogin(userId: String) async throws {
        let (_, response) = try await send("sdk/public/users/track_login", userId: userId)
        if response.statusCode == 404 { throw FunnelsGroveError.unknownUser }
        try check(response)
    }

    /// Posts `{"userId": …}`, and once more after a 503 that asks for a short wait.
    private func send(_ path: String, userId: String) async throws -> (Data, HTTPURLResponse) {
        var (data, response) = try await post(path, userId: userId)
        if response.statusCode == 503, let delay = retryAfter(response), (0...Self.maxRetryAfter).contains(delay) {
            try await sleep(delay)
            (data, response) = try await post(path, userId: userId)
        }
        return (data, response)
    }

    private func post(_ path: String, userId: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(publishableKey, forHTTPHeaderField: "X-SDK-Publishable-Key")
        request.httpBody = try JSONEncoder().encode(["userId": userId])
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FunnelsGroveError.server(statusCode: 0)
            }
            return (data, httpResponse)
        } catch let error as URLError {
            // A SwiftUI `.task` whose view went away is not a network failure.
            if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
            throw FunnelsGroveError.network(error)
        }
    }

    /// Seconds from `Retry-After`; an HTTP date is ignored.
    private func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
    }

    private func check(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 400, 401:
            throw FunnelsGroveError.configuration("FunnelsGrove answered \(response.statusCode): check publishableKey")
        default:
            throw FunnelsGroveError.server(statusCode: response.statusCode)
        }
    }
}
