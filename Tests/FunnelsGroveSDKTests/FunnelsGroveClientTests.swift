import XCTest
@testable import FunnelsGroveSDK

final class FunnelsGroveClientTests: XCTestCase {
    private var sleeps = SleepRecorder()
    private var client: FunnelsGroveClient!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        sleeps = SleepRecorder()
        let sleeps = sleeps
        client = FunnelsGroveClient(
            baseURL: URL(string: "https://sdk-api.example.com")!,
            publishableKey: "pk_test",
            session: StubURLProtocol.session(),
            sleep: { await sleeps.record($0) }
        )
    }

    func testVerifySendsThePublishableKeyAndUserId() async throws {
        StubURLProtocol.respond(200, json: #"{"active":true,"test":false,"user":{"user_id":"u_1"}}"#)

        let response = try await client.verifySubscription(userId: "u_1")

        XCTAssertEqual(response, VerifySubscriptionResponse(active: true, test: false, user: .init(userId: "u_1")))
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://sdk-api.example.com/sdk/public/users/verify_subscription")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 10)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-SDK-Publishable-Key"), "pk_test")
        XCTAssertEqual(request.jsonBody(), ["userId": "u_1"])
    }

    func testVerifyReadsAnUnknownUser() async throws {
        StubURLProtocol.respond(200, json: #"{"active":false,"test":false,"user":null}"#)

        let response = try await client.verifySubscription(userId: "u_1")

        XCTAssertEqual(response, VerifySubscriptionResponse(active: false, test: false, user: nil))
    }

    func testVerifyMaps400And401ToConfiguration() async {
        for status in [400, 401] {
            StubURLProtocol.respond(status, json: #"{"error":"invalid key"}"#)

            await assertThrows(.configuration("FunnelsGrove answered \(status): check publishableKey")) {
                _ = try await self.client.verifySubscription(userId: "u_1")
            }
        }
    }

    func testVerifyMapsOtherStatusesToServer() async {
        // The status wins over a readable body, and only a 503 is retried, whatever Retry-After says.
        for status in [300, 403, 404, 429, 500] {
            StubURLProtocol.reset()
            StubURLProtocol.respond(
                status,
                json: #"{"active":true,"test":false,"user":{"user_id":"u_1"}}"#,
                headers: ["Retry-After": "1"]
            )

            await assertThrows(.server(statusCode: status), message: "\(status)") {
                _ = try await self.client.verifySubscription(userId: "u_1")
            }
            XCTAssertEqual(StubURLProtocol.requests.count, 1, "\(status)")
        }
        let delays = await sleeps.delays
        XCTAssertEqual(delays, [])
    }

    func testVerifyMapsAnUnreadableBodyToServer() async {
        StubURLProtocol.respond(200, json: "not json")

        await assertThrows(.server(statusCode: 200)) {
            _ = try await self.client.verifySubscription(userId: "u_1")
        }
    }

    func testVerifyRetriesOnceAfterAShort503() async throws {
        for retryAfter in ["0", "10"] {
            StubURLProtocol.reset()
            StubURLProtocol.respond(503, json: "{}", headers: ["Retry-After": retryAfter])
            StubURLProtocol.respond(200, json: #"{"active":true,"test":false,"user":{"user_id":"u_1"}}"#)

            let response = try await client.verifySubscription(userId: "u_1")

            XCTAssertTrue(response.active, retryAfter)
            XCTAssertEqual(StubURLProtocol.requests.count, 2, retryAfter)
        }
        let delays = await sleeps.delays
        XCTAssertEqual(delays, [0, 10])
    }

    func testVerifyReportsA503ThatAsksToWaitTooLongOrNamesNoUsableWait() async {
        for retryAfter in ["11", "-1", "Wed, 21 Oct 2026 07:28:00 GMT", nil] {
            let label = retryAfter ?? "no Retry-After"
            StubURLProtocol.reset()
            StubURLProtocol.respond(503, json: "{}", headers: retryAfter.map { ["Retry-After": $0] } ?? [:])

            await assertThrows(.server(statusCode: 503), message: label) {
                _ = try await self.client.verifySubscription(userId: "u_1")
            }
            XCTAssertEqual(StubURLProtocol.requests.count, 1, label)
        }
        let delays = await sleeps.delays
        XCTAssertEqual(delays, [])
    }

    func testVerifyReportsASecond503() async {
        StubURLProtocol.respond(503, json: "{}", headers: ["Retry-After": "1"])
        StubURLProtocol.respond(503, json: "{}", headers: ["Retry-After": "1"])

        await assertThrows(.server(statusCode: 503)) {
            _ = try await self.client.verifySubscription(userId: "u_1")
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
    }

    func testVerifyMapsTransportFailuresToNetwork() async {
        StubURLProtocol.fail(.notConnectedToInternet)

        do {
            _ = try await client.verifySubscription(userId: "u_1")
            XCTFail("Expected a network error")
        } catch FunnelsGroveError.network(let error) {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testVerifyReportsCancellationAsCancellation() async throws {
        StubURLProtocol.hang()
        let client = try XCTUnwrap(client)
        let task = Task { try await client.verifySubscription(userId: "u_1") }
        for _ in 0..<500 where StubURLProtocol.requests.isEmpty {
            try await Task.sleep(nanoseconds: 2_000_000)
        }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testTrackLoginPostsTheUserId() async throws {
        StubURLProtocol.respond(200, json: #"{"user":{"user_id":"u_1"},"login":{"tracked":true,"newlyTracked":true}}"#)

        try await client.trackLogin(userId: "u_1")

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://sdk-api.example.com/sdk/public/users/track_login")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 10)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-SDK-Publishable-Key"), "pk_test")
        XCTAssertEqual(request.jsonBody(), ["userId": "u_1"])
    }

    func testTrackLoginIgnoresTheResponseBody() async throws {
        for (status, body) in [(200, "not json"), (204, "")] {
            StubURLProtocol.respond(status, json: body)

            try await client.trackLogin(userId: "u_1")
        }
    }

    func testTrackLoginRetriesOnceAfterAShort503() async throws {
        StubURLProtocol.respond(503, json: "{}", headers: ["Retry-After": "1"])
        StubURLProtocol.respond(200, json: "{}")

        try await client.trackLogin(userId: "u_1")

        XCTAssertEqual(StubURLProtocol.requests.count, 2)
        let delays = await sleeps.delays
        XCTAssertEqual(delays, [1])
    }

    func testTrackLoginMaps404ToUnknownUser() async {
        StubURLProtocol.respond(404, json: #"{"error":"Funnel user not found"}"#)

        await assertThrows(.unknownUser) {
            try await self.client.trackLogin(userId: "u_1")
        }
    }

    func testTrackLoginMapsOtherErrors() async {
        StubURLProtocol.respond(400, json: #"{"error":"funnelId is required"}"#)
        await assertThrows(.configuration("FunnelsGrove answered 400: check publishableKey")) {
            try await self.client.trackLogin(userId: "u_1")
        }

        StubURLProtocol.respond(500, json: "{}")
        await assertThrows(.server(statusCode: 500)) {
            try await self.client.trackLogin(userId: "u_1")
        }
    }
}
