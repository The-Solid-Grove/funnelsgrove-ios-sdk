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
        for status in [404, 500] {
            StubURLProtocol.respond(status, json: "{}")

            await assertThrows(.server(statusCode: status)) {
                _ = try await self.client.verifySubscription(userId: "u_1")
            }
        }
    }

    func testVerifyMapsAnUnreadableBodyToServer() async {
        StubURLProtocol.respond(200, json: "not json")

        await assertThrows(.server(statusCode: 200)) {
            _ = try await self.client.verifySubscription(userId: "u_1")
        }
    }

    func testVerifyRetriesOnceAfterAShort503() async throws {
        StubURLProtocol.respond(503, json: "{}", headers: ["Retry-After": "2"])
        StubURLProtocol.respond(200, json: #"{"active":true,"test":false,"user":{"user_id":"u_1"}}"#)

        let response = try await client.verifySubscription(userId: "u_1")

        XCTAssertTrue(response.active)
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
        let delays = await sleeps.delays
        XCTAssertEqual(delays, [2])
    }

    func testVerifyReportsA503ThatAsksToWaitTooLongOrNamesNoUsableWait() async {
        for retryAfter in ["30", "-1", "Wed, 21 Oct 2026 07:28:00 GMT"] {
            StubURLProtocol.reset()
            StubURLProtocol.respond(503, json: "{}", headers: ["Retry-After": retryAfter])

            await assertThrows(.server(statusCode: 503), message: retryAfter) {
                _ = try await self.client.verifySubscription(userId: "u_1")
            }
            XCTAssertEqual(StubURLProtocol.requests.count, 1, retryAfter)
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
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-SDK-Publishable-Key"), "pk_test")
        XCTAssertEqual(request.jsonBody(), ["userId": "u_1"])
    }

    func testTrackLoginIgnoresTheResponseBody() async throws {
        StubURLProtocol.respond(200, json: "not json")

        try await client.trackLogin(userId: "u_1")
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
