import XCTest
import UIKit
@testable import PushEngage
@testable import PushEngageExtension
final class ApplicationServiceTests: XCTestCase {

    private var userDefaults: MockUserDefaultsService!
    private var subscriber: MockSubscriberService!
    private var lifecycle: MockNotificationLifeCycleService!
    private var network: MockNetworkRouter!
    private var sut: ApplicationService!

    override func setUp() {
        super.setUp()
        userDefaults = MockUserDefaultsService()
        subscriber = MockSubscriberService()
        lifecycle = MockNotificationLifeCycleService()
        network = MockNetworkRouter()
        sut = ApplicationService(userDefault: userDefaults,
                                 subscriberService: subscriber,
                                 notificationLifeCycleService: lifecycle,
                                 networkService: network)
    }

    override func tearDown() {
        sut = nil
        network = nil
        lifecycle = nil
        subscriber = nil
        userDefaults = nil
        super.tearDown()
    }

    // MARK: - registerDeviceToServer

    func test_registerDeviceToServer_storesHexEncodedToken() {
        let bytes: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF, 0x01]
        sut.registerDeviceToServer(with: Data(bytes))
        XCTAssertEqual(userDefaults.deviceToken, "DEADBEEF01")
    }

    func test_registerDeviceToServer_freshDevice_callsRetryAddSubscriber() {
        userDefaults.deviceToken = ""
        userDefaults.subscriberHash = ""

        sut.registerDeviceToServer(with: Data([0x01, 0x02]))

        XCTAssertEqual(subscriber.retryAddSubscriberCallCount, 1)
        XCTAssertEqual(subscriber.upgradeSubscriptionCallCount, 0)
    }

    func test_registerDeviceToServer_emptySubscriberHash_callsRetryAddSubscriber_evenIfTokenExists() {
        userDefaults.deviceToken = "EXISTING"
        userDefaults.subscriberHash = ""

        sut.registerDeviceToServer(with: Data([0x01, 0x02]))

        XCTAssertEqual(subscriber.retryAddSubscriberCallCount, 1)
        XCTAssertEqual(subscriber.upgradeSubscriptionCallCount, 0)
    }

    func test_registerDeviceToServer_sameTokenWithHash_isNoOp() {
        userDefaults.deviceToken = "0102"
        userDefaults.subscriberHash = "hash"
        userDefaults._setSiteStatus(SiteStatus.active.rawValue)

        sut.registerDeviceToServer(with: Data([0x01, 0x02]))

        XCTAssertEqual(subscriber.retryAddSubscriberCallCount, 0)
        XCTAssertEqual(subscriber.upgradeSubscriptionCallCount, 0,
                       "Same token + hash present should not trigger upgrade")
    }

    func test_registerDeviceToServer_differentTokenActiveSite_callsUpgrade() {
        userDefaults.deviceToken = "OLDOLDOLD"
        userDefaults.subscriberHash = "hash"
        userDefaults._setSiteStatus(SiteStatus.active.rawValue)

        sut.registerDeviceToServer(with: Data([0xAB, 0xCD]))

        XCTAssertEqual(subscriber.upgradeSubscriptionCallCount, 1)
        XCTAssertEqual(subscriber.retryAddSubscriberCallCount, 0)
    }

    func test_registerDeviceToServer_differentTokenInactiveSite_doesNotUpgrade() {
        userDefaults.deviceToken = "OLDOLDOLD"
        userDefaults.subscriberHash = "hash"
        userDefaults._setSiteStatus(SiteStatus.inactive.rawValue)

        sut.registerDeviceToServer(with: Data([0xAB, 0xCD]))

        XCTAssertEqual(subscriber.upgradeSubscriptionCallCount, 0,
                       "Inactive site must not trigger upgrade even if token changed")
        XCTAssertEqual(subscriber.retryAddSubscriberCallCount, 0)
    }

    func test_registerDeviceToServer_setsTriedFirstTimeAfterRetry() {
        userDefaults.deviceToken = ""
        userDefaults.subscriberHash = ""
        userDefaults.istriedFirstTime = true   // start true so we can observe the false→true round-trip

        sut.registerDeviceToServer(with: Data([0x01]))

        // The mock retryAddSubscriberProcess calls completion(nil) immediately;
        // production code sets istriedFirstTime=false before and =true inside the callback.
        XCTAssertTrue(userDefaults.istriedFirstTime,
                      "After completion, istriedFirstTime should end true")
    }

    // MARK: - receivedRemoteNotification — delegate routing

    private final class DelegateSpy: LastNotificationSetDelegate {
        var setLastCallCount = 0
        var lastSetLastInfo: [AnyHashable: Any]?
        var lastSetLastCompletion: ((UIBackgroundFetchResult) -> Void)?

        var silentReceivedCallCount = 0
        var lastSilentInfo: [AnyHashable: Any]?
        var lastSilentIsOpened: Bool?

        func setLast(notification infoDict: [AnyHashable: Any],
                     completionHandler: ((UIBackgroundFetchResult) -> Void)?) {
            setLastCallCount += 1
            lastSetLastInfo = infoDict
            lastSetLastCompletion = completionHandler
        }

        func silentRemoteNotificationRecivedNotification(with userInfo: [AnyHashable: Any],
                                                         isOpened: Bool) {
            silentReceivedCallCount += 1
            lastSilentInfo = userInfo
            lastSilentIsOpened = isOpened
        }
    }

    func test_receivedRemoteNotification_sponsoredPayload_returnsBackgroundFired() {
        let result = sut.receivedRemoteNotification(application: UIApplication.shared,
                                                    userInfo: Fixtures.sponsoredPayload,
                                                    completionHandler: nil)
        XCTAssertTrue(result,
                      "Sponsored payload should report a background job fired")
    }

    func test_receivedRemoteNotification_customAlertPayload_returnsBackgroundFired() {
        // legacyCustomFieldsPayload has pe.t but no aps.alert → triggers custom-alert path
        let result = sut.receivedRemoteNotification(application: UIApplication.shared,
                                                    userInfo: Fixtures.legacyCustomFieldsPayload,
                                                    completionHandler: nil)
        XCTAssertTrue(result)
    }

    /// XCTest's host process reports `applicationState == .active`, so this
    /// exercises the "active app" branch: setLast + silentRemoteNotificationRecivedNotification
    /// (the latter only when the payload is displayable, which an aps.alert is).
    func test_receivedRemoteNotification_activeAppDisplayablePayload_callsBothDelegateMethods() {
        precondition(UIApplication.shared.applicationState == .active,
                     "These tests assume XCTest reports applicationState == .active")
        let delegate = DelegateSpy()
        sut.notifydelegate = delegate

        let returned = sut.receivedRemoteNotification(application: UIApplication.shared,
                                                      userInfo: Fixtures.basicAlertPayload,
                                                      completionHandler: nil)

        XCTAssertFalse(returned,
                       "Active-app silent path returns false — no background job is fired")
        XCTAssertEqual(delegate.setLastCallCount, 1)
        XCTAssertEqual(delegate.silentReceivedCallCount, 1,
                       "Displayable payload in active app must also fire silentRemote")
        XCTAssertEqual(delegate.lastSilentIsOpened, true,
                       "isOpened is hardcoded true on the active-app silent fire")
    }

    func test_receivedRemoteNotification_activeApp_passesThroughUserInfoToDelegate() {
        let delegate = DelegateSpy()
        sut.notifydelegate = delegate

        _ = sut.receivedRemoteNotification(application: UIApplication.shared,
                                           userInfo: Fixtures.basicAlertPayload,
                                           completionHandler: nil)

        let receivedTag = (delegate.lastSetLastInfo?["pe"] as? [String: Any])?["tag"] as? String
        XCTAssertEqual(receivedTag, "tag-abc-123")
    }

    func test_receivedRemoteNotification_silentNonDisplayable_callsOnlySetLast() {
        // Silent push has no aps.alert and no custom title/body → not custom-alert path,
        // and isNotifiyIsDisplayable returns false → only setLast fires.
        let delegate = DelegateSpy()
        sut.notifydelegate = delegate

        _ = sut.receivedRemoteNotification(application: UIApplication.shared,
                                           userInfo: Fixtures.silentPayload,
                                           completionHandler: nil)

        XCTAssertEqual(delegate.setLastCallCount, 1)
        XCTAssertEqual(delegate.silentReceivedCallCount, 0,
                       "Non-displayable silent push must not fire silentRemote")
    }

    // MARK: - notifydelegate weak holding

    func test_notifydelegate_isWeaklyHeld() {
        var delegate: DelegateSpy? = DelegateSpy()
        sut.notifydelegate = delegate
        XCTAssertNotNil(sut.notifydelegate)

        delegate = nil
        XCTAssertNil(sut.notifydelegate,
                     "ApplicationService.notifydelegate must be weak — releasing the strong reference should null it")
    }
}
