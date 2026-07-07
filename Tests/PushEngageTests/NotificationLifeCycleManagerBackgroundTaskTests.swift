import XCTest
@testable import PushEngage
@testable import PushEngageExtension

private final class SpyBackgroundTask: BackgroundTaskType {
    private(set) var endCallCount = 0
    private let onEnd: () -> Void

    init(onEnd: @escaping () -> Void) {
        self.onEnd = onEnd
    }

    func end() {
        endCallCount += 1
        onEnd()
    }
}

private final class SpyBackgroundTaskProvider: BackgroundTaskProviderType {
    private(set) var runCallCount = 0
    private(set) var tasks: [SpyBackgroundTask] = []
    var providesTask = true
    var events: [String] = []

    func run(handler: (BackgroundTaskType?) -> Void) {
        runCallCount += 1
        events.append("begin")
        if providesTask {
            let task = SpyBackgroundTask { [weak self] in self?.events.append("end") }
            tasks.append(task)
            handler(task)
        } else {
            handler(nil)
        }
    }
}

final class NotificationLifeCycleManagerBackgroundTaskTests: XCTestCase {

    private var network: MockNetworkRouter!
    private var datasource: MockDataSource!
    private var userDefaults: MockUserDefaultsService!
    private var backgroundTask: SpyBackgroundTaskProvider!
    private var sut: NotificationLifeCycleManager!

    override func setUp() {
        super.setUp()
        network = MockNetworkRouter()
        datasource = MockDataSource()
        datasource.stubbedSponsoredPush = Fixtures.makeSponsoredPush()
        userDefaults = MockUserDefaultsService()
        backgroundTask = SpyBackgroundTaskProvider()
        sut = NotificationLifeCycleManager(networkRouter: network,
                                           datasource: datasource,
                                           userDefault: userDefaults,
                                           backgroundTask: backgroundTask)
    }

    override func tearDown() {
        sut = nil
        backgroundTask = nil
        userDefaults = nil
        datasource = nil
        network = nil
        super.tearDown()
    }

    // MARK: - withRetrynotificationLifecycleUpdate

    func test_lifecycleUpdate_success_requestRunsInsideTask_endsAfterCompletion() {
        network.enqueueSuccess(#"{"error_code":0,"error_message":null}"#)

        let expectation = expectation(description: "completion fires")
        sut.withRetrynotificationLifecycleUpdate(with: .viewed,
                                                 deviceHash: "h",
                                                 notificationId: "n",
                                                 actionid: nil) { [weak backgroundTask] result in
            guard case .success = result else {
                return XCTFail("Expected success, got \(result)")
            }
            backgroundTask?.events.append("completion")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(backgroundTask.runCallCount, 1)
        XCTAssertEqual(backgroundTask.tasks.first?.endCallCount, 1)
        XCTAssertEqual(backgroundTask.events, ["begin", "completion", "end"])
        XCTAssertEqual(network.requestCallCount, 1)
    }

    func test_lifecycleUpdate_nonRetryableFailure_endsTaskAfterCompletion() {
        network.enqueueSuccess(#"{"error_code":42,"error_message":"bad request"}"#)

        let expectation = expectation(description: "completion fires")
        sut.withRetrynotificationLifecycleUpdate(with: .clicked,
                                                 deviceHash: "h",
                                                 notificationId: "n",
                                                 actionid: "btn-1") { [weak backgroundTask] result in
            guard case .failure(.notificationUserActionFailed) = result else {
                return XCTFail("Expected notificationUserActionFailed, got \(result)")
            }
            backgroundTask?.events.append("completion")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(backgroundTask.tasks.first?.endCallCount, 1)
        XCTAssertEqual(backgroundTask.events, ["begin", "completion", "end"])
    }

    func test_lifecycleUpdate_withoutTask_stillDeliversCompletion() {
        backgroundTask.providesTask = false
        network.enqueueSuccess(#"{"error_code":0,"error_message":null}"#)

        let expectation = expectation(description: "completion fires")
        sut.withRetrynotificationLifecycleUpdate(with: .viewed,
                                                 deviceHash: "h",
                                                 notificationId: "n",
                                                 actionid: nil) { [weak backgroundTask] result in
            guard case .success = result else {
                return XCTFail("Expected success, got \(result)")
            }
            backgroundTask?.events.append("completion")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(backgroundTask.runCallCount, 1)
        XCTAssertTrue(backgroundTask.tasks.isEmpty)
        XCTAssertEqual(backgroundTask.events, ["begin", "completion"])
    }

    // MARK: - withRetrysponseredNotification

    func test_sponsoredNotification_success_requestRunsInsideTask_endsAfterCompletion() {
        network.enqueueSuccess(#"{"error_code":0,"data":{"t":"New Title","u":"https://x.test","tag":"new-tag"}}"#)
        let notification = PENotification(userInfo: Fixtures.sponsoredPayload)

        let expectation = expectation(description: "completion fires")
        sut.withRetrysponseredNotification(with: notification) { [weak backgroundTask] result in
            guard case .success = result else {
                return XCTFail("Expected success, got \(result)")
            }
            backgroundTask?.events.append("completion")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(backgroundTask.runCallCount, 1)
        XCTAssertEqual(backgroundTask.tasks.first?.endCallCount, 1)
        XCTAssertEqual(backgroundTask.events, ["begin", "completion", "end"])
    }

    func test_sponsoredNotification_nonRetryableFailure_endsTaskAfterCompletion() {
        network.enqueueSuccess(#"{"error_code":7,"error_message":"oops"}"#)
        let notification = PENotification(userInfo: Fixtures.sponsoredPayload)

        let expectation = expectation(description: "completion fires")
        sut.withRetrysponseredNotification(with: notification) { [weak backgroundTask] result in
            guard case .failure(.networkResponseFailure) = result else {
                return XCTFail("Expected networkResponseFailure, got \(result)")
            }
            backgroundTask?.events.append("completion")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(backgroundTask.tasks.first?.endCallCount, 1)
        XCTAssertEqual(backgroundTask.events, ["begin", "completion", "end"])
    }

    // MARK: - ExtensionBackgroundTaskProvider

    func test_extensionBackgroundTaskProvider_invokesHandlerOnceWithNilTask() {
        var handlerCallCount = 0
        ExtensionBackgroundTaskProvider().run { task in
            handlerCallCount += 1
            XCTAssertNil(task)
        }
        XCTAssertEqual(handlerCallCount, 1)
    }
}
