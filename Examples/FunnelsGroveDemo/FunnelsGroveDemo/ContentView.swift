import FunnelsGroveSDK
import SwiftUI

struct ContentView: View {
    private static let loginHint = "Records Logged into app in FunnelsGrove for the stored user"

    @State private var userId = FunnelsGrove.shared.userId
    @State private var email = FunnelsGrove.shared.email
    @State private var status = "Not checked"
    @State private var isChecking = false
    @State private var loginStatus = Self.loginHint
    @State private var isTracking = false
    @State private var pastedLink = ""
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
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Handle link") {
                        if let url = URL(string: pastedLink.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            linked(FunnelsGrove.shared.handle(url))
                        }
                    }
                }
                Section {
                    Button("Reset", role: .destructive) {
                        FunnelsGrove.shared.reset()
                        refreshUser()
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
            linkLog.append("onContinueUserActivity: \(activity.webpageURL?.absoluteString ?? "no URL")")
            linked(FunnelsGrove.shared.handle(activity))
        }
        .onOpenURL { url in
            linkLog.append("onOpenURL: \(url.absoluteString)")
            linked(FunnelsGrove.shared.handle(url))
        }
        .onChange(of: scenePhase) { _, phase in
            // iCloud Keychain may deliver a user in the background; the SDK reads it while it has none.
            if phase == .active { refreshUser() }
        }
    }

    private func refreshUser() {
        userId = FunnelsGrove.shared.userId
        email = FunnelsGrove.shared.email
    }

    private func linked(_ handled: Bool) {
        guard handled else {
            status = "Ignored: no valid user_id in the link"
            return
        }
        refreshUser()
        // The demo records the login with its own button, so that a test can see it apart from the link.
        Task { await check() }
    }

    private func check() async {
        isChecking = true
        status = "Checking…"
        defer { isChecking = false }
        do {
            status = describe(try await FunnelsGrove.shared.checkSubscription())
        } catch is CancellationError {
            status = "Not checked"
        } catch {
            status = "Error: \(error)"
        }
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
