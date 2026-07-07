import XCTest
import UserNotifications
@testable import PushEngage
@testable import PushEngageExtension
final class NotificationExtensionManagerTests: XCTestCase {

    private var network: MockNetworkRouter!
    private var lifecycle: MockNotificationLifeCycleService!
    private var userDefaults: MockUserDefaultsService!
    private var sut: NotificationExtensionManager!

    override func setUp() {
        super.setUp()
        network = MockNetworkRouter()
        lifecycle = MockNotificationLifeCycleService()
        userDefaults = MockUserDefaultsService()
        sut = NotificationExtensionManager(networkService: network,
                                           notifcationLifeCycleService: lifecycle,
                                           userDefaultDatasource: userDefaults)
    }

    override func tearDown() {
        sut = nil
        userDefaults = nil
        lifecycle = nil
        network = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeRequest(userInfo: [AnyHashable: Any],
                             categoryIdentifier: String = "") -> (UNNotificationRequest, UNMutableNotificationContent) {
        let content = UNMutableNotificationContent()
        content.userInfo = userInfo
        content.categoryIdentifier = categoryIdentifier
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        return (request, content)
    }

    // MARK: - didReceiveNotificationExtensionRequest

    func test_didReceive_nonPEPayload_isNoOp() {
        let (request, content) = makeRequest(userInfo: ["aps": ["alert": "x"]])
        sut.didReceiveNotificationExtensionRequest(request, bestContentHandler: content)

        XCTAssertTrue(lifecycle.lifecycleCalls.isEmpty,
                      "Non-PE payload should not trigger lifecycle.viewed")
        XCTAssertNil(content.sound,
                     "Non-PE payload should not touch the content")
    }

    func test_didReceive_pePayload_setsDefaultSound_whenNotificationSoundAbsent() {
        let payload = Fixtures.missingCustomBlockPayload   // no pe.tag → not PE
        var pePayload = payload
        pePayload["pe"] = ["tag": "t-1"]   // mark as PE but no sound
        let (request, content) = makeRequest(userInfo: pePayload)

        sut.didReceiveNotificationExtensionRequest(request, bestContentHandler: content)

        XCTAssertNotNil(content.sound,
                        "PE payload without sound should default to UNNotificationSound.default")
    }

    func test_didReceive_pePayload_setsCustomSound_whenProvided() {
        let (request, content) = makeRequest(userInfo: Fixtures.legacyCustomFieldsPayload)
        sut.didReceiveNotificationExtensionRequest(request, bestContentHandler: content)

        XCTAssertNotNil(content.sound)
    }

    func test_didReceive_pePayload_callsLifecycleViewedWithTag() {
        let (request, content) = makeRequest(userInfo: Fixtures.basicAlertPayload)
        userDefaults.subscriberHash = "test-hash"

        sut.didReceiveNotificationExtensionRequest(request, bestContentHandler: content)

        XCTAssertEqual(lifecycle.lifecycleCalls.count, 1)
        XCTAssertEqual(lifecycle.lifecycleCalls.first?.action, "viewed")
        XCTAssertEqual(lifecycle.lifecycleCalls.first?.deviceHash, "test-hash")
        XCTAssertEqual(lifecycle.lifecycleCalls.first?.notificationId, "tag-abc-123")
        XCTAssertNil(lifecycle.lifecycleCalls.first?.actionId)
    }

    func test_didReceive_badge_writesThroughToUserDefaults() {
        let (request, content) = makeRequest(userInfo: Fixtures.basicAlertPayload)
        sut.didReceiveNotificationExtensionRequest(request, bestContentHandler: content)

        // basicAlertPayload has aps.badge = 1
        XCTAssertEqual(userDefaults.badgeCount, 1)
    }

    func test_didReceive_badgeIncrement_addsToStoredCount() {
        userDefaults.badgeCount = 10
        var payload: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "T", "body": "B"]],
            "pe": ["tag": "t-bi", "bi": 3] as [String: Any],
        ]
        let (request, content) = makeRequest(userInfo: payload)
        _ = payload

        sut.didReceiveNotificationExtensionRequest(request, bestContentHandler: content)

        XCTAssertEqual(userDefaults.badgeCount, 13,
                       "10 + 3 increment = 13")
        XCTAssertEqual(content.badge?.intValue, 13)
    }

    func test_didReceive_negativeIncrement_clampsToZero() {
        userDefaults.badgeCount = 2
        let payload: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "T", "body": "B"]],
            "pe": ["tag": "t", "bi": -10] as [String: Any],
        ]
        let (request, content) = makeRequest(userInfo: payload)

        sut.didReceiveNotificationExtensionRequest(request, bestContentHandler: content)

        XCTAssertEqual(userDefaults.badgeCount, 0,
                       "Negative increment must not produce a negative badge")
        XCTAssertEqual(content.badge?.intValue, 0)
    }

    // MARK: - serviceExtensionTimeWillExpire

    func test_serviceExtensionTimeWillExpire_nonPEPayload_returnsNil() {
        let (request, content) = makeRequest(userInfo: ["aps": ["alert": "x"]])
        let result = sut.serviceExtensionTimeWillExpire(request, content: content)
        XCTAssertNil(result)
    }

    func test_serviceExtensionTimeWillExpire_nilContent_returnsNil() {
        let (request, _) = makeRequest(userInfo: Fixtures.basicAlertPayload)
        let result = sut.serviceExtensionTimeWillExpire(request, content: nil)
        XCTAssertNil(result)
    }

    func test_serviceExtensionTimeWillExpire_pePayloadWithContent_returnsThatContent() {
        let (request, content) = makeRequest(userInfo: Fixtures.basicAlertPayload)
        let result = sut.serviceExtensionTimeWillExpire(request, content: content)
        XCTAssertNotNil(result)
        XCTAssertIdentical(result, content)
    }

    // MARK: - getContentExtensionInfo

    func test_getContentExtensionInfo_extractsTitleAndBody() {
        let (request, _) = makeRequest(userInfo: Fixtures.basicAlertPayload)
        let model = sut.getContentExtensionInfo(for: request)
        XCTAssertEqual(model.title, "Hello")
        XCTAssertEqual(model.body, "World")
    }

    func test_getContentExtensionInfo_mapsActionButtonsToCustomUIButtons() {
        let (request, _) = makeRequest(userInfo: Fixtures.actionButtonsPayload)
        let model = sut.getContentExtensionInfo(for: request)

        XCTAssertEqual(model.buttons?.count, 2)
        XCTAssertEqual(model.buttons?[0].id, "yes-id")
        XCTAssertEqual(model.buttons?[0].text, "Yes")
        XCTAssertEqual(model.buttons?[1].id, "no-id")
        XCTAssertEqual(model.buttons?[1].text, "No")
    }

    func test_getContentExtensionInfo_noAttachments_imageIsNil() {
        let (request, _) = makeRequest(userInfo: Fixtures.basicAlertPayload)
        let model = sut.getContentExtensionInfo(for: request)
        XCTAssertNil(model.image)
    }

    // MARK: - addButtonTo respects existing category

    func test_didReceive_skipsButtonInjection_whenCategoryIdentifierAlreadySet() {
        let (request, content) = makeRequest(userInfo: Fixtures.actionButtonsPayload,
                                             categoryIdentifier: "user-category")
        sut.didReceiveNotificationExtensionRequest(request, bestContentHandler: content)

        // Production code returns early from addButtonTo when category is non-empty.
        // We can't observe the no-op directly without UNNotificationCenter,
        // but at minimum content.categoryIdentifier must not be overwritten.
        XCTAssertEqual(content.categoryIdentifier, "user-category",
                       "Existing category must be preserved")
    }
}
