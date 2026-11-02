import FunnelsGroveSDK
import SwiftUI

@main
struct FunnelsGroveDemoApp: App {
    init() {
        // A QA app: it must show Stripe test-mode purchases as active. Real apps never pass true in release builds.
        FunnelsGrove.configure(publishableKey: DemoConfig.publishableKey, acceptTestSubscriptions: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
