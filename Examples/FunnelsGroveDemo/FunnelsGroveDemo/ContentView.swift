import FunnelsGroveSDK
import SwiftUI

struct ContentView: View {
    private static let loginHint = "Records Logged into app in FunnelsGrove for the stored user"
    private static let maxLoggedLinks = 10

    @State private var userId = FunnelsGrove.shared.userId
    @State private var email = FunnelsGrove.shared.email
    @State private var status = "Not checked"
    @State private var isChecking = false
    /// Counts checks, so that only the latest one shows its answer.
    @State private var checkGeneration = 0
    @State private var loginStatus = Self.loginHint
    @State private var isTracking = false
    @State private var pastedLink = ""
    // QA only: the links carry the user ID and email. A real app never shows, logs or stores them.
    @State private var linkLog: [String] = []
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                Section("FunnelsGrove user") {
                    Text(userId ?? "No link yet")
                        .textSelection(.enabled)
                    Text(email ?? "No email from the link")
                        .textSelection(.enabled)
                }
                Section("Subscription") {
                    Text(status)
                    Button(isChecking ? "Checking…" : "Check") {
                        Task { await check() }
                    }
                    .disabled(isChecking)
                }
                Section("App login") {
                    Text(loginStatus)
                        .font(.footnote)
                    Button(isTracking ? "Tracking…" : "Track login") {
                        isTracking = true
                        Task { await trackLogin() }
                    }
                    .disabled(isTracking)
                }
                Section("Last links received") {
                    Text(linkLog.isEmpty ? "None" : linkLog.joined(separator: "\n"))
                        .font(.footnote)
                        .textSelection(.enabled)
                }
                Section("Paste a link") {
                    TextField("Link", text: $pastedLink, prompt: Text(verbatim: "fgdemo://open?user_id=…&email=…"))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(handlePastedLink)
                    Button("Handle link", action: handlePastedLink)
                }
                Section {
                    Button("Reset", role: .destructive) {
                        FunnelsGrove.shared.reset()
                        refreshUser()
                        // Drop the answer of a check still running.
                        checkGeneration += 1
                        isChecking = false
                        status = "Not checked"
                        loginStatus = Self.loginHint
                    }
                }
            }
            .navigationTitle("FunnelsGrove Demo")
        }
        // A custom scheme arrives in onOpenURL; SwiftUI routes a Universal Link to one of these two handlers.
        // "Last links received" shows which.
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            log("onContinueUserActivity: \(activity.webpageURL?.absoluteString ?? "no URL")")
            // A real app routes its own links before handing the rest to the SDK.
            linked(FunnelsGrove.shared.handle(activity))
        }
        .onOpenURL { url in
            log("onOpenURL: \(url.absoluteString)")
            linked(FunnelsGrove.shared.handle(url))
        }
        .onChange(of: scenePhase) { _, phase in
            // iCloud Keychain may deliver a user in the background; the SDK reads it while it has none.
            guard phase == .active else { return }
            let isAnotherUser = FunnelsGrove.shared.userId != userId
            refreshUser()
            // The status on screen was checked for no user or for another one.
            if isAnotherUser {
                status = "Not checked"
                loginStatus = Self.loginHint
            }
        }
    }

    private func handlePastedLink() {
        let text = pastedLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text) else {
            log("Ignored: the pasted text is not a URL")
            return
        }
        log("Pasted: \(url.absoluteString)")
        linked(FunnelsGrove.shared.handle(url))
    }

    private func log(_ entry: String) {
        linkLog.append(entry)
        if linkLog.count > Self.maxLoggedLinks {
            linkLog.removeFirst(linkLog.count - Self.maxLoggedLinks)
        }
    }

    private func refreshUser() {
        userId = FunnelsGrove.shared.userId
        email = FunnelsGrove.shared.email
    }

    private func linked(_ handled: Bool) {
        guard handled else {
            // The SDK ignored the link: the stored user and its last answer stay.
            log("Ignored: no valid user_id in the link")
            return
        }
        let previous = userId
        refreshUser()
        // The login result on screen was for another user.
        if userId != previous { loginStatus = Self.loginHint }
        // A check that already finished saw the previous user: check again.
        Task { await check() }
        // A real app calls trackLogin() here when it has no sign-in of its own, or while the user is signed in
        // (README, "App login"). The demo records the login with its own button, so that a test sees it apart
        // from the link.
    }

    /// Shows the answer of the latest check only: a link can start one while another runs.
    private func check() async {
        checkGeneration += 1
        let generation = checkGeneration
        isChecking = true
        status = "Checking…"
        let answer: String
        do {
            answer = describe(try await FunnelsGrove.shared.checkSubscription())
        } catch is CancellationError {
            answer = "Not checked"
        } catch {
            answer = "Error: \(error)"
        }
        guard generation == checkGeneration else { return }
        status = answer
        isChecking = false
    }

    private func describe(_ result: SubscriptionStatus) -> String {
        guard result.userId != nil else { return "No user" }
        guard result.isKnownUser else { return "Unknown to FunnelsGrove" }
        if result.isActive { return result.isTest ? "Active (test)" : "Active" }
        return result.isTest ? "Inactive (test)" : "Inactive"
    }

    private func trackLogin() async {
        defer { isTracking = false }
        loginStatus = "Tracking…"
        do {
            loginStatus = try await FunnelsGrove.shared.trackLogin() ? "Tracked" : "No user: open a link first"
        } catch FunnelsGroveError.unknownUser {
            loginStatus = "FunnelsGrove does not know this user in the project"
        } catch is CancellationError {
            loginStatus = Self.loginHint
        } catch {
            loginStatus = "Error: \(error)"
        }
    }
}
