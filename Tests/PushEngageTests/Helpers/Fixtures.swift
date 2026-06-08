import Foundation
@testable import PushEngage

/// Reusable APNs payloads and domain-model factories for tests.
enum Fixtures {

    // MARK: - APNs payloads

    /// Standard alert with `pe.u` deep link and tag.
    static let basicAlertPayload: [AnyHashable: Any] = [
        "aps": [
            "alert": ["title": "Hello", "body": "World", "subtitle": "Sub"],
            "badge": 1,
            "sound": "default",
            "mutable-content": 1,
        ],
        "pe": [
            "tag": "tag-abc-123",
            "u": "https://example.com/article/123",
            "ad": ["foo": "bar"],
        ],
    ]

    /// Payload using deep link `pe.dl` (preferred over `pe.u`).
    static let deepLinkPayload: [AnyHashable: Any] = [
        "aps": [
            "alert": ["title": "Open", "body": "Tap"],
        ],
        "pe": [
            "tag": "deeplink-tag",
            "u": "https://example.com/article/123",
            "dl": "myapp://detail/123",
        ],
    ]

    /// Sponsored push (`rf == 1`).
    static let sponsoredPayload: [AnyHashable: Any] = [
        "aps": [
            "alert": ["title": "Ad", "body": "Promoted"],
        ],
        "pe": [
            "tag": "sponsored-tag",
            "rf": 1,
            "u": "https://example.com/sponsored",
        ],
    ]

    /// Silent push (`content-available == 1`).
    static let silentPayload: [AnyHashable: Any] = [
        "aps": [
            "content-available": 1,
        ],
        "pe": [
            "tag": "silent-tag",
        ],
    ]

    /// Payload with two action buttons.
    static let actionButtonsPayload: [AnyHashable: Any] = [
        "aps": [
            "alert": ["title": "Pick", "body": "Choose"],
        ],
        "pe": [
            "tag": "btn-tag",
            "ab": [
                ["a": "yes-id", "b": "Yes"],
                ["a": "no-id",  "b": "No"],
            ],
        ],
    ]

    /// Payload using legacy `pe.t` / `pe.b` title/body fields (no `aps.alert`).
    static let legacyCustomFieldsPayload: [AnyHashable: Any] = [
        "aps": [
            "badge": 7,
            "sound": "ping.caf",
        ],
        "pe": [
            "tag": "legacy-tag",
            "t": "Custom Title",
            "b": "Custom Body",
            "sb": "Custom Subtitle",
            "ba": 5,
            "s": "custom.caf",
        ],
    ]

    /// Empty / malformed: missing `pe` block entirely.
    static let missingCustomBlockPayload: [AnyHashable: Any] = [
        "aps": ["alert": ["title": "No PE", "body": "Bare"]],
    ]

    // MARK: - Domain-model factories

    static func makeSubscriptionInfo(siteId: Int = 1234,
                                     profileId: String? = "profile-1") -> SubscriptionInfo {
        var info = SubscriptionInfo()
        info.siteID = siteId
        info.profileID = profileId
        info.device = "iPhone"
        info.deviceType = "ios"
        info.deviceVersion = "17.0"
        info.deviceModel = "iPhone15,2"
        info.deviceManufacturer = "Apple"
        info.timezone = "Asia/Kolkata"
        info.language = "en"
        info.userAgent = "PushEngage-Tests"
        info.totalScreenWidthHeight = "390.0 x 844.0"
        info.host = "example.com"
        info.attributes = ["key": "value"]
        info.isNotificationEnable = 0
        info.certEnv = "production"
        info.subscription = Subscription(endpoint: "https://apns/token", projectID: nil)
        return info
    }

    static func makeSubscriberDetails(siteId: Int = 1234,
                                      tokenHash: String = "hash-1") -> SubscriberDetails {
        var details = SubscriberDetails()
        details.siteID = siteId
        details.deviceTokenHash = tokenHash
        details.deviceToken = "raw-token"
        details.isUnSubscribed = 0
        details.triggerStatus = 1
        details.profileId = "profile-1"
        return details
    }

    static func makeSubscriberUpgrade() -> SubscriberUpgrade {
        SubscriberUpgrade(deviceTokenHash: "hash-1",
                          subscription: Subscription(endpoint: "https://apns/token",
                                                     projectID: nil),
                          siteId: 1234)
    }

    static func makeSponsoredPush(tag: String = "sponsored-tag") -> SponsoredPush {
        SponsoredPush(tag: tag, postback: nil)
    }
}
