# FunnelsGroveSDK

Links a FunnelsGrove web purchase to your iOS app. After checkout, the funnel's "Open app now" button and the purchase
email open your app with a link that carries the buyer's FunnelsGrove user ID and email, for example
`myapp://open?user_id=u_…&email=…`. The SDK keeps them in the keychain, asks FunnelsGrove whether the user's
subscription is active, and records "Logged into app" in FunnelsGrove when your app says the user signed in.

The link works like a bearer token: whoever opens it in your app gets its user's subscription, and the link carries
the buyer's email. A forwarded link shares the access, so don't treat `isActive` as proof that the person in the app
paid. Don't log the link, the user ID or the email, or send them to analytics, attribution or support tools.

## How a buyer reaches the app

- The buyer taps "Open app now" on the funnel's success page, or the link in the purchase email. If the app is
  installed, iOS opens it with the link.
- If the app is not installed, the link cannot open it. A custom-scheme link fails in the browser; a Web link opens
  its page on your domain, so make that page send the buyer to the App Store. The buyer installs the app and taps
  "Open app now" again: there is no deferred deep link.
- The funnel also opens the link once by itself. iOS often does not open the app for that, so the purchase is linked
  by a later tap.
- In-app browsers such as TikTok's or Instagram's often don't open the app at all.

## Requirements

- iOS 15+, Xcode 16+.
- The SDK publishable key of your FunnelsGrove project. Never put a secret key (`sdk_sec_…`) or an organization API
  key (`fg_key_…`) in an app: anyone who downloads it can read the key, so `configure` stops the app if you pass one,
  or an empty key.
- A FunnelsGrove project whose funnel links to your app, see below.

## Set up your FunnelsGrove project

In the project settings, point these fields at your app, then publish the funnel. Set both if you can, at least one:

- **App Store deeplink**: a link with your app's own scheme, for example `myapp://open`. On iOS, "Open app now"
  uses it first.
- **Web link**: a Universal Link on your domain, for example `https://go.myapp.com/open`. The purchase email uses it
  first.

With only an App Store deeplink, the purchase email carries your custom scheme, which many email apps don't open: a
buyer who installs the app after checkout may then have no working link to it.

FunnelsGrove adds `user_id`, `email` and the first-touch campaign parameters to both. Check that "Open app now" in the
published funnel opens your app and that the link carries `user_id`.

## Install

Add the package `https://github.com/The-Solid-Grove/funnelsgrove-ios-sdk.git` and link the `FunnelsGroveSDK`
product. The repository is private: ask the FunnelsGrove team for access, and add the GitHub account that has it in
Xcode → Settings → Accounts and on your CI. There is no release tag yet: add the package by branch `main`, then
pin a commit (Dependency Rule → Commit) before you release.

## Links into the app

The SDK accepts any link with a `user_id`, whatever its scheme and host. Which links open your app is up to you:

- **Custom scheme.** Add a URL type with your scheme: Target → Info → URL Types, or `CFBundleURLTypes`.
- **Universal Links.** Add the Associated Domains capability with `applinks:<your domain>` and serve an
  `apple-app-site-association` file at `https://<your domain>/.well-known/apple-app-site-association` that lists
  `<Team ID>.<bundle ID>` for the Web link's path, for example `/open`. Apple's CDN can take up to 24 hours to pick up
  a new file, so publish it before you ship the build.
  - Debug builds can use `applinks:<your domain>?mode=developer`. The device then reads the file from your server
    directly. This needs Developer Mode (Settings → Privacy & Security) and Settings → Developer → Associated
    Domains Development.
  - Release and TestFlight builds must use the plain `applinks:<your domain>`. One entitlements file can serve both:
    write `applinks:<your domain>$(APPLINKS_MODE)` and set the build setting `APPLINKS_MODE` to `?mode=developer` in
    Debug only. Check the entitlement of the archived app before you upload it.
  - Serve a page at the Web link's path, for example a redirect to your App Store page: buyers without the app, in
    in-app browsers or on another device land there. Its URL carries the user ID and the email, so keep analytics
    scripts off that page and the query out of your server and CDN logs.
  - Use a domain other than the funnel's: iOS opens a Universal Link tapped on a page of the same domain in the
    browser, not in the app.

If your app has its own links with a `user_id` parameter, handle them before the SDK: it takes any link with a valid
`user_id` for a FunnelsGrove link.

If `handle` returns `true`, don't pass the URL as is to attribution or deep-link SDKs such as AppsFlyer, Adjust or
Branch: they usually send the URLs they get to their servers, user ID and email included. Remove `user_id` and `email`
first if you need the campaign parameters there.

## Use

`FunnelsGrove` is `@MainActor`: call it from the main actor. SwiftUI views and the app and scene delegates already
are.

### SwiftUI

```swift
import FunnelsGroveSDK
import SwiftUI

@main
struct MyApp: App {
    // false until the first check answers: while it runs, show progress rather than the paywall (keep your own
    // checking state).
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
                    // Route your own links before this call: the SDK takes any link with a user_id.
                    if FunnelsGrove.shared.handle(url) { linked() }
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    // Your own Universal Links first, here too.
                    if FunnelsGrove.shared.handle(activity) { linked() }
                }
        }
    }

    @MainActor
    private func linked() {
        // A check that already finished saw the previous user: check again.
        Task { await refreshAccess() }
        // This app has no sign-in of its own, so the link is the login. With your own sign-in, call trackLogin()
        // here only while the user is signed in: see "App login".
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

// SceneDelegate. Route your own links before each handle call.
private var hasAccess = false   // drive your UI from it

func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    // A cold start may come from a link; check access either way.
    let fromURL = connectionOptions.urlContexts.map { FunnelsGrove.shared.handle($0.url) }.contains(true)
    let fromActivity = connectionOptions.userActivities.map { FunnelsGrove.shared.handle($0) }.contains(true)
    if fromURL || fromActivity { linked() } else { refreshAccess() }
}

func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    // A custom-scheme link while the app runs.
    if URLContexts.map({ FunnelsGrove.shared.handle($0.url) }).contains(true) { linked() }
}

func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    // A Universal Link while the app runs.
    if FunnelsGrove.shared.handle(userActivity) { linked() }
}

private func linked() {
    // A check that already finished saw the previous user: check again.
    refreshAccess()
    // This app has no sign-in of its own, so the link is the login. With your own sign-in, call trackLogin()
    // here only while the user is signed in: see "App login".
    Task { try? await FunnelsGrove.shared.trackLogin() }
}

private func refreshAccess() {
    Task {
        do {
            hasAccess = try await FunnelsGrove.shared.checkSubscription().isActive
        } catch is CancellationError {
            // The task was cancelled: keep the current state.
        } catch {
            // FunnelsGroveError: see "Errors" below.
        }
    }
}
```

Without scenes, handle the same links in `application(_:open:options:)` and
`application(_:continue:restorationHandler:)`; iOS calls them on a cold start too.

`FunnelsGrove.shared` stops the app if `configure` has not run, so configure it in
`application(_:didFinishLaunchingWithOptions:)`.

Check access at launch, when the app returns to the foreground, after every `handle` that returns `true`, and at
every paid-content boundary.

### App login

`trackLogin()` records "Logged into app" for the stored user in FunnelsGrove. The SDK never calls it by itself. Call
it:

- when the user signs in or up in your app (a session your app restores at launch needs no call);
- in an app without a sign-in of its own, after `handle` returns `true`, as in the examples above;
- again after `handle` returns `true` while the user is signed in: the link may be another FunnelsGrove user's.

```swift
// After your own sign-in succeeds.
Task { try? await FunnelsGrove.shared.trackLogin() }
```

It returns `false` without a network call when no user is stored, so you can call it on every sign-in, and `true` once
FunnelsGrove has the login. A repeated call for the same user records nothing new. The login goes to the user stored
when the call starts.

The SDK doesn't retry later. After `.network` or `.server`, call `trackLogin()` again at the next chance, for example
at the next launch: the first call may have reached FunnelsGrove, and a repeat records nothing new. `.unknownUser` and
`.configuration` won't succeed on a retry.

### Email from the link

`FunnelsGrove.shared.email` is the address the buyer bought with, when a link carried it. Use it to prefill a sign-up
form or to show who is signed in. It is not verified: it is what the buyer typed in the funnel, anyone with the link
has it, and anyone can make a link with any address. Never sign the user in to an existing account, or merge
accounts, by this email without verifying the address first. A newer link without an email keeps the address of the
same user and clears it for another user.

## Behaviour

- **`handle(_:)`** accepts any URL with a `user_id` query parameter (non-empty, at most 256 UTF-8 bytes, no
  whitespace or control characters; the first one counts). It stores the ID together with the link's `email`, and a
  newer link replaces them. It returns `true` and records no login. Any other URL returns `false` and is left to the
  app. `userId` and `email` read what is stored. They are plain properties, not observable: copy them into your own
  state after `handle` returns `true` and after `reset()`.
- **`handle(_ userActivity:)`** uses the activity's `webpageURL` when its type is `NSUserActivityTypeBrowsingWeb`,
  and returns `false` otherwise.
- **`checkSubscription()`**:
  - without a stored ID returns at once, without a network call;
  - within 2 minutes of a link asks again after waits of 1, 2, 4 and 8 s (15 s of waiting, plus the requests, each
    with a 10 s timeout) while FunnelsGrove still says inactive, because the payment webhook may lag: show progress
    instead of blocking launch on it;
  - retries a 503 once when `Retry-After` is 10 s or less;
  - answers `isKnownUser: false` when FunnelsGrove does not know the stored ID in your project, for example after a
    link from another project's funnel; the ID stays stored. If every user answers `isKnownUser: false`, the
    publishable key is probably from another project than the funnel;
  - never caches the answer;
  - if a link or `reset()` changes the stored user while it waits, answers for the current user;
  - throws `CancellationError` when its task is cancelled (for example a SwiftUI `.task` whose view went away):
    treat that as no result, not as a failure.
- **`trackLogin()`** returns `false` without a stored ID and `true` once FunnelsGrove has the login. It retries a 503
  once like `checkSubscription()`. It throws `.unknownUser` when FunnelsGrove does not know the user in your project,
  another `FunnelsGroveError` (see Errors), or `CancellationError` when its task is cancelled.
- **Test subscriptions.** `isActive` is `false` for Stripe test-mode subscriptions unless you pass
  `acceptTestSubscriptions: true` to `configure`. `isTest` is reported either way. Whoever reaches a test-mode funnel
  can pay with Stripe's test card, so a build that accepts test subscriptions gives paid access away. Pass a flag that
  only Debug or a separate QA build configuration sets, for example `acceptTestSubscriptions: isQABuild` with
  `isQABuild` set under `#if DEBUG || QA`, where `QA` is in the Active Compilation Conditions of your QA configuration
  only. Never set it in the configuration you archive for the App Store: its TestFlight build is the binary you then
  release. For App Review, give the reviewers the link of a live-mode user with an active subscription.
- **Errors.** Both calls throw `FunnelsGroveError`, or `CancellationError`, which is no result rather than a failure:
  - `.configuration`: FunnelsGrove answered 400 or 401, usually a wrong `publishableKey`. From `trackLogin()`, a 400
    can also mean that the same user ID exists in several funnels of the project: FunnelsGrove then needs a funnel ID
    that the link does not carry, and this version cannot record that user's login. Don't retry.
  - `.unknownUser`, from `trackLogin()` only: FunnelsGrove has no such user in your project. Don't retry.
  - `.server(statusCode:)` and `.network(URLError)`: try again later.

  Handle the cases you act on and end with `default`: later versions may add cases. The SDK does not cache the
  subscription answer, so offline every check for a stored user fails with `.network`: decide whether your app keeps
  the access it last saw or locks paid content. If you keep the last answer, store it with `status.userId` and use it
  only while `userId` is the same.
- **Storage.** The ID and the email live in one keychain item with iCloud Keychain sync. It outlives app deletion in
  practice; Apple does not guarantee that. A reinstall or a new device of the same Apple ID can therefore show the
  previous user's access until a new link arrives. Call `reset()` on sign-out. iCloud Keychain then removes the user
  from the user's other devices too, where the app forgets it from its next launch. Access returns only with a new
  link, for example the one in the purchase email.
- **Network.** The SDK sends only the stored user ID, with your publishable key, to `sdk-api.funnelsgrove.com`. The
  email leaves the device only through iCloud Keychain.

## Testing a link

Tap a Universal Link in Notes or Messages: typed into Safari's address bar, it opens the web page instead of the app.
If a Universal Link that worked starts opening Safari, the domain was opened in Safari once: long-press the link and
choose to open it in the app. On the simulator, `xcrun simctl openurl booted 'myapp://open?user_id=u_test'` opens a
custom-scheme link after you tap Open in the prompt. A made-up `user_id` answers `isKnownUser: false`, after about
15 s of polling, because the link is fresh.

## Demo app

```bash
brew install xcodegen
cd Examples/FunnelsGroveDemo
cp Config/Local.xcconfig.example Config/Local.xcconfig   # set DEVELOPMENT_TEAM and FG_PUBLISHABLE_KEY
xcodegen generate
open FunnelsGroveDemo.xcodeproj
```

The demo needs iOS 17. On a device, also set a `PRODUCT_BUNDLE_IDENTIFIER` that your team can sign. The demo opens
`fgdemo://` links: set the App Store deeplink of your test FunnelsGrove project to `fgdemo://open`, or paste a link
into the demo. Universal Links are optional: see `Config/Local.xcconfig.example`. Track login records a real login in
that FunnelsGrove project. The demo accepts test subscriptions: don't copy its `configure` call.

## Tests

```bash
swift test
DEVICE_ID=$(xcrun simctl list devices available | grep -m1 -E '^\s+iPhone' | grep -oE '[0-9A-F-]{36}')
: "${DEVICE_ID:?no available iPhone simulator}"
xcodebuild test -scheme FunnelsGroveSDK -destination "platform=iOS Simulator,id=$DEVICE_ID"
```

The keychain is not unit-tested: an unsigned test bundle gets `errSecMissingEntitlement`. Check it in the demo app
(relaunch, then delete and reinstall).
