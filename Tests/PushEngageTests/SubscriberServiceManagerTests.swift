import XCTest
@testable import PushEngage

final class SubscriberServiceManagerTests: XCTestCase {

    private var datasource: MockDataSource!
    private var network: MockNetworkRouter!
    private var userDefaults: MockUserDefaultsService!
    private var sut: SubscriberServiceManager!

    private let okJSON = #"{"error_code":0}"#
    private let errorJSON = #"{"error_code":7,"error_message":"oops"}"#
    private let garbageJSON = "not valid json"

    override func setUp() {
        super.setUp()
        datasource = MockDataSource()
        datasource.stubbedSubscriptionInfo = Fixtures.makeSubscriptionInfo()
        datasource.stubbedSubscriberDetails = Fixtures.makeSubscriberDetails()
        datasource.stubbedSubscriberUpgrade = Fixtures.makeSubscriberUpgrade()
        network = MockNetworkRouter()
        userDefaults = MockUserDefaultsService()
        userDefaults.subscriberHash = "hash-1"
        sut = SubscriberServiceManager(datasourceProtocol: datasource,
                                       networkRouter: network,
                                       userDefault: userDefaults)
    }

    override func tearDown() {
        sut = nil
        userDefaults = nil
        network = nil
        datasource = nil
        super.tearDown()
    }

    // MARK: - sendGoal

    func test_sendGoal_emptyName_returnsInvalidInputWithoutNetworkCall() {
        let exp = expectation(description: "completion")
        let emptyGoal = Goal(name: "", count: Int?.none, value: Double?.none)
        sut.sendGoal(goal: emptyGoal) { success, error in
            XCTAssertFalse(success)
            if case .invalidInput? = error { exp.fulfill() } else { XCTFail() }
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(network.requestCallCount, 0)
    }

    func test_sendGoal_happyPath() {
        network.enqueueSuccess(okJSON)
        let exp = expectation(description: "completion")
        sut.sendGoal(goal: Goal(name: "purchase", count: 1, value: 9.99)) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_sendGoal_serverError() {
        network.enqueueSuccess(errorJSON)
        let exp = expectation(description: "completion")
        sut.sendGoal(goal: Goal(name: "purchase", count: 1, value: 1.0)) { success, error in
            XCTAssertFalse(success)
            if case .networkResponseFailure(let code, _)? = error {
                XCTAssertEqual(code, 7)
                exp.fulfill()
            } else { XCTFail() }
        }
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - addSubscriber

    func test_addSubscriber_happyPath_storesHashAndResetsFlags() {
        network.enqueueSuccess(#"{"error_code":0,"data":{"subscriber_hash":"new-hash"}}"#)
        userDefaults.isSubscriberDeleted = true

        let exp = expectation(description: "completion")
        sut.addSubscriber { response, error in
            XCTAssertEqual(response?.subscriberHash, "new-hash")
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(userDefaults.subscriberHash, "new-hash")
        XCTAssertFalse(userDefaults.isSubscriberDeleted,
                       "Happy path resets isSubscriberDeleted")
        XCTAssertNotNil(userDefaults.lastSmartSubscribeDate)
    }

    func test_addSubscriber_serverError_setsSubscriberDeleted() {
        network.enqueueSuccess(errorJSON)

        let exp = expectation(description: "completion")
        sut.addSubscriber { response, error in
            XCTAssertNil(response)
            if case .networkResponseFailure? = error { exp.fulfill() } else { XCTFail() }
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(userDefaults.isSubscriberDeleted)
    }

    func test_addSubscriber_parseError_setsSubscriberDeleted() {
        network.enqueueSuccess(garbageJSON)

        let exp = expectation(description: "completion")
        sut.addSubscriber { _, error in
            if case .parsingError? = error { exp.fulfill() } else { XCTFail() }
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(userDefaults.isSubscriberDeleted)
    }

    func test_addSubscriber_networkError_setsSubscriberDeleted() {
        network.enqueueFailure(.dataNotFound)

        let exp = expectation(description: "completion")
        sut.addSubscriber { _, error in
            if case .dataNotFound? = error { exp.fulfill() } else { XCTFail() }
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(userDefaults.isSubscriberDeleted)
    }

    // MARK: - updateSubscriber

    func test_updateSubscriber_happyPath() {
        network.enqueueSuccess(okJSON)
        let exp = expectation(description: "completion")
        sut.updateSubscriber { response, error in
            XCTAssertNotNil(response)
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_updateSubscriber_serverError() {
        network.enqueueSuccess(errorJSON)
        let exp = expectation(description: "completion")
        sut.updateSubscriber { response, error in
            XCTAssertNil(response)
            if case .networkResponseFailure? = error { exp.fulfill() } else { XCTFail() }
        }
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - checkSubscriber

    func test_checkSubscriber_happyPath() {
        network.enqueueSuccess(#"{"error_code":0,"data":{"gateway_endpoint":"endpoint-1"}}"#)
        let exp = expectation(description: "completion")
        sut.checkSubscriber { data, error in
            XCTAssertEqual(data?.deviceToken, "endpoint-1")
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_checkSubscriber_serverError() {
        network.enqueueSuccess(errorJSON)
        let exp = expectation(description: "completion")
        sut.checkSubscriber { _, error in
            if case .networkResponseFailure? = error { exp.fulfill() } else { XCTFail() }
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_checkSubscriber_parseError() {
        network.enqueueSuccess(garbageJSON)
        let exp = expectation(description: "completion")
        sut.checkSubscriber { _, error in
            if case .parsingError? = error { exp.fulfill() } else { XCTFail() }
        }
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - getSubscriber

    func test_getSubscriber_happyPath_fieldsForwarded() {
        network.enqueueSuccess(#"{"error_code":0,"data":{"profile_id":"p1"}}"#)
        let exp = expectation(description: "completion")
        sut.getSubscriber(for: ["profile_id"]) { data, error in
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_getSubscriber_nilFieldsAllowed() {
        network.enqueueSuccess(#"{"error_code":0,"data":{}}"#)
        let exp = expectation(description: "completion")
        sut.getSubscriber(for: nil) { _, error in
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - Attributes (set / add / get / delete)

    func test_setSubscriberAttributes_happyPath() {
        network.enqueueSuccess(okJSON)
        let exp = expectation(description: "completion")
        sut.setSubscriberAttributes(attributes: ["k": "v"]) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_addSubscriberAttributes_happyPath() {
        network.enqueueSuccess(okJSON)
        let exp = expectation(description: "completion")
        sut.addSubscriberAttributes(attributes: ["k": "v"]) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_getAttribute_happyPath_returnsDataDict() {
        network.enqueueSuccess(#"{"error_code":0,"data":{"name":"Bob","age":30}}"#)
        let exp = expectation(description: "completion")
        sut.getAttribute { data, error in
            XCTAssertEqual(data?["name"] as? String, "Bob")
            XCTAssertEqual(data?["age"] as? Int, 30)
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_getAttribute_missingDataField_returnsError() {
        network.enqueueSuccess(#"{"error_code":99,"error_message":"missing"}"#)
        let exp = expectation(description: "completion")
        sut.getAttribute { data, error in
            XCTAssertNil(data)
            if case .networkResponseFailure(let code, _)? = error {
                XCTAssertEqual(code, 99)
                exp.fulfill()
            } else { XCTFail() }
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_deleteAttribute_happyPath() {
        network.enqueueSuccess(okJSON)
        let exp = expectation(description: "completion")
        sut.deleteAttribute(with: ["k1", "k2"]) { success, error in
            XCTAssertTrue(success)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - updateSubscriberStatus

    func test_updateSubscriberStatus_zero_doesNotSetNotificationDisabled() {
        network.enqueueSuccess(okJSON)
        let exp = expectation(description: "completion")
        sut.updateSubscriberStatus(status: 0) { success, _ in
            XCTAssertTrue(success)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_updateSubscriberStatus_one_consultsDeleteOnDisableFlag() {
        userDefaults._setIsDeleteSubscriberOnDisable(true)
        network.enqueueSuccess(okJSON)
        let exp = expectation(description: "completion")
        sut.updateSubscriberStatus(status: 1) { success, _ in
            XCTAssertTrue(success)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - addProfile

    func test_addProfile_happyPath() {
        network.enqueueSuccess(okJSON)
        let exp = expectation(description: "completion")
        sut.addProfile(id: "new-profile") { success, _ in
            XCTAssertTrue(success)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_addProfile_serverError() {
        network.enqueueSuccess(errorJSON)
        let exp = expectation(description: "completion")
        sut.addProfile(id: "x") { success, error in
            XCTAssertFalse(success)
            if case .networkResponseFailure? = error { exp.fulfill() } else { XCTFail() }
        }
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - upgradeSubscription

    func test_upgradeSubscription_happyPath() {
        network.enqueueSuccess(okJSON)
        let exp = expectation(description: "completion")
        sut.upgradeSubscription { success, _ in
            XCTAssertTrue(success)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_upgradeSubscription_parseError() {
        network.enqueueSuccess(garbageJSON)
        let exp = expectation(description: "completion")
        sut.upgradeSubscription { success, error in
            XCTAssertFalse(success)
            if case .parsingError? = error { exp.fulfill() } else { XCTFail() }
        }
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - Segments

    func test_updateSegments_add() {
        network.enqueueSuccess(okJSON)
        let exp = expectation(description: "completion")
        sut.update(segments: ["s1", "s2"], action: .add) { success, _ in
            XCTAssertTrue(success)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_updateSegments_remove() {
        network.enqueueSuccess(okJSON)
        let exp = expectation(description: "completion")
        sut.update(segments: ["s1"], action: .remove) { success, _ in
            XCTAssertTrue(success)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_updateDynamicSegments_happyPath() {
        network.enqueueSuccess(okJSON)
        let exp = expectation(description: "completion")
        sut.update(dynamic: [["name": "premium", "duration": 30]]) { success, _ in
            XCTAssertTrue(success)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_updateDynamicSegments_malformedInput_returnsParsingError() {
        // Missing "duration" field — won't decode to [Segment]
        let exp = expectation(description: "completion")
        sut.update(dynamic: [["name": "premium"]]) { success, error in
            XCTAssertFalse(success)
            if case .parsingError? = error { exp.fulfill() } else { XCTFail() }
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(network.requestCallCount, 0)
    }

    // MARK: - segmentHashArray

    func test_segmentHashArray_happyPath() {
        network.enqueueSuccess(okJSON)
        let exp = expectation(description: "completion")
        sut.segmentHashArray(for: 7) { success, _ in
            XCTAssertTrue(success)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - automatedNotification

    func test_automatedNotification_enabled() {
        network.enqueueSuccess(okJSON)
        let exp = expectation(description: "completion")
        sut.automatedNotification(status: .enabled) { success, _ in
            XCTAssertTrue(success)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_automatedNotification_disabled() {
        network.enqueueSuccess(okJSON)
        let exp = expectation(description: "completion")
        sut.automatedNotification(status: .disabled) { success, _ in
            XCTAssertTrue(success)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - syncSiteInfo

    func test_syncSiteInfo_happyPath_writesToUserDefaults() {
        network.enqueueSuccess(#"{"error_code":0,"data":{"site_id":42,"site_status":"active"}}"#)
        let exp = expectation(description: "completion")
        sut.syncSiteInfo(for: "site-key") { data, error in
            XCTAssertEqual(data?.siteID, 42)
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(userDefaults.saveCallCount, 1,
                       "Sync should persist the response object to UserDefaults")
        XCTAssertEqual(userDefaults.lastSaveKey, "pushengage_sync_api")
    }

    func test_syncSiteInfo_serverError() {
        network.enqueueSuccess(errorJSON)
        let exp = expectation(description: "completion")
        sut.syncSiteInfo(for: "site-key") { _, error in
            if case .networkResponseFailure? = error { exp.fulfill() } else { XCTFail() }
        }
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - updateSettingPermission (writes flags)

    /// Production behavior: writes through to UserDefaults.
    /// The dispatch group inside updateSettingPermission waits up to NetworkConstants.requestTimeout
    /// for syncSiteInfo to complete — our mock fires synchronously, so it returns immediately.
    func test_updateSettingPermission_grantedRunsSyncAndUpdate() {
        // syncSiteInfo response + updateSubscriberStatus response, both 0
        network.stubbedResults = [
            .success(Data(okJSON.utf8)),
            .success(Data(okJSON.utf8)),
        ]
        userDefaults.notificationPermissionState = .granted
        userDefaults.siteKey = "site-key"

        sut.updateSettingPermission(status: .granted)

        XCTAssertEqual(network.requestCallCount, 2,
                       "updateSettingPermission must call syncSiteInfo then updateSubscriberStatus")
    }
}
