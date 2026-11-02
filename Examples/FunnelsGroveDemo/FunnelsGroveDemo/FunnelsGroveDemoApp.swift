import FunnelsGroveSDK
import SwiftUI

@main
struct FunnelsGroveDemoApp: App {
    init() {
        // QA only: Stripe test-mode purchases show as active, and anyone can make one with a test card. A real app
        // passes a flag that only Debug or a QA configuration sets, never the one it archives (README, "Test
        // subscriptions").
        FunnelsGrove.configure(publishableKey: DemoConfig.publishableKey, acceptTestSubscriptions: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
