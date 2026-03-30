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
  <a href="#"><img src="https://img.shields.io/badge/platform-iOS%2010%2B-blue.svg?style=flat-square" alt="Platform"/></a>
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

Select the latest version and add to your target.

### CocoaPods

Add to your `Podfile`:

```ruby
pod 'PushEngage', '~> 0.0.6'
```

Then run:

```bash
pod install
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
    // Handle deep link or notification data
    print("Notification opened: \(result)")
}
```

**Objective-C:**

```objc
[PushEngage setNotificationOpenHandlerWithBlock:^(PENotificationOpenResult * _Nullable result) {
    // Handle deep link or notification data
    NSLog(@"Notification opened: %@", result);
}];
```

---

## API Overview

| Category | Methods |
|----------|---------|
| **Setup** | `setAppID`, `setInitialInfo`, `setEnvironment`, `enableLogging`, `swizzleInjection` |
| **Permissions** | `requestNotificationPermission`, `getNotificationPermissionStatus` |
| **Subscription** | `subscribe`, `unsubscribe`, `getSubscriptionStatus`, `getSubscriptionNotificationStatus` |
| **Subscriber Data** | `getSubscriberId`, `getSubscriberDetails`, `addProfile` |
| **Attributes** | `add`, `set`, `getSubscriberAttributes`, `deleteSubscriberAttributes` |
| **Segments** | `addSegments`, `removeSegments`, `addDynamicSegments` |
| **Events** | `sendTriggerEvent`, `sendGoal`, `addAlert` |
| **Campaigns** | `automatedNotification` (enable/disable) |
| **UI** | `setBadgeCount`, notification handlers (open, foreground) |
| **Extensions** | `getCustomUIPayLoad`, `didReceiveNotificationExtensionRequest`, `serviceExtensionTimeWillExpire` |
| **AppDelegate Forwarding** | `registerDeviceToServer`, `receivedRemoteNotification`, `didReceiveRemoteNotification`, `willPresentNotification` (required when swizzling is disabled) |

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
| iOS | 10.0+ |
| Xcode | 15+ (SPM) / 13+ (CocoaPods) |
| Swift | 5.9+ (SPM) / 5.0+ (CocoaPods) |
| Objective-C | Supported |

---

## Support

Having trouble? We're here to help.

- **Issues & Bugs** -- [Open a GitHub issue](https://github.com/awesomemotive/pushengage-ios-sdk/issues)
- **General Support** -- Contact us from your [PushEngage dashboard](https://app.pushengage.com) or email [care@pushengage.com](mailto:care@pushengage.com)

---

## License

MIT -- see [LICENSE](LICENSE) for details.


