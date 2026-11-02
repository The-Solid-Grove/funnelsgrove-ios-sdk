# FunnelsGroveSDK

Links a FunnelsGrove web purchase to your iOS app. After checkout, the funnel's "Open app now" button and the purchase
email open your app with a link that carries the buyer's FunnelsGrove user ID and email, for example
`myapp://open?user_id=u_…&email=…`. The SDK keeps them in the keychain, asks FunnelsGrove whether the user's
subscription is active, and records "Logged into app" in FunnelsGrove when your app says the user signed in.

The link works like a bearer token: whoever has it gets the subscription status of its user and the buyer's email.
Don't treat the result as proof of ownership, and don't log the link, the user ID or the email, or send them to
analytics or support tools.

## How a buyer reaches the app

- The buyer taps "Open app now" on the funnel's success page, or the link in the purchase email. If the app is
  installed, iOS opens it with the link.
- If the app is not installed, the link cannot open it. The buyer installs the app from the App Store button on the
  same page and taps "Open app now" again: there is no deferred deep link.
- The funnel also opens the link once by itself. iOS often does not open the app for that, so the purchase is linked
  by a later tap.
- In-app browsers such as TikTok's or Instagram's often don't open the app at all.

## Requirements

- iOS 15+, Xcode 16+.
- The SDK publishable key of your FunnelsGrove project. Never put a secret key (`sdk_sec_…`) or an organization API
  key (`fg_key_…`) in an app: anyone who downloads it can read the key, so `configure` stops the app if you pass one.
- A FunnelsGrove project whose funnel links to your app, see below.

## Set up your FunnelsGrove project

In the project settings, point at least one of these fields at your app, then publish the funnel:

- **App Store deeplink**: a link with your app's own scheme, for example `myapp://open`. On iOS, "Open app now"
  uses it first.
- **Web link**: a Universal Link on your domain, for example `https://go.myapp.com/open`. The purchase email uses it
  first.

FunnelsGrove adds `user_id`, `email` and the first-touch campaign parameters to both. Check that "Open app now" in the
published funnel opens your app and that the link carries `user_id`.

## Install

Add the package `https://github.com/The-Solid-Grove/funnelsgrove-ios-sdk.git` and link the `FunnelsGroveSDK`
product. The repository is private for now: ask the FunnelsGrove team for access. There is no release tag yet: until
the prototype is merged, add the package by branch `feat/sdk-prototype`, and after that by `main`.

## Links into the app

The SDK accepts any link with a `user_id`, whatever its scheme and host. Which links open your app is up to you:

- **Custom scheme.** Add a URL type with your scheme: Target → Info → URL Types, or `CFBundleURLTypes`.
- **Universal Links.** Add the Associated Domains capability with `applinks:<your domain>` and serve an
  `apple-app-site-association` file for your Team ID and bundle ID from that domain. Apple's CDN can take up to
  24 hours to pick up a new file, so publish it before you ship the build.
  - Debug builds can use `applinks:<your domain>?mode=developer`. The device then reads the file from your server
    directly. This needs Developer Mode (Settings → Privacy & Security) and Settings → Developer → Associated
    Domains Development.
  - Release and TestFlight builds must use the plain `applinks:<your domain>`.

If your app has its own links with a `user_id` parameter, handle them before the SDK: it takes any link with a valid
`user_id` for a FunnelsGrove link.

## Use

### SwiftUI

```swift
import FunnelsGroveSDK
import SwiftUI

@main
struct MyApp: App {
    @State private var hasAccess = false

    init() {
        FunnelsGrove.configure(publishableKey: "<FunnelsGrove SDK publishable key>")
    }

    var body: some Scene {
        WindowGroup {
            RootView(hasAccess: hasAccess)
                .task { await refreshAccess() }
                // A custom-scheme link arrives in onOpenURL. SwiftUI routes a Universal Link to one of these two
                // handlers; register both.
                .onOpenURL { url in
                    // Handle your own links first.
                    if FunnelsGrove.shared.handle(url) { linked() }
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if FunnelsGrove.shared.handle(activity) { linked() }
                }
        }
    }

    @MainActor
    private func linked() {
        // A check that already finished saw the previous user: check again.
        Task { await refreshAccess() }
        // This app has no sign-in of its own, so the link is the login: see "App login".
        Task { try? await FunnelsGrove.shared.trackLogin() }
    }

    @MainActor
    private func refreshAccess() async {
        do {
            hasAccess = try await FunnelsGrove.shared.checkSubscription().isActive
        } catch is CancellationError {
            // The task was cancelled, for example the view went away: keep the current state.
        } catch {
            // FunnelsGroveError: see "Errors" below.
        }
    }
}
```

Which of the two handlers receives a Universal Link depends on the SwiftUI version and on the other handlers in your
app, so the example registers both. If both ever fire for one link, the second `handle` stores the same user again
and FunnelsGrove records the login once, so nothing breaks. Check a cold and a warm start on a device.

### UIKit

```swift
// AppDelegate.application(_:didFinishLaunchingWithOptions:)
FunnelsGrove.configure(publishableKey: "<FunnelsGrove SDK publishable key>")

// SceneDelegate
func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    // A cold start may come from a link; check access either way.
    connectionOptions.urlContexts.forEach { FunnelsGrove.shared.handle($0.url) }
    connectionOptions.userActivities.forEach { FunnelsGrove.shared.handle($0) }
    refreshAccess()
}

func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    // A custom-scheme link while the app runs.
    let linked = URLContexts.map { FunnelsGrove.shared.handle($0.url) }.contains(true)
    if linked { refreshAccess() }
}

func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    // A Universal Link while the app runs.
    if FunnelsGrove.shared.handle(userActivity) { refreshAccess() }
}
```

`refreshAccess()` is your own function that calls `checkSubscription()`, like the SwiftUI example. Record the login
as described in [App login](#app-login).

`FunnelsGrove.shared` stops the app if `configure` has not run, so configure it in
`application(_:didFinishLaunchingWithOptions:)`.

Check access at launch, after every `handle` that returns `true`, and at every paid-content boundary.

### App login

`trackLogin()` records "Logged into app" for the stored user in FunnelsGrove. The SDK never calls it by itself. Call
it:

- when your app signs the user in or up;
- in an app without a sign-in of its own, after `handle` returns `true`, as in the SwiftUI example;
- again after `handle` returns `true` while the user is signed in: the link may be another FunnelsGrove user's.

```swift
// After your own sign-in succeeds.
Task { try? await FunnelsGrove.shared.trackLogin() }
```

It returns `false` without a network call when no user is stored, so you can call it on every sign-in. A repeated call
for the same user records nothing new. The login goes to the user stored when the call starts.

### Email from the link

`FunnelsGrove.shared.email` is the address the buyer bought with, when a link carried it. Use it to prefill a sign-up
form or to show who is signed in. It is not verified: it is what the buyer typed in the funnel, and anyone with the
link has it. A newer link without an email keeps the address of the same user and clears it for another user.

## Behaviour

- **`handle(_:)`** accepts any URL with a `user_id` query parameter (non-empty, at most 256 UTF-8 bytes, no
  whitespace or control characters; the first one counts). It stores the ID together with the link's `email`, and a
  newer link replaces them. It returns `true` and records no login. Any other URL returns `false` and is left to the
  app. `userId` and `email` read what is stored. They are plain properties, not observable: copy them into your own
  state after `handle` returns `true` and after `reset()`.
- **`handle(_ activity:)`** uses the activity's `webpageURL` when its type is `NSUserActivityTypeBrowsingWeb`, and
  returns `false` otherwise.
- **`checkSubscription()`**:
  - without a stored ID returns at once, without a network call;
  - within 2 minutes of a link asks again after 1, 2, 4 and 8 s while FunnelsGrove still says inactive, because the
    payment webhook may lag: show progress instead of blocking launch on it;
  - retries a 503 once when `Retry-After` is 10 s or less;
  - answers `isKnownUser: false` when FunnelsGrove does not know the stored ID in your project, for example after a
    link from another project's funnel; the ID stays stored;
  - never caches the answer;
  - if a link or `reset()` changes the stored user while it waits, answers for the current user;
  - throws `CancellationError` when its task is cancelled (for example a SwiftUI `.task` whose view went away):
    treat that as no result, not as a failure.
- **`trackLogin()`** returns `false` without a stored ID, retries a 503 once like `checkSubscription()`, and throws
  `.unknownUser` when FunnelsGrove does not know the user in your project.
- **Test subscriptions.** `isActive` is `false` for Stripe test-mode subscriptions unless you pass
  `acceptTestSubscriptions: true` to `configure`. `isTest` is reported either way. Pass a flag that only your QA
  build configuration sets, for example `acceptTestSubscriptions: isQABuild`, never `true` in release builds.
- **Errors.** `FunnelsGroveError.configuration` for 400/401 (check the key), `.server(statusCode:)`,
  `.network(URLError)` and, from `trackLogin()`, `.unknownUser`. A 400 from `trackLogin()` can also mean that the same
  user ID exists in several funnels of the project: FunnelsGrove then needs a funnel ID that the link does not carry.
  Switch over `FunnelsGroveError` with a `default` case: later versions may add cases. The SDK does not cache the
  subscription answer, so offline every check for a stored user fails with `.network`: decide whether your app keeps
  the access it last saw or locks paid content.
- **Storage.** The ID and the email live in one keychain item with iCloud Keychain sync. It outlives app deletion in
  practice; Apple does not guarantee that. A reinstall or a new device of the same Apple ID can therefore show the
  previous user's access until a new link arrives. Call `reset()` on sign-out; iCloud Keychain then removes the user
  from other devices, where the app forgets it from its next launch.

## Testing a link

Tap a Universal Link in Notes or Messages: typed into Safari's address bar, it opens the web page instead of the app.
On the simulator, `xcrun simctl openurl booted 'myapp://open?user_id=u_test'` opens a custom-scheme link.

## Demo app

```bash
brew install xcodegen
cd Examples/FunnelsGroveDemo
cp Config/Local.xcconfig.example Config/Local.xcconfig   # set DEVELOPMENT_TEAM and FG_PUBLISHABLE_KEY
xcodegen generate
open FunnelsGroveDemo.xcodeproj
```

The demo opens `fgdemo://` links: set the App Store deeplink of your test FunnelsGrove project to `fgdemo://open`, or
paste a link into the demo. Universal Links are optional: see `Config/Local.xcconfig.example`. Track login records a
real login in that FunnelsGrove project.

## Tests

```bash
swift test
DEVICE_ID=$(xcrun simctl list devices available | grep -m1 -E '^\s+iPhone' | grep -oE '[0-9A-F-]{36}')
: "${DEVICE_ID:?no available iPhone simulator}"
xcodebuild test -scheme FunnelsGroveSDK -destination "platform=iOS Simulator,id=$DEVICE_ID"
```

The keychain is not unit-tested: an unsigned test bundle gets `errSecMissingEntitlement`. Check it in the demo app
(relaunch, then delete and reinstall).
