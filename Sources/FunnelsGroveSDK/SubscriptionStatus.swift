import Foundation

/// The result of `FunnelsGrove.checkSubscription()`.
public struct SubscriptionStatus: Sendable, Equatable {
    /// FunnelsGrove reports an active subscription, and it is either live or test subscriptions are accepted.
    public let isActive: Bool
    /// An active subscription bought in Stripe test mode. FunnelsGrove reports `false` for an inactive one.
    public let isTest: Bool
    /// FunnelsGrove knows the stored user in this project.
    public let isKnownUser: Bool
    /// The stored FunnelsGrove user ID, or `nil` before the first link or after `reset()`.
    public let userId: String?

    public init(isActive: Bool, isTest: Bool, isKnownUser: Bool, userId: String?) {
        self.isActive = isActive
        self.isTest = isTest
        self.isKnownUser = isKnownUser
        self.userId = userId
    }
}
