import Foundation
@testable import FunnelsGroveSDK

final class FakeUserStore: UserStore {
    var value: LinkedUser?
    var saveError: Error?

    func read() -> LinkedUser? { value }

    func save(_ user: LinkedUser) throws {
        if let saveError { throw saveError }
        value = user
    }

    func delete() { value = nil }
}

actor FakeFunnelsGrove: FunnelsGroveAPI {
    private var answers: [VerifySubscriptionResponse]
    private var verifyError: FunnelsGroveError?
    private var trackError: FunnelsGroveError?
    private var duringNextVerify: (@Sendable () async -> Void)?
    private(set) var verifiedUserIds: [String] = []
    private(set) var trackedUserIds: [String] = []

    init(answers: [VerifySubscriptionResponse] = []) {
        self.answers = answers
    }

    func failVerification(with error: FunnelsGroveError) {
        verifyError = error
    }

    func failTracking(with error: FunnelsGroveError) {
        trackError = error
    }

    /// Runs `action` while the next verify request is in flight.
    func duringNextVerify(_ action: @escaping @Sendable () async -> Void) {
        duringNextVerify = action
    }

    func verifySubscription(userId: String) async throws -> VerifySubscriptionResponse {
        verifiedUserIds.append(userId)
        if let action = duringNextVerify {
            duringNextVerify = nil
            await action()
        }
        if let verifyError { throw verifyError }
        return answers.count > 1 ? answers.removeFirst() : answers[0]
    }

    func trackLogin(userId: String) async throws {
        trackedUserIds.append(userId)
        if let trackError { throw trackError }
    }
}

final class TestClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
}
