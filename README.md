<p align="center">
  <a href="https://www.pushengage.com">
    <img src="https://assetscdn.pushengage.com/site_assets/img/pushengage-logo.png" width="300" alt="PushEngage"/>
  </a>
</p>

<p align="center">
  <strong>iOS Push Notification SDK</strong><br/>
  Add rich push notifications to your iOS app in minutes.
</p>

<p align="center">
  <a href="https://cocoapods.org/pods/PushEngage"><img src="https://img.shields.io/cocoapods/v/PushEngage.svg?style=flat-square" alt="CocoaPods"/></a>
  <a href="https://swift.org/package-manager/"><img src="https://img.shields.io/badge/SPM-compatible-brightgreen.svg?style=flat-square" alt="Swift Package Manager"/></a>
  <a href="#"><img src="https://img.shields.io/badge/platform-iOS%2012%2B-blue.svg?style=flat-square" alt="Platform"/></a>
  <a href="#"><img src="https://img.shields.io/badge/language-Swift%20%7C%20Objective--C-orange.svg?style=flat-square" alt="Language"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg?style=flat-square" alt="License"/></a>
</p>

---

## Why PushEngage?

PushEngage is a complete push notification platform that supports **both web and mobile** from a single dashboard. Unlike Firebase Cloud Messaging alone, PushEngage gives you a full marketing toolkit on top of reliable delivery: audience segmentation, automated drip campaigns, A/B testing, analytics, and a no-code campaign builder that non-technical marketers can use.

**Key features of the iOS SDK:**

- **Rich Notifications** -- images, action buttons, badges, and custom sounds (iOS 10+)
- **Deep Linking** -- route users to specific screens in your app
- **Audience Segmentation** -- static and dynamic segments based on user behavior
- **Triggered Campaigns** -- send notifications based on in-app events
- **Goal Tracking** -- measure conversion events tied to notifications
- **Price Drop & Inventory Alerts** -- e-commerce trigger notifications
- **Subscriber Attributes** -- store custom key-value data per subscriber
- **Notification Analytics** -- track views, clicks, and conversions from the PushEngage dashboard
- **Swift & Objective-C** -- full support for both languages with example projects

---

## Installation

### Swift Package Manager (Recommended)

In Xcode, go to **File > Add Package Dependencies** and enter:

```
https://github.com/awesomemotive/pushengage-ios-sdk
```

Select the latest version, then link **PushEngage** to your app target and **PushEngageExtension** to your Notification Service / Content Extension target(s).

### CocoaPods

Add to your `Podfile`:

```ruby
# In your app target
pod 'PushEngage', '~> 1.0.0'

# In your Notification Service Extension (and Notification Content Extension) target(s)
pod 'PushEngageExtension', '~> 1.0.0'
```

> **Upgrading from 0.1.x:** the SDK is now split into two modules, and your
> notification extension targets need three changes:
>
> 1. **Dependency** — CocoaPods: replace `pod 'PushEngage'` with
>    `pod 'PushEngageExtension'` in the extension target(s); SPM: link the
>    `PushEngageExtension` product instead of `PushEngage`.
> 2. **Import** — `import PushEngage` → `import PushEngageExtension`
>    (Objective-C: `@import PushEngage;` → `@import PushEngageExtension;`).
> 3. **Call sites** — method names are unchanged, but the class is renamed:
>    replace the `PushEngage` prefix with `PushEngageExtension`, e.g.
>    `PushEngage.didReceiveNotificationExtensionRequest(...)` becomes
>    `PushEngageExtension.didReceiveNotificationExtensionRequest(...)`
>    (Objective-C: `[PushEngage ...]` → `[PushEngageExtension ...]`).
>
> App-target code is unchanged — keep `pod 'PushEngage'` / the `PushEngage`
> product there, and all existing app APIs work as before.

> **Objective-C with modules disabled:** if an app target builds with
> `CLANG_ENABLE_MODULES = NO` (or uses Objective-C++), also
> `#import <PushEngageExtension/PushEngageExtension-Swift.h>` where you use the
> notification model types (`PENotification`, `PENotificationOpenResult`,
> `SubscriberDetailsData`) — without modules, the generated `PushEngage-Swift.h`
> only forward-declares types defined in the `PushEngageExtension` module.
> Targets with modules enabled (the default) need nothing extra.

Then run:

```bash
pod install
```

> **Upgrading from 0.1.x with CocoaPods:** run `pod deintegrate && pod install`
> (not `pod update`) so the cached single-module `PushEngage.swiftmodule` is
> fully cleared. If your team uses binary caching for pods (XCRemoteCache,
> Bazel, etc.), invalidate the cached PushEngage framework as well.

### Configure the App Group

The app and its notification extensions share SDK state (subscriber identity,
the logging flag, server-configured endpoints) through an App Group container.
Without it, extension processes start with a blank state on every delivery.

1. In Xcode, add the **App Groups** capability with the same group ID (e.g.
   `group.com.yourcompany.yourapp`) to your app target **and** every
   notification extension target.
2. Add the group ID to the `Info.plist` of the app target and of each
   extension target:

```xml
<key>PushEngage_App_Group_Key</key>
<string>group.com.yourcompany.yourapp</string>
```

---

## Quick Start

### 1. Initialize the SDK

**Swift:**

```swift
import PushEngage

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // Initialize PushEngage
        PushEngage.setAppID(id: "YOUR_APP_ID")
        PushEngage.setInitialInfo(for: application, with: launchOptions)

        return true
    }
}
```

**Objective-C:**

```objc
#import <PushEngage/PushEngage-Swift.h>

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    [PushEngage setAppIDWithId:@"YOUR_APP_ID"];
    [PushEngage setInitialInfoFor:application with:launchOptions];

    return YES;
}
```

### 2. Request Permission & Subscribe

**Swift:**

```swift
PushEngage.requestNotificationPermission { granted, error in
    if granted {
        print("User subscribed to push notifications")
    }
}
```

**Objective-C:**

```objc
[PushEngage requestNotificationPermissionWithCompletion:^(BOOL granted, NSError * _Nullable error) {
    if (granted) {
        NSLog(@"User subscribed to push notifications");
    }
}];
```

### 3. Handle Notification Opens

**Swift:**

```swift
PushEngage.setNotificationOpenHandler { result in
    // actionID is nil when the SDK already opened the URL itself
    // (PushEngageAutoHandleDeeplinkURL = YES in Info.plist) — don't navigate then.
    guard let deepLink = result.notificationAction.actionID else { return }
    print("Notification opened with deep link: \(deepLink)")
}
```

**Objective-C:**

```objc
[PushEngage setNotificationOpenHandlerWithBlock:^(PENotificationOpenResult * _Nullable result) {
    // actionID is nil when the SDK already opened the URL itself
    // (PushEngageAutoHandleDeeplinkURL = YES in Info.plist) — don't navigate then.
    NSString *deepLink = result.notificationAction.actionID;
    if (deepLink == nil) { return; }
    NSLog(@"Notification opened with deep link: %@", deepLink);
}];
```

---

## API Overview

| Category | Methods |
|----------|---------|
| **Setup** | `setAppID`, `setInitialInfo`, `setEnvironment`, `enableLogging`, `swizzleInjection`, `setBadgeCount`, `getSdkVersion` |
| **Permissions** | `requestNotificationPermission`, `getNotificationPermissionStatus` |
| **Subscription** | `subscribe`, `unsubscribe`, `getSubscriptionStatus`, `getSubscriptionNotificationStatus` |
| **User Identity** | `identify`, `logout`, `addProfile` |
| **Subscriber Data** | `getSubscriberId`, `getSubscriberDetails` |
| **Attributes** | `addSubscriberAttributes`, `setSubscriberAttributes`, `getSubscriberAttributes`, `deleteSubscriberAttributes` |
| **Segments** | `addSegments`, `removeSegments`, `addDynamicSegments` |
| **Events** | `sendTriggerEvent`, `sendGoal`, `trackEvent`, `addAlert` |
| **Campaigns** | `automatedNotification` (enable/disable) |
| **Notification Handlers** | `setNotificationOpenHandler`, `setNotificationWillShowInForegroundHandler` |
| **AppDelegate Forwarding** | `registerDeviceToServer`, `receivedRemoteNotification`, `didReceiveRemoteNotification`, `willPresentNotification` (required when swizzling is disabled) |

**Notification Service / Content Extension API** (call on `PushEngageExtension`, from your extension target):

| Method | Where to call it |
|--------|------------------|
| `didReceiveNotificationExtensionRequest(_:bestContentHandler:)` | `UNNotificationServiceExtension.didReceive(_:withContentHandler:)` |
| `serviceExtensionTimeWillExpire(_:content:)` | `UNNotificationServiceExtension.serviceExtensionTimeWillExpire()` |
| `getCustomUIPayLoad(for:)` | `UNNotificationContentExtension.didReceive(_:)` |

SDK logging inside extension processes follows the app's
`PushEngage.enableLogging` setting automatically (persisted via the shared app
group) — no extra call is needed in extension code.

> **Threading:** completion handlers are not guaranteed to be invoked on the
> main queue — network-backed calls (subscriber data, attributes, goals,
> events) complete on a background queue. Dispatch to the main queue before
> updating UI from a completion handler.

Full API reference: [iOS SDK Public APIs](https://pushengage.com/api/mobile-sdk/iOS-sdk)

---

## Example Projects

This repo includes two complete example apps:

- **`PushEngageExample/`** -- Swift example with notification service and content extensions
- **`PushEngageExampleObjectiveC/`** -- Objective-C example demonstrating the same features

---

## Documentation

- [Installation Guide](https://www.pushengage.com/documentation/how-to-set-up-ios-app-push-notifications-with-pushengage/) -- step-by-step setup
- [APNS Certificate Guide](https://www.pushengage.com/documentation/guide-to-creating-ios-apns-certificate/) -- creating your Apple Push Notification certificate
- [iOS SDK API Reference](https://pushengage.com/api/mobile-sdk/iOS-sdk) -- complete API docs
- [PushEngage Dashboard](https://app.pushengage.com) -- manage campaigns and analytics

---

## Requirements

| Requirement | Minimum |
|-------------|---------|
| iOS | 12.0+ |
| Xcode | 15+ |
| Swift | 5.9+ |
| Objective-C | Supported |

---

## Support

Having trouble? We're here to help.

- **Issues & Bugs** -- [Open a GitHub issue](https://github.com/awesomemotive/pushengage-ios-sdk/issues)
- **General Support** -- Contact us from your [PushEngage dashboard](https://app.pushengage.com) or email [care@pushengage.com](mailto:care@pushengage.com)

---

## License

MIT -- see [LICENSE](LICENSE) for details.
