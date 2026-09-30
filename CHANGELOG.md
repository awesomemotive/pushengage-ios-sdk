# Changelog

All notable changes to the PushEngage iOS SDK are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-09-30

### Added
- **In-App Messaging.** Design messages on the PushEngage dashboard and show them inside
  your app — no push subscription or notification permission required.
  - Four layouts: top banner, bottom banner, center modal and full screen, rendered as
    designed in the dashboard editor and sized for iPhone, iPad and landscape.
  - Show a message when the app opens (optionally after a delay) or when your app reports
    an event with `triggerIAMEvent(...)`, including conditions on the event's parameters.
  - Target messages with audience rules, segments and subscriber attributes, schedule start
    and end dates, and control how often each user sees them (one time, recurring or
    capped) and which shows first when several are eligible.
  - Button actions to open a URL, dismiss, or run a custom action in your app via
    `setIAMCustomActionHandler(_:)`, which receives the dashboard's action name in
    `parameters["action"]`.
  - A "request notification permission" button that shows the system prompt and
    subscribes the user as soon as they allow it — no extra code in your app.
  - Impressions, clicks and closes reported to the dashboard, queued while offline and
    sent automatically when connectivity returns.
- **Background campaign refresh (opt-in).** Campaigns stay fresh even while the app is in
  the background, using `BGTaskScheduler`. To enable it, add
  `com.pushengage.iam.refresh` to `BGTaskSchedulerPermittedIdentifiers` in your
  `Info.plist` and turn on **Background Modes → Background fetch**; without it, campaigns
  refresh on app open as before.

### Changed
- The minimum supported iOS version is now **15.0**, the lowest version Xcode 27 builds for.

## [1.0.0] - 2026-07-07

### Changed
- **The SDK now ships as two modules**, so notification extensions only link what they
  need:
  - `PushEngage` — link to your app target (unchanged).
  - `PushEngageExtension` — link to your Notification Service and Notification Content
    extension targets, and call `PushEngageExtension.didReceiveNotificationExtensionRequest(...)`
    there. See the README's "Upgrading from 0.1.x" section for the full migration steps.

### Improved
- Reliable push delivery for CocoaPods integrations, including development builds.
- Click and view tracking completes even when the app is suspended.
- `PushEngage.enableLogging` now also applies inside notification extensions.
- Errors are always written to the unified logging system (privacy-redacted on
  end-user devices), so integration problems are easy to diagnose.

## [0.1.0] - 2026-06-08

### Added
- **User identification.** `identify(fields:completionHandler:)` links a subscriber to your
  own user fields (name, email, phone, profile ID and more), and
  `logout(fieldNames:completionHandler:)` clears them while keeping the device subscribed.
- **Custom event tracking.** `trackEvent(name:properties:...)` sends in-app actions such as
  add-to-cart or purchase, so they can start or stop workflow campaigns.
- `getSdkVersion()` returns the SDK version, handy for support and about screens.

## [0.0.6] - 2025-08-21

### Added
- Notification permission APIs: `requestNotificationPermission(completion:)` now reports
  the result, and `getNotificationPermissionStatus()` returns the current status.
- Subscription control: `subscribe`, `unsubscribe`, `getSubscriptionStatus`,
  `getSubscriptionNotificationStatus` and `getSubscriberId`, each with a completion
  handler.

### Improved
- `setEnvironment(environment:)` now takes a typed `PEEnvironment`.

## [0.0.5] - 2024-11-19

### Added
- Custom URL schemes for deep links.

### Improved
- More reliable deep link handling.

## [0.0.4] - 2024-08-19

### Added
- Swift Package Manager support.

## [0.0.3] - 2024-06-05

### Added
- Trigger campaigns.
- Goal tracking.

## [0.0.2] - 2023-11-24

### Improved
- General performance improvements.

## [0.0.1] - 2021-10-07

### Added
- Initial release: push notifications for iOS apps.

[1.1.0]: https://github.com/awesomemotive/pushengage-ios-sdk/releases/tag/1.1.0
[1.0.0]: https://github.com/awesomemotive/pushengage-ios-sdk/releases/tag/1.0.0
[0.1.0]: https://github.com/awesomemotive/pushengage-ios-sdk/releases/tag/0.1.0
[0.0.6]: https://github.com/awesomemotive/pushengage-ios-sdk/releases/tag/0.0.6
[0.0.5]: https://github.com/awesomemotive/pushengage-ios-sdk/releases/tag/0.0.5
[0.0.4]: https://github.com/awesomemotive/pushengage-ios-sdk/releases/tag/0.0.4
[0.0.3]: https://github.com/awesomemotive/pushengage-ios-sdk/releases/tag/0.0.3
[0.0.2]: https://github.com/awesomemotive/pushengage-ios-sdk/releases/tag/0.0.2
[0.0.1]: https://github.com/awesomemotive/pushengage-ios-sdk/releases/tag/0.0.1
