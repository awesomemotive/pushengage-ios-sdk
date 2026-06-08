import XCTest
@testable import PushEngage

final class TriggerCampaignManagerTests: XCTestCase {

    private var userDefaults: MockUserDefaultsService!
    private var network: MockNetworkRouter!
    private var datasource: MockDataSource!
    private var sut: TriggerCampaignManager!

    override func setUp() {
        super.setUp()
        userDefaults = MockUserDefaultsService()
        network = MockNetworkRouter()
        datasource = MockDataSource()
        datasource.stubbedSubscriberDetails = Fixtures.makeSubscriberDetails()
        sut = TriggerCampaignManager(userDefaultService: userDefaults,
                                     networkService: network,
                                     dataSource: datasource)
    }

    override func tearDown() {
        sut = nil
        datasource = nil
        network = nil
        userDefaults = nil
        super.tearDown()
    }

    // MARK: - sendTriggerEvent

    func test_sendTriggerEvent_emptyCampaignName_failsWithInvalidInput() {
        let trigger = TriggerCampaign(campaignName: "", eventName: "evt")

        let expectation = expectation(description: "completion")
        sut.sendTriggerEvent(trigger: trigger) { response, error in
            XCTAssertFalse(response)
            if case .invalidInput? = error {
                expectation.fulfill()
            } else {
                XCTFail("Expected invalidInput error, got \(String(describing: error))")
            }
        }
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(network.requestCallCount, 0,
                       "Network must not be called for invalid input")
    }

    func test_sendTriggerEvent_emptyEventName_failsWithInvalidInput() {
        let trigger = TriggerCampaign(campaignName: "campaign", eventName: "")

        let expectation = expectation(description: "completion")
        sut.sendTriggerEvent(trigger: trigger) { response, error in
            XCTAssertFalse(response)
            if case .invalidInput? = error {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func test_sendTriggerEvent_happyPath_callsNetworkAndReturnsTrue() {
        network.enqueueSuccess(#"{"SequenceNumber":"seq-1","ShardId":"shard-1"}"#)
        let trigger = TriggerCampaign(campaignName: "campaign",
                                      eventName: "event",
                                      referenceId: "ref",
                                      profileId: "prof",
                                      data: ["k": "v"])

        let expectation = expectation(description: "completion")
        sut.sendTriggerEvent(trigger: trigger) { response, error in
            XCTAssertTrue(response)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(network.requestCallCount, 1)
    }

    func test_sendTriggerEvent_garbageJSON_returnsParsingError() {
        network.enqueueSuccess("not valid json")
        let trigger = TriggerCampaign(campaignName: "c", eventName: "e")

        let expectation = expectation(description: "completion")
        sut.sendTriggerEvent(trigger: trigger) { response, error in
            XCTAssertFalse(response)
            if case .parsingError? = error {
                expectation.fulfill()
            } else {
                XCTFail("Expected parsingError, got \(String(describing: error))")
            }
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func test_sendTriggerEvent_networkFailure_propagatesError() {
        network.enqueueFailure(.invalidStatusCode("server", 500))
        let trigger = TriggerCampaign(campaignName: "c", eventName: "e")

        let expectation = expectation(description: "completion")
        sut.sendTriggerEvent(trigger: trigger) { response, error in
            XCTAssertFalse(response)
            if case .invalidStatusCode(_, let code)? = error {
                XCTAssertEqual(code, 500)
                expectation.fulfill()
            } else {
                XCTFail("Expected invalidStatusCode passthrough, got \(String(describing: error))")
            }
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - addAlert

    func test_addAlert_happyPath_priceDrop() {
        network.enqueueSuccess(#"{"error_code":0}"#)
        let alert = TriggerAlert(type: .priceDrop,
                                 productId: "prod-1",
                                 link: "https://x.test",
                                 price: 9.99)

        let expectation = expectation(description: "completion")
        sut.addAlert(triggerAlert: alert) { response, error in
            XCTAssertTrue(response)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func test_addAlert_happyPath_inventory_withFullOptionalFields() {
        network.enqueueSuccess(#"{"error_code":0}"#)
        let alert = TriggerAlert(type: .inventory,
                                 productId: "prod-2",
                                 link: "https://x.test/2",
                                 price: 19.99,
                                 variantId: "v-1",
                                 expiryTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
                                 alertPrice: 14.99,
                                 availability: .inStock,
                                 profileId: "prof-1",
                                 mrp: 24.99,
                                 data: ["custom": "field"])

        let expectation = expectation(description: "completion")
        sut.addAlert(triggerAlert: alert) { response, error in
            XCTAssertTrue(response)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func test_addAlert_serverErrorCode_returnsCustomError() {
        network.enqueueSuccess(#"{"error_code":42,"error_message":"out of stock"}"#)
        let alert = TriggerAlert(type: .inventory, productId: "p", link: "https://x.test", price: 1)

        let expectation = expectation(description: "completion")
        sut.addAlert(triggerAlert: alert) { response, error in
            XCTAssertFalse(response)
            if case .custom(let message)? = error {
                XCTAssertEqual(message, "out of stock")
                expectation.fulfill()
            } else {
                XCTFail("Expected custom error, got \(String(describing: error))")
            }
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func test_addAlert_networkFailure_propagatesError() {
        network.enqueueFailure(.dataNotFound)
        let alert = TriggerAlert(type: .priceDrop, productId: "p", link: "https://x.test", price: 1)

        let expectation = expectation(description: "completion")
        sut.addAlert(triggerAlert: alert) { response, error in
            XCTAssertFalse(response)
            if case .dataNotFound? = error {
                expectation.fulfill()
            } else {
                XCTFail("Expected dataNotFound, got \(String(describing: error))")
            }
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func test_addAlert_garbageJSON_returnsParsingError() {
        network.enqueueSuccess("not json")
        let alert = TriggerAlert(type: .priceDrop, productId: "p", link: "https://x.test", price: 1)

        let expectation = expectation(description: "completion")
        sut.addAlert(triggerAlert: alert) { response, error in
            XCTAssertFalse(response)
            if case .parsingError? = error {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 1.0)
    }
}
