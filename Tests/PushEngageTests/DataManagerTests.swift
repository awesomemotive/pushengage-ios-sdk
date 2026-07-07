import XCTest
@testable import PushEngage
@testable import PushEngageExtension
final class DataManagerTests: XCTestCase {

    private var userDefaults: MockUserDefaultsService!
    private var sut: DataManager!

    override func setUp() {
        super.setUp()
        userDefaults = MockUserDefaultsService()
        sut = DataManager(userDefault: userDefaults)
    }

    override func tearDown() {
        sut = nil
        userDefaults = nil
        super.tearDown()
    }

    // MARK: - getSubscriptionData

    func test_getSubscriptionData_populatesStaticDeviceFields() {
        let info = sut.getSubscriptionData()
        XCTAssertEqual(info.deviceType, "ios")
        XCTAssertEqual(info.deviceManufacturer, "Apple")
        XCTAssertNotNil(info.device)
        XCTAssertNotNil(info.deviceVersion)
        XCTAssertNotNil(info.userAgent)
        XCTAssertNotNil(info.totalScreenWidthHeight)
    }

    func test_getSubscriptionData_readsSiteIdAndProfileIdFromUserDefaults() {
        userDefaults._setAppId(987)
        userDefaults.profileID = "user-42"
        userDefaults.deviceToken = "tok-1"

        let info = sut.getSubscriptionData()

        XCTAssertEqual(info.siteID, 987)
        XCTAssertEqual(info.profileID, "user-42")
        XCTAssertEqual(info.subscription?.endpoint, "tok-1")
    }

    func test_getSubscriptionData_isNotificationEnable_nilWhenGranted() {
        userDefaults.notificationPermissionState = .granted

        let info = sut.getSubscriptionData()

        XCTAssertNil(info.isNotificationEnable,
                     "Granted permission should not include isNotificationEnable flag")
    }

    func test_getSubscriptionData_isNotificationEnable_oneWhenDeniedAndDeleteOnDisable() {
        userDefaults.notificationPermissionState = .denied
        userDefaults._setIsDeleteSubscriberOnDisable(true)

        let info = sut.getSubscriptionData()

        XCTAssertEqual(info.isNotificationEnable, 1,
                       "Denied + deleteSubscriberOnDisable=true should set flag to 1")
    }

    func test_getSubscriptionData_isNotificationEnable_zeroWhenDeniedAndKeepSubscriber() {
        userDefaults.notificationPermissionState = .denied
        userDefaults._setIsDeleteSubscriberOnDisable(false)

        let info = sut.getSubscriptionData()

        XCTAssertEqual(info.isNotificationEnable, 0,
                       "Denied + deleteSubscriberOnDisable=false should set flag to 0")
    }

    func test_getSubscriptionData_isNotificationEnable_zeroWhenDeniedAndFlagMissing() {
        userDefaults.notificationPermissionState = .denied
        userDefaults._setIsDeleteSubscriberOnDisable(nil)

        let info = sut.getSubscriptionData()

        XCTAssertEqual(info.isNotificationEnable, 0,
                       "Denied + missing flag should default to 0 (keep subscriber)")
    }

    // MARK: - getSubscriptionData certEnv (APNs environment)

    func test_getSubscriptionData_certEnv_developmentMapsToDev() {
        sut = DataManager(userDefault: userDefaults,
                          entitlementsProvider: { Entitlements(["aps-environment": "development"]) })
        XCTAssertEqual(sut.getSubscriptionData().certEnv, "dev")
    }

    func test_getSubscriptionData_certEnv_productionMapsToProd() {
        sut = DataManager(userDefault: userDefaults,
                          entitlementsProvider: { Entitlements(["aps-environment": "production"]) })
        XCTAssertEqual(sut.getSubscriptionData().certEnv, "prod")
    }

    func test_getSubscriptionData_certEnv_nilWhenEntitlementMissing() {
        sut = DataManager(userDefault: userDefaults,
                          entitlementsProvider: { .empty })
        XCTAssertNil(sut.getSubscriptionData().certEnv)
    }

    func test_getSubscriptionData_certEnv_nilForUnknownValue() {
        sut = DataManager(userDefault: userDefaults,
                          entitlementsProvider: { Entitlements(["aps-environment": "staging"]) })
        XCTAssertNil(sut.getSubscriptionData().certEnv)
    }

    // MARK: - getSubscriptionStatus

    func test_getSubscriptionStatus_buildsFromUserDefaults() {
        userDefaults._setAppId(1234)
        userDefaults.subscriberHash = "hash-abc"

        let status = sut.getSubscriptionStatus()

        XCTAssertEqual(status.siteID, 1234)
        XCTAssertEqual(status.deviceTokenHash, "hash-abc")
    }

    func test_getSubscriptionStatus_appIdNilProducesNil() {
        userDefaults._setAppId(nil)

        let status = sut.getSubscriptionStatus()

        XCTAssertNil(status.siteID)
    }

    // MARK: - getPostBackSubscriptionData

    func test_getPostBackSubscriptionData_extractsTagFromNotification() {
        let notification = PENotification(userInfo: Fixtures.sponsoredPayload)

        let sponsored = sut.getPostBackSubscriptionData(for: notification)

        XCTAssertEqual(sponsored.tag, "sponsored-tag")
    }

    func test_getPostBackSubscriptionData_postbackPassesThroughWhenAbsent() {
        let notification = PENotification(userInfo: Fixtures.basicAlertPayload)

        let sponsored = sut.getPostBackSubscriptionData(for: notification)

        XCTAssertEqual(sponsored.tag, "tag-abc-123")
        XCTAssertNil(sponsored.postback)
    }

    // MARK: - getSubsriberUpgradeData

    func test_getSubsriberUpgradeData_packsHashTokenAndSiteId() {
        userDefaults.subscriberHash = "upg-hash"
        userDefaults.deviceToken = "upg-tok"
        userDefaults._setAppId(555)

        let upgrade = sut.getSubsriberUpgradeData()

        XCTAssertEqual(upgrade.deviceTokenHash, "upg-hash")
        XCTAssertEqual(upgrade.subscription.endpoint, "upg-tok")
        XCTAssertEqual(upgrade.siteId, 555)
    }

    func test_getSubsriberUpgradeData_defaultsSiteIdToMinusHundredWhenMissing() {
        userDefaults._setAppId(nil)

        let upgrade = sut.getSubsriberUpgradeData()

        XCTAssertEqual(upgrade.siteId, -100,
                       "Missing appId must default to -100 sentinel")
    }
}
