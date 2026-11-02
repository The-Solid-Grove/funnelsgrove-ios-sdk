import Foundation
import os

private let logger = Logger(subsystem: "com.funnelsgrove.sdk", category: "FunnelsGrove")

/// Receives FunnelsGrove links, checks the subscription of the linked user and records app logins.
@MainActor
public final class FunnelsGrove {
    struct Configuration {
        let acceptTestSubscriptions: Bool
    }

    /// Within this time after a link, an inactive answer is polled again: the payment webhook may lag.
    static let freshLinkWindow: TimeInterval = 120
    static let freshLinkRetryDelays: [TimeInterval] = [1, 2, 4, 8]

    private static var instance: FunnelsGrove?

    /// The instance created by `configure`. Using it before `configure` stops the app.
    public static var shared: FunnelsGrove {
        guard let instance else {
            // fatalError, not preconditionFailure: a Release build drops a precondition's message.
            fatalError("Call FunnelsGrove.configure(publishableKey:) before FunnelsGrove.shared")
        }
        return instance
    }

    /// Call once at launch, before any link can arrive. Stops the app when `publishableKey` is empty, contains
    /// whitespace, or starts with `sdk_sec_` or `fg_key_`.
    /// - Parameters:
    ///   - publishableKey: The SDK publishable key of your FunnelsGrove project. Never a secret key.
    ///   - acceptTestSubscriptions: Treat Stripe test-mode subscriptions as active. Use only in QA builds.
    ///   - apiBaseURL: The FunnelsGrove SDK API origin.
    public static func configure(
        publishableKey: String,
        acceptTestSubscriptions: Bool = false,
        apiBaseURL: URL = URL(string: "https://sdk-api.funnelsgrove.com")!
    ) {
        if let problem = publishableKeyProblem(publishableKey) {
            fatalError(problem)
        }
        instance = FunnelsGrove(
            configuration: Configuration(acceptTestSubscriptions: acceptTestSubscriptions),
            store: KeychainUserStore(),
            client: FunnelsGroveClient(baseURL: apiBaseURL, publishableKey: publishableKey)
        )
    }

    /// Why `configure` refuses `key`, or `nil`. The format of publishable keys is not checked, so that a new
    /// FunnelsGrove key format cannot stop apps.
    static func publishableKeyProblem(_ key: String) -> String? {
        if key.isEmpty || key.contains(where: \.isWhitespace) {
            return "publishableKey must be the SDK publishable key of your FunnelsGrove project, without spaces"
        }
        // Anyone who downloads the app can read a key shipped in it.
        if key.hasPrefix("sdk_sec_") || key.hasPrefix("fg_key_") {
            return "publishableKey is a secret FunnelsGrove key: never ship it in an app, use the SDK publishable key"
        }
        return nil
    }

    private let configuration: Configuration
    private let store: UserStore
    private let client: FunnelsGroveAPI
    private let now: () -> Date
    private let sleep: Sleep
    private var cachedUser: LinkedUser?
    private var linkedAt: Date?

    init(
        configuration: Configuration,
        store: UserStore,
        client: FunnelsGroveAPI,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping Sleep = sleepSeconds
    ) {
        self.configuration = configuration
        self.store = store
        self.client = client
        self.now = now
        self.sleep = sleep
    }

    /// The FunnelsGrove user ID from the latest link, if any. A plain property, not observable: read it again after
    /// `handle` returns `true` and after `reset()`.
    public var userId: String? { user?.userId }

    /// The email the links carried for the stored user, if any. Not verified: it is the address the buyer typed in
    /// the funnel, and anyone with the link has it. Fine for a sign-up form or a "signed in as" label, not as proof
    /// that the user owns the address.
    public var email: String? { user?.email }

    private var user: LinkedUser? {
        // An empty read, for example before the first unlock after a reboot, is not cached: the next access tries again.
        if cachedUser == nil { cachedUser = store.read() }
        return cachedUser
    }

    /// Stores the user ID and email from a FunnelsGrove link: any URL, whatever its scheme and host, with a valid
    /// `user_id`. Returns `false` for any other URL, which the app handles itself; route your own links first.
    /// A link without a usable `email` keeps the stored email of the same user and clears another user's.
    /// After `true`, call `checkSubscription()` again: a check that already finished saw the previous user.
    /// No login is recorded: call `trackLogin()` when your app signs the user in.
    @discardableResult
    public func handle(_ url: URL) -> Bool {
        guard let linked = LinkParser.user(from: url) else {
            return false
        }
        let previous = user
        // A link without an email keeps the address of the same user, but never pairs another user's address with
        // the new ID.
        let email = linked.email ?? (previous?.userId == linked.userId ? previous?.email : nil)
        keep(LinkedUser(userId: linked.userId, email: email))
        linkedAt = now()
        return true
    }

    /// Handles a Universal Link delivered as a browsing-web user activity.
    @discardableResult
    public func handle(_ userActivity: NSUserActivity) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL
        else {
            return false
        }
        return handle(url)
    }

    /// Asks FunnelsGrove whether the stored user has an active subscription. The answer is not cached. Without a
    /// stored user it answers `isActive: false` and `userId: nil` without a network call.
    ///
    /// Within 2 minutes of a link an inactive answer is asked again after waits of 1, 2, 4 and 8 seconds, because the
    /// payment webhook may lag: show progress instead of blocking launch on it. Throws `FunnelsGroveError`, or
    /// `CancellationError` when the calling task is cancelled (for example a SwiftUI `.task` whose view went away),
    /// which is no result rather than a failure. If a link or `reset()` arrives meanwhile, the answer is for the
    /// current user.
    public func checkSubscription() async throws -> SubscriptionStatus {
        while true {
            guard let checked = userId else {
                return SubscriptionStatus(isActive: false, isTest: false, isKnownUser: false, userId: nil)
            }
            var response = try await client.verifySubscription(userId: checked)
            if !response.active, isFreshLink {
                for delay in Self.freshLinkRetryDelays {
                    try await sleep(delay)
                    guard userId == checked else { break }
                    response = try await client.verifySubscription(userId: checked)
                    if response.active { break }
                }
            }
            // A link or reset() that arrived while waiting made this answer stale: ask again for the current user.
            guard userId == checked else { continue }
            return SubscriptionStatus(
                isActive: response.active && (!response.test || configuration.acceptTestSubscriptions),
                isTest: response.test,
                isKnownUser: response.user != nil,
                userId: checked
            )
        }
    }

    /// Records "Logged into app" in FunnelsGrove for the stored user. Call it when your app signs the user in or up;
    /// in an app without a sign-in of its own, after `handle` returns `true`; and again after `handle` returns `true`
    /// while the user is signed in. A repeated call for the same user records nothing new.
    ///
    /// Returns `false` without a network call when no user is stored, and `true` once FunnelsGrove has the login.
    /// The login goes to the user stored when the call starts. Throws `FunnelsGroveError.unknownUser` when
    /// FunnelsGrove has no such user in the project, another `FunnelsGroveError`, or `CancellationError`.
    @discardableResult
    public func trackLogin() async throws -> Bool {
        guard let userId else {
            return false
        }
        try await client.trackLogin(userId: userId)
        logger.info("Recorded the login of FunnelsGrove user \(userId, privacy: .private)")
        return true
    }

    /// Forgets the stored user and email. iCloud Keychain removes them from the user's other devices too, where the
    /// app forgets the user from its next launch.
    public func reset() {
        store.delete()
        cachedUser = nil
        linkedAt = nil
    }

    /// Stores the user, kept in memory when the keychain fails.
    private func keep(_ user: LinkedUser) {
        do {
            try store.save(user)
        } catch let error as KeychainError {
            logger.error("Keeping the user failed: \(error.description, privacy: .public)")
        } catch {
            // Only a keychain status is known to carry no user data.
            logger.error("Keeping the user failed: \(String(describing: error), privacy: .private)")
        }
        cachedUser = user
        logger.info("Linked FunnelsGrove user \(user.userId, privacy: .private)")
    }

    private var isFreshLink: Bool {
        guard let linkedAt else { return false }
        return now().timeIntervalSince(linkedAt) < Self.freshLinkWindow
    }
}
