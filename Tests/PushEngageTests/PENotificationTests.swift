import XCTest
@testable import PushEngage

final class PENotificationTests: XCTestCase {

    // MARK: - Basic parsing

    func test_init_parsesAlertTitleAndBodyFromAps() {
        let notification = PENotification(userInfo: Fixtures.basicAlertPayload)
        XCTAssertEqual(notification.title, "Hello")
        XCTAssertEqual(notification.body, "World")
        XCTAssertEqual(notification.subtitle, "Sub")
    }

    func test_init_parsesBadgeAndSoundFromAps() {
        let notification = PENotification(userInfo: Fixtures.basicAlertPayload)
        XCTAssertEqual(notification.badge, 1)
        XCTAssertEqual(notification.sound, "default")
        XCTAssertEqual(notification.mutableContent, 1)
    }

    func test_init_parsesTagAndLaunchURLFromCustomBlock() {
        let notification = PENotification(userInfo: Fixtures.basicAlertPayload)
        XCTAssertEqual(notification.tag, "tag-abc-123")
        XCTAssertEqual(notification.launchURL, "https://example.com/article/123")
    }

    func test_init_parsesAdditionalData() {
        let notification = PENotification(userInfo: Fixtures.basicAlertPayload)
        XCTAssertEqual(notification.additionalData?["foo"], "bar")
    }

    func test_init_preservesRawPayload() {
        let notification = PENotification(userInfo: Fixtures.basicAlertPayload)
        XCTAssertEqual(notification.rawPayload.count, Fixtures.basicAlertPayload.count)
    }

    // MARK: - Deep link field (Issue #3 reference — pe.dl preferred over pe.u downstream)

    func test_init_parsesDeeplinkingField() {
        let notification = PENotification(userInfo: Fixtures.deepLinkPayload)
        XCTAssertEqual(notification.deeplinking, "myapp://detail/123")
        XCTAssertEqual(notification.launchURL,
                       "https://example.com/article/123",
                       "launchURL (pe.u) should still be populated even when pe.dl is present")
    }

    // MARK: - Sponsored notifications

    func test_init_detectsSponsoredFlag() {
        let notification = PENotification(userInfo: Fixtures.sponsoredPayload)
        XCTAssertEqual(notification.isSponsered, 1)
    }

    func test_init_defaultsSponsoredFlagToZero() {
        let notification = PENotification(userInfo: Fixtures.basicAlertPayload)
        XCTAssertEqual(notification.isSponsered, 0)
    }

    // MARK: - Silent push

    func test_init_parsesSilentContentAvailable() {
        let notification = PENotification(userInfo: Fixtures.silentPayload)
        XCTAssertEqual(notification.contentAvailable, 1)
        XCTAssertNil(notification.title, "Silent push has no alert block")
        XCTAssertNil(notification.body)
    }

    // MARK: - Action buttons

    func test_init_parsesActionButtons() {
        let notification = PENotification(userInfo: Fixtures.actionButtonsPayload)
        XCTAssertEqual(notification.actionButtons?.count, 2)
        XCTAssertEqual(notification.actionButtons?[0].id, "yes-id")
        XCTAssertEqual(notification.actionButtons?[0].title, "Yes")
        XCTAssertEqual(notification.actionButtons?[1].id, "no-id")
        XCTAssertEqual(notification.actionButtons?[1].title, "No")
    }

    func test_init_actionButtons_isNilWhenAbsent() {
        let notification = PENotification(userInfo: Fixtures.basicAlertPayload)
        XCTAssertNil(notification.actionButtons)
    }

    // MARK: - Legacy custom-field fallback (no aps.alert)

    func test_init_fallsBackToCustomFields_whenApsAlertMissing() {
        let notification = PENotification(userInfo: Fixtures.legacyCustomFieldsPayload)
        XCTAssertEqual(notification.title, "Custom Title")
        XCTAssertEqual(notification.body, "Custom Body")
        XCTAssertEqual(notification.subtitle, "Custom Subtitle")
        XCTAssertEqual(notification.badge, 5,
                       "When aps.alert is missing, badge should come from pe.ba, not aps.badge")
        XCTAssertEqual(notification.sound, "custom.caf",
                       "When aps.alert is missing, sound should come from pe.s, not aps.sound")
    }

    func test_init_usesApsAlertWhenPresent_eveniIfCustomFieldsAreToo() {
        // basicAlertPayload has aps.alert set; ensure pe.t/pe.b/pe.ba are NOT used
        var payload: [AnyHashable: Any] = Fixtures.basicAlertPayload
        var custom = payload["pe"] as! [String: Any]
        custom["t"] = "SHOULD-NOT-USE-THIS"
        custom["b"] = "SHOULD-NOT-USE-THIS"
        payload["pe"] = custom

        let notification = PENotification(userInfo: payload)
        XCTAssertEqual(notification.title, "Hello", "aps.alert.title wins over pe.t")
        XCTAssertEqual(notification.body, "World", "aps.alert.body wins over pe.b")
    }

    // MARK: - Malformed / missing payloads (Issue #1 reference)

    func test_init_handlesMissingCustomBlock_gracefully() {
        let notification = PENotification(userInfo: Fixtures.missingCustomBlockPayload)
        XCTAssertEqual(notification.tag, "", "Missing pe block produces empty tag, not nil/crash")
        XCTAssertNil(notification.launchURL)
        XCTAssertNil(notification.deeplinking)
        XCTAssertEqual(notification.isSponsered, 0)
    }

    func test_init_handlesEmptyUserInfo_gracefully() {
        let notification = PENotification(userInfo: [:])
        XCTAssertEqual(notification.tag, "")
        XCTAssertNil(notification.title)
        XCTAssertNil(notification.body)
        XCTAssertEqual(notification.contentAvailable, 0)
        XCTAssertEqual(notification.mutableContent, 0)
    }

    // MARK: - PENotificationOpenResult wiring

    func test_openResult_holdsNotificationAndAction() {
        let notification = PENotification(userInfo: Fixtures.basicAlertPayload)
        let action = PENotificationAction(actionID: "btn-1", actionType: .taken)
        let result = PENotificationOpenResult(notification: notification, notficationAction: action)

        XCTAssertEqual(result.notification.tag, "tag-abc-123")
        XCTAssertEqual(result.notificationAction.actionID, "btn-1")
        XCTAssertEqual(result.notificationAction.actionType, .taken)
    }
}
