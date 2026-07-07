import XCTest
@testable import PushEngage
@testable import PushEngageExtension
final class NotificationLifeCycleManagerTests: XCTestCase {

    private var network: MockNetworkRouter!
    private var datasource: MockDataSource!
    private var userDefaults: MockUserDefaultsService!
    private var sut: NotificationLifeCycleManager!

    override func setUp() {
        super.setUp()
        network = MockNetworkRouter()
        datasource = MockDataSource()
        datasource.stubbedSponsoredPush = Fixtures.makeSponsoredPush()
        userDefaults = MockUserDefaultsService()
        sut = NotificationLifeCycleManager(networkRouter: network,
                                           datasource: datasource,
                                           userDefault: userDefaults,
                                           backgroundTask: ExtensionBackgroundTaskProvider())
    }

    override func tearDown() {
        sut = nil
        userDefaults = nil
        datasource = nil
        network = nil
        super.tearDown()
    }

    // MARK: - withRetrynotificationLifecycleUpdate

    func test_lifecycleUpdate_happyPath_callsCompletionWithSuccess() {
        network.enqueueSuccess(#"{"error_code":0,"error_message":null}"#)

        let expectation = expectation(description: "completion fires")
        sut.withRetrynotificationLifecycleUpdate(with: .viewed,
                                                 deviceHash: "hash-1",
                                                 notificationId: "n-1",
                                                 actionid: nil) { result in
            if case .success(let value) = result {
                XCTAssertTrue(value)
            } else {
                XCTFail("Expected success, got \(result)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(network.requestCallCount, 1)
    }

    func test_lifecycleUpdate_serverErrorCode_failsWithUserActionFailed() {
        network.enqueueSuccess(#"{"error_code":42,"error_message":"bad request"}"#)

        let expectation = expectation(description: "completion fires")
        sut.withRetrynotificationLifecycleUpdate(with: .clicked,
                                                 deviceHash: "h",
                                                 notificationId: "n",
                                                 actionid: "btn-1") { result in
            if case .failure(.notificationUserActionFailed(let message)) = result {
                XCTAssertEqual(message, "bad request")
            } else {
                XCTFail("Expected notificationUserActionFailed, got \(result)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func test_lifecycleUpdate_garbageJSON_failsWithParsingError() {
        network.enqueueSuccess("not valid json")

        let expectation = expectation(description: "completion fires")
        sut.withRetrynotificationLifecycleUpdate(with: .clicked,
                                                 deviceHash: "h",
                                                 notificationId: "n",
                                                 actionid: nil) { result in
            if case .failure(.parsingError) = result {
                expectation.fulfill()
            } else {
                XCTFail("Expected parsingError, got \(result)")
            }
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func test_lifecycleUpdate_nonRetryableNetworkError_passesThrough() {
        // 4xx status codes are NOT retried by Utility.retryCheck — completion fires immediately
        network.enqueueFailure(.invalidStatusCode("client error", 400))

        let expectation = expectation(description: "completion fires")
        sut.withRetrynotificationLifecycleUpdate(with: .viewed,
                                                 deviceHash: "h",
                                                 notificationId: "n",
                                                 actionid: nil) { result in
            if case .failure(.invalidStatusCode(_, let code)) = result {
                XCTAssertEqual(code, 400)
                expectation.fulfill()
            } else {
                XCTFail("Expected invalidStatusCode passthrough, got \(result)")
            }
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - withRetrysponseredNotification

    func test_sponseredNotification_happyPath_callsDatasourceAndReturnsData() {
        datasource.stubbedSponsoredPush = SponsoredPush(tag: "spons-1", postback: nil)
        network.enqueueSuccess(#"{"error_code":0,"data":{"t":"New Title","u":"https://x.test","tag":"new-tag"}}"#)
        let notification = PENotification(userInfo: Fixtures.sponsoredPayload)

        let expectation = expectation(description: "completion fires")
        sut.withRetrysponseredNotification(with: notification) { result in
            if case .success(let data) = result {
                XCTAssertEqual(data.title, "New Title")
                XCTAssertEqual(data.launchURL, "https://x.test")
                XCTAssertEqual(data.tag, "new-tag")
                expectation.fulfill()
            } else {
                XCTFail("Expected success, got \(result)")
            }
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(datasource.getPostBackSubscriptionDataCallCount, 1)
        XCTAssertEqual(datasource.lastPostbackNotification?.tag, notification.tag)
    }

    func test_sponseredNotification_errorCodeNonZero_failsWithNetworkResponseFailure() {
        network.enqueueSuccess(#"{"error_code":7,"error_message":"oops"}"#)
        let notification = PENotification(userInfo: Fixtures.sponsoredPayload)

        let expectation = expectation(description: "completion fires")
        sut.withRetrysponseredNotification(with: notification) { result in
            if case .failure(.networkResponseFailure(let code, let message)) = result {
                XCTAssertEqual(code, 7)
                XCTAssertEqual(message, "oops")
                expectation.fulfill()
            } else {
                XCTFail("Expected networkResponseFailure, got \(result)")
            }
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func test_sponseredNotification_parsingError() {
        network.enqueueSuccess("not valid json")
        let notification = PENotification(userInfo: Fixtures.sponsoredPayload)

        let expectation = expectation(description: "completion fires")
        sut.withRetrysponseredNotification(with: notification) { result in
            if case .failure(.parsingError) = result {
                expectation.fulfill()
            } else {
                XCTFail("Expected parsingError, got \(result)")
            }
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - cancelled

    func test_cancelled_cancelsNetworkRequest() {
        sut.cancelled()
        XCTAssertEqual(network.cancelCallCount, 1)
    }
}
