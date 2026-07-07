import XCTest
@testable import PushEngage
@testable import PushEngageExtension
final class UserDefaultManagerTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var sut: UserDefaultManager!

    override func setUp() {
        super.setUp()
        // Unique suite per test so cases are isolated.
        suiteName = "com.pushengage.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        XCTAssertNotNil(defaults, "Test suite UserDefaults must initialize")
        sut = UserDefaultManager(userDefaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Scalar string properties

    func test_deviceToken_defaultIsEmpty() {
        XCTAssertEqual(sut.deviceToken, "")
    }

    func test_deviceToken_roundTrip() {
        sut.deviceToken = "tok-123"
        XCTAssertEqual(sut.deviceToken, "tok-123")
    }

    func test_subscriberHash_defaultIsEmpty() {
        XCTAssertEqual(sut.subscriberHash, "")
    }

    func test_subscriberHash_roundTrip() {
        sut.subscriberHash = "hash-xyz"
        XCTAssertEqual(sut.subscriberHash, "hash-xyz")
    }

    func test_siteKey_defaultIsNil() {
        XCTAssertNil(sut.siteKey)
    }

    func test_siteKey_roundTrip() {
        sut.siteKey = "site-key-1"
        XCTAssertEqual(sut.siteKey, "site-key-1")
    }

    func test_profileID_defaultIsNil() {
        XCTAssertNil(sut.profileID)
    }

    func test_profileID_roundTrip() {
        sut.profileID = "user-99"
        XCTAssertEqual(sut.profileID, "user-99")
    }

    // MARK: - Permission state

    func test_notificationPermissionState_defaultIsNotYetRequested() {
        XCTAssertEqual(sut.notificationPermissionState, .notYetRequested)
    }

    func test_notificationPermissionState_roundTrip_granted() {
        sut.notificationPermissionState = .granted
        XCTAssertEqual(sut.notificationPermissionState, .granted)
    }

    func test_notificationPermissionState_roundTrip_denied() {
        sut.notificationPermissionState = .denied
        XCTAssertEqual(sut.notificationPermissionState, .denied)
    }

    func test_notificationPermissionState_unknownRawValue_fallsBackToNotYetRequested() {
        defaults.setValue("nonsense", forKey: "notification_permission")
        XCTAssertEqual(sut.notificationPermissionState, .notYetRequested)
    }

    // MARK: - Boolean flags (all default to false)

    func test_ispermissionAlerted_defaultIsFalse_andRoundTrips() {
        XCTAssertFalse(sut.ispermissionAlerted)
        sut.ispermissionAlerted = true
        XCTAssertTrue(sut.ispermissionAlerted)
    }

    func test_isSubscriberDeleted_defaultIsFalse_andRoundTrips() {
        XCTAssertFalse(sut.isSubscriberDeleted)
        sut.isSubscriberDeleted = true
        XCTAssertTrue(sut.isSubscriberDeleted)
    }

    func test_isManuallyUnsubscribed_defaultIsFalse_andRoundTrips() {
        XCTAssertFalse(sut.isManuallyUnsubscribed)
        sut.isManuallyUnsubscribed = true
        XCTAssertTrue(sut.isManuallyUnsubscribed)
    }

    func test_istriedFirstTime_defaultIsFalse_andRoundTrips() {
        XCTAssertFalse(sut.istriedFirstTime)
        sut.istriedFirstTime = true
        XCTAssertTrue(sut.istriedFirstTime)
    }

    func test_isSwizzled_defaultIsFalse_andRoundTrips() {
        XCTAssertFalse(sut.isSwizzled)
        sut.isSwizzled = true
        XCTAssertTrue(sut.isSwizzled)
    }

    // MARK: - badgeCount / lastSmartSubscribeDate

    func test_badgeCount_defaultIsNil_andRoundTrips() {
        XCTAssertNil(sut.badgeCount)
        sut.badgeCount = 7
        XCTAssertEqual(sut.badgeCount, 7)
    }

    func test_lastSmartSubscribeDate_defaultIsNil_andRoundTrips() {
        XCTAssertNil(sut.lastSmartSubscribeDate)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        sut.lastSmartSubscribeDate = date
        XCTAssertEqual(sut.lastSmartSubscribeDate, date)
    }

    // MARK: - Environment

    func test_environment_defaultIsProduction() {
        XCTAssertEqual(sut.environment, .production)
    }

    func test_environment_roundTrip_staging() {
        sut.environment = .staging
        XCTAssertEqual(sut.environment, .staging)
    }

    func test_environment_roundTrip_production() {
        sut.environment = .staging
        sut.environment = .production
        XCTAssertEqual(sut.environment, .production)
    }

    // MARK: - Sponsored ID

    func test_sponsoredId_defaultIsNil_andRoundTripsViaSetter() {
        XCTAssertNil(sut.sponseredIdKey)
        sut.setsponseredID(id: "sponsored-42")
        XCTAssertEqual(sut.sponseredIdKey, "sponsored-42")
    }

    // MARK: - Generic Codable store

    private struct Box: Codable, Equatable {
        let value: Int
        let label: String
    }

    func test_saveAndGetObject_roundTripsAnyCodable() {
        let box = Box(value: 99, label: "test")
        sut.save(object: box, for: "boxKey")
        let retrieved = sut.getObject(for: Box.self, key: "boxKey")
        XCTAssertEqual(retrieved, box)
    }

    func test_getObject_returnsNilForMissingKey() {
        XCTAssertNil(sut.getObject(for: Box.self, key: "absent-key"))
    }

    func test_getObject_returnsNilWhenDataIsCorrupt() {
        // Write garbage bytes under the expected key
        defaults.setValue(Data([0xFF, 0x00, 0xAB]), forKey: "boxKey")
        XCTAssertNil(sut.getObject(for: Box.self, key: "boxKey"))
    }

    // MARK: - SyncAPIData-backed read-only computed properties

    func test_appId_returnsNilWhenSyncDataAbsent() {
        XCTAssertNil(sut.appId)
    }

    func test_siteStatus_defaultsToNoneWhenSyncDataAbsent() {
        XCTAssertEqual(sut.siteStatus, "none")
    }

    func test_isLocationEnabled_defaultIsFalseWhenSyncDataAbsent() {
        XCTAssertFalse(sut.isLocationEnabled)
    }

    func test_isGDPR_defaultIsZeroWhenSyncDataAbsent() {
        XCTAssertEqual(sut.isGDPR, 0)
    }

    func test_isDeleteSubscriberOnDisable_defaultIsNilWhenSyncDataAbsent() {
        XCTAssertNil(sut.isDeleteSubscriberOnDisable)
    }

    // Once SyncAPIData is persisted, the read-only computeds should reflect its contents.
    // We construct a SyncAPIData with the JSON fields the production code expects.
    func test_syncBackedProperties_readFromStoredSyncAPIData() throws {
        let json = """
        {
          "site_id": 4242,
          "site_status": "active",
          "geo_fetch": true,
          "is_eu": 1,
          "delete_on_notification_disable": true
        }
        """
        let data = Data(json.utf8)
        let sync = try JSONDecoder().decode(SyncAPIData.self, from: data)
        sut.save(object: sync, for: "pushengage_sync_api")

        XCTAssertEqual(sut.appId, 4242)
        XCTAssertEqual(sut.siteStatus, "active")
        XCTAssertTrue(sut.isLocationEnabled)
        XCTAssertEqual(sut.isGDPR, 1)
        XCTAssertEqual(sut.isDeleteSubscriberOnDisable, true)
    }

    // MARK: - Nil-storage safety

    func test_initWithNilUserDefaults_doesNotCrashOnReads() {
        let nilSut = UserDefaultManager(userDefaults: nil)
        XCTAssertEqual(nilSut.deviceToken, "")
        XCTAssertEqual(nilSut.subscriberHash, "")
        XCTAssertEqual(nilSut.notificationPermissionState, .notYetRequested)
        XCTAssertFalse(nilSut.ispermissionAlerted)
        XCTAssertNil(nilSut.badgeCount)
        XCTAssertNil(nilSut.appId)
        XCTAssertEqual(nilSut.siteStatus, "none")
    }

    func test_initWithNilUserDefaults_writesAreNoOps() {
        let nilSut = UserDefaultManager(userDefaults: nil)
        nilSut.deviceToken = "ignored"
        XCTAssertEqual(nilSut.deviceToken, "", "Writes to nil storage should silently no-op")
    }

    // MARK: - platform (wrapper flavor)

    func test_platform_defaultIsNil() {
        XCTAssertNil(sut.platform)
    }

    func test_platform_roundTrip() {
        sut.platform = "FlutterIOS"
        XCTAssertEqual(sut.platform, "FlutterIOS")
    }

    func test_platform_canBeClearedWithNil() {
        sut.platform = "ReactNativeIOS"
        sut.platform = nil
        XCTAssertNil(sut.platform)
    }

    // MARK: - wrapperVersion

    func test_wrapperVersion_defaultIsNil() {
        XCTAssertNil(sut.wrapperVersion)
    }

    func test_wrapperVersion_roundTrip() {
        sut.wrapperVersion = "2.3.0"
        XCTAssertEqual(sut.wrapperVersion, "2.3.0")
    }

    func test_wrapperVersion_canBeClearedWithNil() {
        sut.wrapperVersion = "1.0.0"
        sut.wrapperVersion = nil
        XCTAssertNil(sut.wrapperVersion)
    }

    // MARK: - Subscriber-fields cache

    func test_subscriberFields_defaultsToEmptyDict() {
        XCTAssertEqual(sut.subscriberFields, [:])
        XCTAssertNil(sut.subscriberFieldsCacheTimestamp)
    }

    func test_mergeSubscriberFields_writesAndUpdatesTimestamp() {
        sut.mergeSubscriberFields(["email": "a@b.com", "first_name": "Alice"])
        XCTAssertEqual(sut.subscriberFields, ["email": "a@b.com", "first_name": "Alice"])
        XCTAssertNotNil(sut.subscriberFieldsCacheTimestamp)
    }

    func test_mergeSubscriberFields_addsToExistingValues() {
        sut.mergeSubscriberFields(["email": "a@b.com"])
        sut.mergeSubscriberFields(["first_name": "Alice"])
        XCTAssertEqual(sut.subscriberFields, ["email": "a@b.com", "first_name": "Alice"])
    }

    func test_mergeSubscriberFields_overwritesSameKey() {
        sut.mergeSubscriberFields(["email": "a@b.com"])
        sut.mergeSubscriberFields(["email": "c@d.com"])
        XCTAssertEqual(sut.subscriberFields, ["email": "c@d.com"])
    }

    func test_removeSubscriberFields_dropsListedKeys() {
        sut.mergeSubscriberFields(["email": "a@b.com", "first_name": "Alice", "phone": "1234"])
        sut.removeSubscriberFields(["email", "phone"])
        XCTAssertEqual(sut.subscriberFields, ["first_name": "Alice"])
    }

    func test_removeSubscriberFields_ignoresAbsentKeys() {
        sut.mergeSubscriberFields(["email": "a@b.com"])
        sut.removeSubscriberFields(["phone"])
        XCTAssertEqual(sut.subscriberFields, ["email": "a@b.com"])
    }

    func test_clearSubscriberFields_wipesDictAndTimestamp() {
        sut.mergeSubscriberFields(["email": "a@b.com"])
        sut.clearSubscriberFields()
        XCTAssertEqual(sut.subscriberFields, [:])
        XCTAssertNil(sut.subscriberFieldsCacheTimestamp)
    }

    // MARK: - Cache lifecycle: subscriberHash setter wipe

    func test_subscriberHash_changing_wipesSubscriberFieldsCache() {
        sut.subscriberHash = "hash-1"
        sut.mergeSubscriberFields(["email": "a@b.com"])
        XCTAssertEqual(sut.subscriberFields, ["email": "a@b.com"])

        sut.subscriberHash = "hash-2"

        XCTAssertEqual(sut.subscriberFields, [:],
                       "Subscriber-fields cache must wipe when subscriberHash changes — the cache " +
                       "is keyed to the current subscriber and stale entries would short-circuit a " +
                       "subsequent identify() incorrectly")
    }

    func test_subscriberHash_settingSameValue_doesNotWipeSubscriberFieldsCache() {
        sut.subscriberHash = "hash-1"
        sut.mergeSubscriberFields(["email": "a@b.com"])
        sut.subscriberHash = "hash-1"

        XCTAssertEqual(sut.subscriberFields, ["email": "a@b.com"],
                       "Setting subscriberHash to the same value must not wipe the cache")
    }

    func test_subscriberHash_emptyOverwriteOfNonEmpty_isNoOp() {
        // Parse-error paths in subscriber-service can transiently set this to "".
        // Treat that as a no-op rather than clobbering valid state.
        sut.subscriberHash = "hash-1"
        sut.subscriberHash = ""
        XCTAssertEqual(sut.subscriberHash, "hash-1",
                       "Empty value must not overwrite a non-empty subscriberHash")
    }

    func test_subscriberHash_emptyOverwriteOfNonEmpty_doesNotWipeSubscriberFieldsCache() {
        sut.subscriberHash = "hash-1"
        sut.mergeSubscriberFields(["email": "a@b.com"])
        sut.subscriberHash = ""
        XCTAssertEqual(sut.subscriberFields, ["email": "a@b.com"],
                       "Transient empty write must not wipe the cache either")
    }

    func test_subscriberHash_emptyOnFreshState_isAllowed() {
        // When there's no previous value, writing empty is a true no-op.
        sut.subscriberHash = ""
        XCTAssertEqual(sut.subscriberHash, "")
    }
}
