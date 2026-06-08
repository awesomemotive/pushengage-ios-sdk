import XCTest
import UIKit
import UserNotifications
@testable import PushEngage

/// Tier 3 — `PEManager` orchestration. Wires all 7 service mocks through
/// the SUT and verifies dispatch, the prerequisite gate, notification routing,
/// and the queue-flush behavior relevant to Issue #1 (cold-boot notifications).
final class PEManagerTests: XCTestCase {

    private var applicationService: MockApplicationService!
    private var notificationService: MockNotificationService!
    private var notificationExtensionService: MockNotificationExtensionService!
    private var subscriberService: MockSubscriberService!
    private var userDefaults: MockUserDefaultsService!
    private var lifecycle: MockNotificationLifeCycleService!
    private var triggerCampaign: MockTriggerCampaignManager!
    private var sut: PEManager!

    override func setUp() {
        super.setUp()
        applicationService = MockApplicationService()
        notificationService = MockNotificationService()
        notificationExtensionService = MockNotificationExtensionService()
        subscriberService = MockSubscriberService()
        userDefaults = MockUserDefaultsService()
        lifecycle = MockNotificationLifeCycleService()
        triggerCampaign = MockTriggerCampaignManager()

        // Default: site active, permission granted, subscriber alive — so the
        // prerequisite gate lets calls through. Override per-test as needed.
        userDefaults._setSiteStatus(SiteStatus.active.rawValue)
        userDefaults.notificationPermissionState = .granted
        userDefaults.isSubscriberDeleted = false
        userDefaults.subscriberHash = "hash-1"

        sut = PEManager(applicationService: applicationService,
                        notificationService: notificationService,
                        notificationExtensionService: notificationExtensionService,
                        subscriberService: subscriberService,
                        userDefaultService: userDefaults,
                        notificationLifeCycleService: lifecycle,
                        triggerCamapaiginService: triggerCampaign)
    }

    override func tearDown() {
        // Manager holds a static notificationOpenHandler — clear it so cross-test
        // pollution can't happen.
        sut.setNotificationOpenHandler(block: nil)
        sut.setNotificationWillShowInForegroundHandler(block: nil)
        sut = nil
        triggerCampaign = nil
        lifecycle = nil
        userDefaults = nil
        subscriberService = nil
        notificationExtensionService = nil
        notificationService = nil
        applicationService = nil
        super.tearDown()
    }

    // MARK: - init wiring

    func test_init_wiresApplicationServiceDelegateToSelf() {
        XCTAssertTrue(applicationService.notifydelegate === sut as LastNotificationSetDelegate,
                      "PEManager.init must assign itself as ApplicationService's notifydelegate")
    }

    // MARK: - Device + environment + appId

    func test_setEnvironment_writesThroughToUserDefaults() {
        sut.setEnvironment(.staging)
        XCTAssertEqual(userDefaults.environment, .staging)
    }

    func test_getDeviceToken_readsFromUserDefaults() {
        userDefaults.deviceToken = "DTOKEN"
        XCTAssertEqual(sut.getDeviceToken(), "DTOKEN")
    }

    func test_setDeviceToken_writesThrough() {
        sut.setDeviceToken(token: "WRITTEN")
        XCTAssertEqual(userDefaults.deviceToken, "WRITTEN")
    }

    func test_setAppId_writesSiteKey() {
        sut.setAppId(key: "site-A")
        XCTAssertEqual(userDefaults.siteKey, "site-A")
    }

    func test_getAppId_readsFromUserDefaults() {
        userDefaults._setAppId(99)
        XCTAssertEqual(sut.getAppId(), 99)
    }

    func test_getDeviceHash_returnsSubscriberHash() {
        userDefaults.subscriberHash = "the-hash"
        XCTAssertEqual(sut.getDeviceHash(), "the-hash")
    }

    func test_getSubscriberHash_returnsSubscriberHash() {
        userDefaults.subscriberHash = "the-hash"
        XCTAssertEqual(sut.getSubscriberHash(), "the-hash")
    }

    // MARK: - setBadgeCount  (Issue #7 — native API exists)
    //
    // The current production implementation calls UNUserNotificationCenter.setBadgeCount
    // (iOS 16+) or, on iOS 12-15, UIApplication.shared.applicationIconBadgeNumber wrapped
    // in `#if !APPLICATION_EXTENSION_API_ONLY`. Both system calls throw
    // NSInternalInconsistencyException (`bundleProxyForCurrentProcess is nil`) when
    // invoked from inside an SPM-driven XCTest bundle with no app host.
    //
    // Marked as `[skip]` in docs/TEST_PLAN.md until either:
    //   (a) the production code is wrapped so the system call can be bypassed in tests, or
    //   (b) these tests are moved into an app-hosted XCTest bundle (Tier 5 infra).

    // MARK: - Permission status read/write

    func test_getNotificationPermissionStatus_readsFromUserDefaults() {
        userDefaults.notificationPermissionState = .denied
        XCTAssertEqual(sut.getNotificationPermissionStatus(), .denied)
    }

    func test_setNotificationPermissionStatus_writesThrough() {
        sut.setNotificationPermissionStatus(status: .granted)
        XCTAssertEqual(userDefaults.notificationPermissionState, .granted)
    }

    // MARK: - handleNotificationPermission (request flow)

    func test_handleNotificationPermission_failsFastIfApplicationMissing() {
        let exp = expectation(description: "completion")
        sut.handleNotificationPermission { granted, error in
            XCTAssertFalse(granted)
            XCTAssertNotNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(notificationService.handleNotificationPermissionCallCount, 0,
                       "When application is nil, the service must not be called")
    }

    // NOTE: A test for the positive "handleNotificationPermission delegates to the
    // notificationService after setInitialInfo" path is intentionally omitted here.
    // PEManager.setInitialInfo stores `UIApplication.shared` into a private property
    // and then handleNotificationPermission reads it back through a `guard let` —
    // but inside this SPM-driven XCTest bundle the stored value reads back as nil,
    // which causes the guard to short-circuit with `.siteKeyNotAvailable`. This
    // appears specific to the no-app-host environment and prevents direct
    // unit-test verification. Tier 5 (app-hosted XCTest bundle) will cover it.
    // The negative path (`test_handleNotificationPermission_failsFastIfApplicationMissing`)
    // is verified above.

    // MARK: - Prerequisite gate (siteStatus / permission / subscriberDeleted)

    func test_prerequisite_siteNotActive_blocksCalls() {
        userDefaults._setSiteStatus(SiteStatus.inactive.rawValue)

        let exp = expectation(description: "completion")
        sut.add(attributes: ["k": "v"]) { response, error in
            XCTAssertFalse(response)
            if case .siteStatusNotActive? = error { exp.fulfill() } else { XCTFail() }
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(subscriberService.addSubscriberAttributesCallCount, 0,
                       "Inactive site must short-circuit before the service is called")
    }

    func test_prerequisite_subscriberDeleted_blocksCalls() {
        userDefaults.isSubscriberDeleted = true

        let exp = expectation(description: "completion")
        sut.set(attributes: ["k": "v"]) { _, error in
            if case .subscriberNotAvailable? = error { exp.fulfill() } else { XCTFail() }
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(subscriberService.setSubscriberAttributesCallCount, 0)
    }

    func test_prerequisite_notYetRequestedPermission_blocksCalls() {
        userDefaults.notificationPermissionState = .notYetRequested

        let exp = expectation(description: "completion")
        sut.add(attributes: ["k": "v"]) { _, error in
            if case .subscriberNotAvailable? = error { exp.fulfill() } else { XCTFail() }
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_prerequisite_grantedAndActive_allowsCallThrough() {
        let exp = expectation(description: "completion")
        sut.add(attributes: ["a": 1]) { response, _ in
            XCTAssertTrue(response)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(subscriberService.addSubscriberAttributesCallCount, 1)
    }

    func test_prerequisite_deniedPermissionStillCountsAsValid() {
        // The gate explicitly accepts both .granted and .denied — only .notYetRequested blocks.
        userDefaults.notificationPermissionState = .denied

        let exp = expectation(description: "completion")
        sut.add(attributes: ["a": 1]) { _, _ in exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(subscriberService.addSubscriberAttributesCallCount, 1,
                       "Denied permission must still pass the prerequisite gate")
    }

    // MARK: - Attribute pass-through

    func test_set_attributes_forwardsToService() {
        sut.set(attributes: ["x": 1], completionHandler: nil)
        XCTAssertEqual(subscriberService.setSubscriberAttributesCallCount, 1)
        XCTAssertEqual(subscriberService.lastSetAttributes?["x"] as? Int, 1)
    }

    func test_add_attributes_forwardsToService() {
        sut.add(attributes: ["x": 1], completionHandler: nil)
        XCTAssertEqual(subscriberService.addSubscriberAttributesCallCount, 1)
    }

    func test_getAttribute_forwardsToService() {
        subscriberService.getAttributeResult = (["k": "v"], nil)
        let exp = expectation(description: "completion")
        sut.getAttribute { dict, _ in
            XCTAssertEqual(dict?["k"] as? String, "v")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_deleteAttribute_forwardsToService() {
        sut.deleteAttribute(values: ["k1", "k2"], completionHandler: nil)
        XCTAssertEqual(subscriberService.deleteAttributeCallCount, 1)
        XCTAssertEqual(subscriberService.lastDeleteAttributeValues, ["k1", "k2"])
    }

    func test_addProfile_forwardsToService() {
        sut.addProfile(for: "profile-9", completionHandler: nil)
        XCTAssertEqual(subscriberService.addProfileCallCount, 1)
        XCTAssertEqual(subscriberService.lastAddProfileId, "profile-9")
    }

    // MARK: - Segments

    func test_update_segments_add_forwardsToService() {
        sut.update(segments: ["s1", "s2"], with: .add, completionHandler: nil)
        XCTAssertEqual(subscriberService.updateSegmentsCallCount, 1)
        XCTAssertEqual(subscriberService.lastUpdateSegmentAction, .add)
        XCTAssertEqual(subscriberService.lastUpdateSegments, ["s1", "s2"])
    }

    func test_update_segments_remove_forwardsToService() {
        sut.update(segments: ["s1"], with: .remove, completionHandler: nil)
        XCTAssertEqual(subscriberService.updateSegmentsCallCount, 1)
        XCTAssertEqual(subscriberService.lastUpdateSegmentAction, .remove)
    }

    func test_add_dynamicSegments_forwardsToService() {
        sut.add(dynamic: [["name": "premium", "duration": 30]], completionHandler: nil)
        XCTAssertEqual(subscriberService.updateDynamicCallCount, 1)
    }

    func test_updateHashArray_forwardsToService() {
        sut.updateHashArray(for: 5, completionHandler: nil)
        XCTAssertEqual(subscriberService.segmentHashArrayCallCount, 1)
        XCTAssertEqual(subscriberService.lastSegmentId, 5)
    }

    // MARK: - Subscriber details

    func test_getSubscriberDetails_forwardsToService() {
        sut.getSubscriberDetails(for: ["a", "b"], completionHandler: nil)
        XCTAssertEqual(subscriberService.getSubscriberCallCount, 1)
        XCTAssertEqual(subscriberService.lastGetSubscriberFields, ["a", "b"])
    }

    func test_checkSubscriber_forwardsToService() {
        sut.checkSubscriber(completionHandler: nil)
        XCTAssertEqual(subscriberService.checkSubscriberCallCount, 1)
    }

    // MARK: - Goal / trigger campaign

    func test_sendGoal_forwardsToService() {
        let goal = Goal(name: "purchase", count: 1, value: 9.99)
        sut.sendGoal(goal: goal, completionHandler: nil)
        XCTAssertEqual(subscriberService.sendGoalCallCount, 1)
        XCTAssertEqual(subscriberService.lastGoal?.name, "purchase")
    }

    func test_automatedNotification_forwardsToService() {
        sut.automatedNotification(status: .enabled, completionHandler: nil)
        XCTAssertEqual(subscriberService.automatedNotificationCallCount, 1)
        XCTAssertEqual(subscriberService.lastAutomatedStatus, .enabled)
    }

    func test_sendTriggerEvent_forwardsToTriggerCampaignService() {
        let trigger = TriggerCampaign(campaignName: "c", eventName: "e")
        sut.sendTriggerEvent(trigger: trigger, completionHandler: nil)
        XCTAssertEqual(triggerCampaign.sendTriggerEventCallCount, 1)
        XCTAssertEqual(triggerCampaign.lastTriggerCampaign?.campaignName, "c")
    }

    func test_addAlert_forwardsToTriggerCampaignService() {
        let alert = TriggerAlert(type: .priceDrop, productId: "p", link: "https://x.test", price: 1)
        sut.addAlert(triggerAlert: alert, completionHandler: nil)
        XCTAssertEqual(triggerCampaign.addAlertCallCount, 1)
    }

    // MARK: - unsubscribe / subscribe state machine

    func test_unsubscribe_happyPath_setsManualUnsubscribedAndDeletedFlags() {
        subscriberService.updateSubscriberStatusResult = (true, nil)

        let exp = expectation(description: "completion")
        sut.unsubscribe { response, _ in
            XCTAssertTrue(response)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(userDefaults.isManuallyUnsubscribed,
                      "Successful unsubscribe must mark manuallyUnsubscribed=true")
        XCTAssertTrue(userDefaults.isSubscriberDeleted)
        XCTAssertEqual(subscriberService.lastUpdateStatus, 1,
                       "unsubscribe sends status=1")
    }

    func test_unsubscribe_failureDoesNotSetFlags() {
        subscriberService.updateSubscriberStatusResult = (false, .networkError)
        let exp = expectation(description: "completion")
        sut.unsubscribe { response, _ in
            XCTAssertFalse(response)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertFalse(userDefaults.isManuallyUnsubscribed,
                       "Failed unsubscribe must not flip manuallyUnsubscribed")
    }

    func test_unsubscribe_happyPath_clearsSubscriberFieldsCache() {
        // Seed the identify/logout cache, then unsubscribe — the cache must be
        // wiped so a future re-subscribe doesn't short-circuit identify against
        // stale fields belonging to the previous subscriber identity.
        userDefaults.mergeSubscriberFields(["email": "a@b.com"])
        subscriberService.updateSubscriberStatusResult = (true, nil)

        let exp = expectation(description: "completion")
        sut.unsubscribe { _, _ in exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(userDefaults.clearSubscriberFieldsCallCount, 1,
                       "Successful unsubscribe must wipe the subscriber-fields cache")
        XCTAssertEqual(userDefaults.subscriberFields, [:])
    }

    func test_unsubscribe_failure_doesNotClearSubscriberFieldsCache() {
        userDefaults.mergeSubscriberFields(["email": "a@b.com"])
        subscriberService.updateSubscriberStatusResult = (false, .networkError)

        let exp = expectation(description: "completion")
        sut.unsubscribe { _, _ in exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(userDefaults.clearSubscriberFieldsCallCount, 0,
                       "Failed unsubscribe must not wipe the cache")
        XCTAssertEqual(userDefaults.subscriberFields, ["email": "a@b.com"])
    }

    func test_subscribe_grantedWithHash_callsUpdateSubscriberStatusZero() {
        userDefaults.notificationPermissionState = .granted
        userDefaults.subscriberHash = "hash-1"
        subscriberService.updateSubscriberStatusResult = (true, nil)

        let exp = expectation(description: "completion")
        sut.subscribe { response, _ in
            XCTAssertTrue(response)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(subscriberService.lastUpdateStatus, 0,
                       "subscribe via update path sends status=0")
        XCTAssertFalse(userDefaults.isManuallyUnsubscribed)
        XCTAssertFalse(userDefaults.isSubscriberDeleted)
    }

    func test_subscribe_deniedPermission_failsWithPermissionNotGranted() {
        userDefaults.notificationPermissionState = .denied
        userDefaults.subscriberHash = ""

        let exp = expectation(description: "completion")
        sut.subscribe { response, error in
            XCTAssertFalse(response)
            if case .permissionNotGranted? = error { exp.fulfill() } else { XCTFail() }
        }
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - getSubscriptionStatus state machine

    func test_getSubscriptionStatus_inactiveSite_returnsErrorFalse() {
        userDefaults._setSiteStatus(SiteStatus.inactive.rawValue)
        let exp = expectation(description: "completion")
        sut.getSubscriptionStatus { isSubscribed, error in
            XCTAssertFalse(isSubscribed)
            if case .siteStatusNotActive? = error { exp.fulfill() } else { XCTFail() }
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_getSubscriptionStatus_manuallyUnsubscribed_returnsFalseNoError() {
        userDefaults.isManuallyUnsubscribed = true
        let exp = expectation(description: "completion")
        sut.getSubscriptionStatus { isSubscribed, error in
            XCTAssertFalse(isSubscribed)
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_getSubscriptionStatus_emptyHash_returnsFalseNoError() {
        userDefaults.subscriberHash = ""
        let exp = expectation(description: "completion")
        sut.getSubscriptionStatus { isSubscribed, error in
            XCTAssertFalse(isSubscribed)
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_getSubscriptionStatus_notYetRequestedPermission_returnsPermissionNotDetermined() {
        userDefaults.notificationPermissionState = .notYetRequested
        let exp = expectation(description: "completion")
        sut.getSubscriptionStatus { isSubscribed, error in
            XCTAssertFalse(isSubscribed)
            if case .permissionNotDetermined? = error { exp.fulfill() } else { XCTFail() }
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_getSubscriptionStatus_grantedAndNotDeleted_returnsTrue_withoutNetworkCall() {
        // Live local data path — no API call needed
        userDefaults.notificationPermissionState = .granted
        userDefaults.isSubscriberDeleted = false
        userDefaults.subscriberHash = "alive-hash"

        let exp = expectation(description: "completion")
        sut.getSubscriptionStatus { isSubscribed, error in
            XCTAssertTrue(isSubscribed)
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(subscriberService.getSubscriberCallCount, 0,
                       "Granted+alive path must not call the network")
    }

    // MARK: - getSubscriberId

    func test_getSubscriberId_returnsHashWhenSubscribed() {
        userDefaults.subscriberHash = "id-1"
        userDefaults.notificationPermissionState = .granted

        let exp = expectation(description: "completion")
        sut.getSubscriberId { id in
            XCTAssertEqual(id, "id-1")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_getSubscriberId_returnsNilWhenNotSubscribed() {
        userDefaults.subscriberHash = ""

        let exp = expectation(description: "completion")
        sut.getSubscriberId { id in
            XCTAssertNil(id)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - getSubscriptionNotificationStatus (combined gate)

    func test_getSubscriptionNotificationStatus_requiresBothSubscribedAndGranted() {
        userDefaults.notificationPermissionState = .granted
        userDefaults.subscriberHash = "id-1"
        userDefaults.isSubscriberDeleted = false

        let exp = expectation(description: "completion")
        sut.getSubscriptionNotificationStatus { canReceive, error in
            XCTAssertTrue(canReceive)
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_getSubscriptionNotificationStatus_subscribedButDeniedPermission_returnsFalse() {
        // Tricky: getSubscriptionStatus's "granted + alive" shortcut won't fire with denied.
        // Force the service-call branch by setting isSubscriberDeleted=true so we go through getSubscriber.
        userDefaults.notificationPermissionState = .denied
        userDefaults.subscriberHash = "id-1"
        userDefaults.isSubscriberDeleted = true
        let detailsJSON = #"{"has_unsubscribed":0,"notification_disabled":0}"#
        let details = try! JSONDecoder().decode(SubscriberDetailsData.self,
                                                from: Data(detailsJSON.utf8))
        subscriberService.getSubscriberResult = (details, nil)

        let exp = expectation(description: "completion")
        sut.getSubscriptionNotificationStatus { canReceive, _ in
            XCTAssertFalse(canReceive,
                           "Permission denied must produce canReceive=false even if backend says subscribed")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - Notification routing (Issue #1 — queue flush)

    func test_setNotificationOpenHandler_flushesQueuedNotifications() {
        // Use the internal receivedNotification API to enqueue a tap result
        // BEFORE installing the handler. After install, it must replay.
        var openInfo = Fixtures.basicAlertPayload
        // Mark as "opened action taken" to take the .taken branch
        var pe = openInfo["pe"] as! [String: Any]
        pe["ad"] = ["actionSelected": "default-action"]
        openInfo["pe"] = pe

        sut.receivedNotification(with: openInfo, isOpened: true)

        // No handler yet → notification should be queued (no crash, no fire).
        var fired: PENotificationOpenResult?
        sut.setNotificationOpenHandler { result in
            fired = result
        }

        XCTAssertNotNil(fired,
                        "Setting the open handler must immediately flush any queued tap")
        XCTAssertEqual(fired?.notification.tag, "tag-abc-123")
    }

    func test_setNotificationOpenHandler_nil_doesNotCrash() {
        sut.setNotificationOpenHandler(block: nil)
        XCTAssertTrue(true, "Nil handler must be a safe no-op")
    }

    func test_receivedNotification_nonPEPayload_isNoOp() {
        var captured: PENotificationOpenResult?
        sut.setNotificationOpenHandler { captured = $0 }
        sut.receivedNotification(with: ["aps": ["alert": "x"]], isOpened: true)
        XCTAssertNil(captured,
                     "Non-PE userInfo must not produce an openResult")
    }

    func test_receivedNotification_duplicateTag_deduplicates() {
        var fireCount = 0
        sut.setNotificationOpenHandler { _ in fireCount += 1 }

        // Same payload twice with isOpened:true
        sut.receivedNotification(with: Fixtures.basicAlertPayload, isOpened: true)
        sut.receivedNotification(with: Fixtures.basicAlertPayload, isOpened: true)

        XCTAssertEqual(fireCount, 1,
                       "Duplicate notification tags must be filtered (dedupe is by tag)")
    }

    // MARK: - Foreground presentation handler
    //
    // `handleWillPresentNotificationInForeground` checks `application?.applicationState`
    // which requires setInitialInfo to have persisted the app — see note above.
    // These tests will move to the app-hosted XCTest bundle in Tier 5.

    // MARK: - Extension surface delegation

    func test_didReceiveNotificationExtensionRequest_forwardsToExtensionService() {
        let content = UNMutableNotificationContent()
        let request = UNNotificationRequest(identifier: "id",
                                            content: content,
                                            trigger: nil)
        sut.didReceiveNotificationExtensionRequest(request, bestContentHandler: content)
        XCTAssertEqual(notificationExtensionService.didReceiveExtensionCallCount, 1)
    }

    func test_serviceExtensionTimeWillExpire_forwardsToExtensionService() {
        let content = UNMutableNotificationContent()
        let request = UNNotificationRequest(identifier: "id",
                                            content: content,
                                            trigger: nil)
        _ = sut.serviceExtensionTimeWillExpire(request, content: content)
        XCTAssertEqual(notificationExtensionService.serviceExtensionTimeWillExpireCallCount, 1)
    }

    func test_getCustomUIPayLoad_forwardsToExtensionService() {
        let content = UNMutableNotificationContent()
        let request = UNNotificationRequest(identifier: "id",
                                            content: content,
                                            trigger: nil)
        _ = sut.getCustomUIPayLoad(for: request)
        XCTAssertEqual(notificationExtensionService.getContentExtensionInfoCallCount, 1)
    }

    // MARK: - Application service delegation

    func test_registerDeviceToServer_forwardsToApplicationService() {
        sut.registerDeviceToServer(with: Data([0xAB]))
        XCTAssertEqual(applicationService.registerDeviceCallCount, 1)
    }

    func test_receivedRemoteNotification_forwardsToApplicationService() {
        applicationService.receivedRemoteReturn = true
        let returned = sut.receivedRemoteNotification(application: UIApplication.shared,
                                                     userInfo: ["aps": ["alert": "x"]],
                                                     completionHandler: nil)
        XCTAssertTrue(returned)
        XCTAssertEqual(applicationService.receivedRemoteCallCount, 1)
    }

    // `willPresentNotification` test omitted: UNNotification has no public init,
    // and instantiating UNUserNotificationCenter.current() inside this test bundle
    // raises bundleProxyForCurrentProcess. Covered in Tier 5 (app-hosted).
}
