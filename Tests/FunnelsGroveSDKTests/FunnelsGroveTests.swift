import XCTest
@testable import FunnelsGroveSDK

@MainActor
final class FunnelsGroveTests: XCTestCase {
    private let link = URL(string: "https://go.example.com/open?user_id=u_1&email=buyer%40example.com")!
    private let active = VerifySubscriptionResponse(active: true, test: false, user: .init(userId: "u_1"))
    private let inactive = VerifySubscriptionResponse(active: false, test: false, user: .init(userId: "u_1"))
    private let activeTest = VerifySubscriptionResponse(active: true, test: true, user: .init(userId: "u_1"))
    private let unknown = VerifySubscriptionResponse(active: false, test: false, user: nil)

    private var store = FakeUserStore()
    private var clock = TestClock()
    private var sleeps = SleepRecorder()

    override func setUp() async throws {
        store = FakeUserStore()
        clock = TestClock()
        sleeps = SleepRecorder()
    }

    private func makeSDK(
        answers: [VerifySubscriptionResponse],
        acceptTestSubscriptions: Bool = false,
        sleep: Sleep? = nil
    ) -> (FunnelsGrove, FakeFunnelsGrove) {
        let fake = FakeFunnelsGrove(answers: answers)
        let clock = clock
        let sleeps = sleeps
        let sdk = FunnelsGrove(
            configuration: .init(acceptTestSubscriptions: acceptTestSubscriptions),
            store: store,
            client: fake,
            now: { clock.now },
            sleep: sleep ?? { await sleeps.record($0) }
        )
        return (sdk, fake)
    }

    // MARK: - Links

    func testHandleStoresTheUserAndEmailWithoutTrackingTheLogin() async {
        let (sdk, fake) = makeSDK(answers: [active])

        XCTAssertTrue(sdk.handle(link))

        XCTAssertEqual(store.value, LinkedUser(userId: "u_1", email: "buyer@example.com"))
        XCTAssertEqual(sdk.userId, "u_1")
        XCTAssertEqual(sdk.email, "buyer@example.com")
        let tracked = await fake.trackedUserIds
        XCTAssertEqual(tracked, [])
    }

    func testHandleAcceptsACustomScheme() {
        let (sdk, _) = makeSDK(answers: [active])

        XCTAssertTrue(sdk.handle(URL(string: "fgdemo://open?user_id=u_1")!))
        XCTAssertEqual(sdk.userId, "u_1")
        XCTAssertNil(sdk.email)
    }

    func testHandleIgnoresLinksWithoutAUserId() {
        let (sdk, _) = makeSDK(answers: [active])

        XCTAssertFalse(sdk.handle(URL(string: "https://go.example.com/open?email=buyer%40example.com")!))
        XCTAssertFalse(sdk.handle(URL(string: "myapp://profile?id=42")!))
        XCTAssertNil(store.value)
        XCTAssertNil(sdk.userId)
        XCTAssertNil(sdk.email)
    }

    func testHandleKeepsTheUserInMemoryWhenTheKeychainFails() {
        store.saveError = KeychainError(status: errSecIO)
        let (sdk, _) = makeSDK(answers: [active])

        XCTAssertTrue(sdk.handle(link))
        XCTAssertEqual(sdk.userId, "u_1")
        XCTAssertEqual(sdk.email, "buyer@example.com")
    }

    func testANewLinkReplacesTheStoredUserAndEmail() {
        store.value = LinkedUser(userId: "u_old", email: "old@example.com")
        let (sdk, _) = makeSDK(answers: [active])

        sdk.handle(link)

        XCTAssertEqual(store.value, LinkedUser(userId: "u_1", email: "buyer@example.com"))
    }

    func testALinkWithoutAnEmailKeepsTheEmailOfTheSameUser() {
        store.value = LinkedUser(userId: "u_1", email: "buyer@example.com")
        let (sdk, _) = makeSDK(answers: [active])

        sdk.handle(URL(string: "fgdemo://open?user_id=u_1")!)

        XCTAssertEqual(store.value, LinkedUser(userId: "u_1", email: "buyer@example.com"))
    }

    func testALinkWithAnUnusableEmailKeepsTheEmailOfTheSameUser() {
        store.value = LinkedUser(userId: "u_1", email: "buyer@example.com")
        let (sdk, _) = makeSDK(answers: [active])

        sdk.handle(URL(string: "fgdemo://open?user_id=u_1&email=nonsense")!)

        XCTAssertEqual(sdk.email, "buyer@example.com")
    }

    func testALinkWithoutAnEmailDropsTheEmailOfAnotherUser() {
        store.value = LinkedUser(userId: "u_old", email: "old@example.com")
        let (sdk, _) = makeSDK(answers: [active])

        sdk.handle(URL(string: "fgdemo://open?user_id=u_1")!)

        XCTAssertEqual(store.value, LinkedUser(userId: "u_1"))
        XCTAssertNil(sdk.email)
    }

    func testANewEmailReplacesTheEmailOfTheSameUser() {
        store.value = LinkedUser(userId: "u_1", email: "old@example.com")
        let (sdk, _) = makeSDK(answers: [active])

        sdk.handle(link)

        XCTAssertEqual(sdk.email, "buyer@example.com")
    }

    func testHandleAcceptsABrowsingWebActivity() {
        let (sdk, _) = makeSDK(answers: [active])
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = link

        XCTAssertTrue(sdk.handle(activity))
        XCTAssertFalse(sdk.handle(NSUserActivity(activityType: "com.funnelsgrove.other")))
    }

    func testHandleIgnoresOtherActivityTypesEvenWithAURL() {
        let (sdk, _) = makeSDK(answers: [active])
        let activity = NSUserActivity(activityType: "com.funnelsgrove.other")
        activity.webpageURL = link

        XCTAssertFalse(sdk.handle(activity))
        XCTAssertNil(store.value)
    }

    func testTheUserSurvivesANewInstance() {
        store.value = LinkedUser(userId: "u_saved", email: "saved@example.com")
        let (sdk, _) = makeSDK(answers: [active])

        XCTAssertEqual(sdk.userId, "u_saved")
        XCTAssertEqual(sdk.email, "saved@example.com")
    }

    func testTheUserIsReadAgainAfterAnEmptyRead() {
        let (sdk, _) = makeSDK(answers: [active])
        XCTAssertNil(sdk.userId)

        store.value = LinkedUser(userId: "u_later")

        XCTAssertEqual(sdk.userId, "u_later")
    }

    // MARK: - Subscription

    func testCheckWithoutAUserSkipsTheNetwork() async throws {
        let (sdk, fake) = makeSDK(answers: [active])

        let status = try await sdk.checkSubscription()

        XCTAssertEqual(status, SubscriptionStatus(isActive: false, isTest: false, isKnownUser: false, userId: nil))
        let calls = await fake.verifiedUserIds
        XCTAssertEqual(calls, [])
    }

    func testCheckReportsALiveSubscription() async throws {
        store.value = LinkedUser(userId: "u_1")
        let (sdk, _) = makeSDK(answers: [active])

        let status = try await sdk.checkSubscription()

        XCTAssertEqual(status, SubscriptionStatus(isActive: true, isTest: false, isKnownUser: true, userId: "u_1"))
    }

    func testCheckRejectsTestSubscriptionsByDefault() async throws {
        store.value = LinkedUser(userId: "u_1")
        let (sdk, _) = makeSDK(answers: [activeTest])

        let status = try await sdk.checkSubscription()

        XCTAssertEqual(status, SubscriptionStatus(isActive: false, isTest: true, isKnownUser: true, userId: "u_1"))
    }

    func testCheckAcceptsTestSubscriptionsWhenConfigured() async throws {
        store.value = LinkedUser(userId: "u_1")
        let (sdk, _) = makeSDK(answers: [activeTest], acceptTestSubscriptions: true)

        let status = try await sdk.checkSubscription()

        XCTAssertEqual(status, SubscriptionStatus(isActive: true, isTest: true, isKnownUser: true, userId: "u_1"))
    }

    func testCheckKeepsTheUserWhenFunnelsGroveDoesNotKnowIt() async throws {
        store.value = LinkedUser(userId: "u_1", email: "buyer@example.com")
        let (sdk, _) = makeSDK(answers: [unknown])

        let status = try await sdk.checkSubscription()

        XCTAssertEqual(status, SubscriptionStatus(isActive: false, isTest: false, isKnownUser: false, userId: "u_1"))
        XCTAssertEqual(store.value, LinkedUser(userId: "u_1", email: "buyer@example.com"))
    }

    func testCheckPollsAfterAFreshLinkUntilActive() async throws {
        let (sdk, fake) = makeSDK(answers: [inactive, inactive, active])
        sdk.handle(link)

        let status = try await sdk.checkSubscription()

        XCTAssertTrue(status.isActive)
        let calls = await fake.verifiedUserIds
        XCTAssertEqual(calls.count, 3)
        let delays = await sleeps.delays
        XCTAssertEqual(delays, [1, 2])
    }

    func testCheckStopsPollingAfterAllDelays() async throws {
        let (sdk, fake) = makeSDK(answers: [inactive])
        sdk.handle(link)

        let status = try await sdk.checkSubscription()

        XCTAssertFalse(status.isActive)
        let calls = await fake.verifiedUserIds
        XCTAssertEqual(calls.count, 5)
        let delays = await sleeps.delays
        XCTAssertEqual(delays, [1, 2, 4, 8])
    }

    func testCheckDoesNotPollForAUserFromAnEarlierLaunch() async throws {
        store.value = LinkedUser(userId: "u_1")
        let (sdk, fake) = makeSDK(answers: [inactive])

        _ = try await sdk.checkSubscription()

        let calls = await fake.verifiedUserIds
        XCTAssertEqual(calls.count, 1)
    }

    func testFreshLinkWindowIsTwoMinutes() async throws {
        for (age, expectedCalls) in [(119.0, 5), (120.0, 1)] {
            store = FakeUserStore()
            let (sdk, fake) = makeSDK(answers: [inactive])
            sdk.handle(link)
            clock.now += age

            _ = try await sdk.checkSubscription()

            let calls = await fake.verifiedUserIds
            XCTAssertEqual(calls.count, expectedCalls, "link age \(age) s")
        }
    }

    func testCheckPassesFunnelsGroveErrorsThrough() async {
        store.value = LinkedUser(userId: "u_1")
        let (sdk, fake) = makeSDK(answers: [active])
        await fake.failVerification(with: .server(statusCode: 500))

        do {
            _ = try await sdk.checkSubscription()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? FunnelsGroveError, .server(statusCode: 500))
        }
    }

    func testCheckReportsCancellationWhilePolling() async {
        // Task.sleep throws CancellationError when the calling task is cancelled.
        let (sdk, fake) = makeSDK(answers: [inactive], sleep: { _ in throw CancellationError() })
        sdk.handle(link)

        do {
            _ = try await sdk.checkSubscription()
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error \(error)")
        }
        let calls = await fake.verifiedUserIds
        XCTAssertEqual(calls.count, 1)
    }

    func testCheckAnswersForALinkThatArrivedDuringTheRequest() async throws {
        store.value = LinkedUser(userId: "u_old")
        let (sdk, fake) = makeSDK(answers: [active])
        let newLink = URL(string: "fgdemo://open?user_id=u_new")!
        await fake.duringNextVerify { await MainActor.run { _ = sdk.handle(newLink) } }

        let status = try await sdk.checkSubscription()

        XCTAssertEqual(status.userId, "u_new")
        let calls = await fake.verifiedUserIds
        XCTAssertEqual(calls, ["u_old", "u_new"])
    }

    func testCheckReportsNoUserAfterAResetDuringTheRequest() async throws {
        store.value = LinkedUser(userId: "u_1")
        let (sdk, fake) = makeSDK(answers: [active])
        await fake.duringNextVerify { await MainActor.run { sdk.reset() } }

        let status = try await sdk.checkSubscription()

        XCTAssertEqual(status, SubscriptionStatus(isActive: false, isTest: false, isKnownUser: false, userId: nil))
        let calls = await fake.verifiedUserIds
        XCTAssertEqual(calls, ["u_1"])
    }

    func testCheckStopsPollingTheOldUserWhenANewLinkArrives() async throws {
        let (sdk, fake) = makeSDK(answers: [inactive])
        sdk.handle(link)
        let newLink = URL(string: "fgdemo://open?user_id=u_2")!
        await fake.duringNextVerify { await MainActor.run { _ = sdk.handle(newLink) } }

        let status = try await sdk.checkSubscription()

        XCTAssertEqual(status.userId, "u_2")
        let calls = await fake.verifiedUserIds
        XCTAssertEqual(calls, ["u_1"] + Array(repeating: "u_2", count: 5))
    }

    // MARK: - Login

    func testTrackLoginWithoutAUserSkipsTheNetwork() async throws {
        let (sdk, fake) = makeSDK(answers: [active])

        let tracked = try await sdk.trackLogin()

        XCTAssertFalse(tracked)
        let calls = await fake.trackedUserIds
        XCTAssertEqual(calls, [])
    }

    func testTrackLoginRecordsTheStoredUser() async throws {
        store.value = LinkedUser(userId: "u_1")
        let (sdk, fake) = makeSDK(answers: [active])

        let tracked = try await sdk.trackLogin()

        XCTAssertTrue(tracked)
        let calls = await fake.trackedUserIds
        XCTAssertEqual(calls, ["u_1"])
    }

    func testTrackLoginRecordsTheUserOfTheLatestLink() async throws {
        store.value = LinkedUser(userId: "u_old")
        let (sdk, fake) = makeSDK(answers: [active])
        sdk.handle(link)

        try await sdk.trackLogin()

        let calls = await fake.trackedUserIds
        XCTAssertEqual(calls, ["u_1"])
    }

    func testTrackLoginPassesErrorsThrough() async {
        store.value = LinkedUser(userId: "u_1")
        let (sdk, fake) = makeSDK(answers: [active])
        await fake.failTracking(with: .unknownUser)

        do {
            try await sdk.trackLogin()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? FunnelsGroveError, .unknownUser)
        }
    }

    // MARK: - Reset

    func testResetForgetsTheUserAndEmail() async throws {
        let (sdk, fake) = makeSDK(answers: [inactive])
        sdk.handle(link)

        sdk.reset()
        let status = try await sdk.checkSubscription()
        let tracked = try await sdk.trackLogin()

        XCTAssertNil(store.value)
        XCTAssertNil(sdk.userId)
        XCTAssertNil(sdk.email)
        XCTAssertNil(status.userId)
        XCTAssertFalse(tracked)
        let calls = await fake.verifiedUserIds
        XCTAssertEqual(calls, [])
    }

    func testResetAlsoForgetsWhenTheLinkArrived() async throws {
        let (sdk, fake) = makeSDK(answers: [inactive])
        sdk.handle(link)
        sdk.reset()
        store.value = LinkedUser(userId: "u_synced")

        _ = try await sdk.checkSubscription()

        let calls = await fake.verifiedUserIds
        XCTAssertEqual(calls, ["u_synced"])
    }

    // MARK: - Configuration

    func testAcceptsAPublishableKey() {
        XCTAssertNil(FunnelsGrove.publishableKeyProblem("sdk_pub_" + String(repeating: "a", count: 48)))
        // Not tied to today's format: a new kind of publishable key must not stop apps.
        XCTAssertNil(FunnelsGrove.publishableKeyProblem("pk_future_format"))
    }

    func testRefusesAnEmptyOrSpacedKey() {
        for key in ["", " sdk_pub_1", "sdk_pub_1\n", "sdk pub"] {
            XCTAssertEqual(
                FunnelsGrove.publishableKeyProblem(key),
                "publishableKey must be the SDK publishable key of your FunnelsGrove project, without spaces",
                key
            )
        }
    }

    func testRefusesSecretKeys() {
        for key in ["sdk_sec_123", "fg_key_123"] {
            XCTAssertEqual(
                FunnelsGrove.publishableKeyProblem(key),
                "publishableKey is a secret FunnelsGrove key: never ship it in an app, use the SDK publishable key",
                key
            )
        }
    }
}
