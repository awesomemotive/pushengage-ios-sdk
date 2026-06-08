import XCTest
import UserNotifications
@testable import PushEngage

/// Tier 8 — operation lifecycle + concrete operations.

final class OperationsTests: XCTestCase {

    // MARK: - AsyncOperation lifecycle

    func test_asyncOperation_finishesViaMainImpl() {
        let operation = AsyncOperation()
        let queue = OperationQueue()
        let exp = expectation(description: "finished")
        operation.completionBlock = { exp.fulfill() }

        queue.addOperation(operation)
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(operation.isFinished)
        XCTAssertFalse(operation.isExecuting)
    }

    func test_asyncOperation_isAsynchronous() {
        XCTAssertTrue(AsyncOperation().isAsynchronous)
    }

    // MARK: - AsyncResultOperation finish + result

    private final class TestResultOperation: AsyncResultOperation<String, PEError> {
        var produce: () -> Result<String, PEError> = { .failure(.cancelled) }
        override func main() {
            finish(with: produce())
        }
        // Override the parent's fatalError-y cancel() so tests can cancel safely.
        override func cancel() {
            cancel(with: .cancelled)
        }
    }

    func test_asyncResultOperation_finishWithSuccess_callsOnResult() {
        let operation = TestResultOperation()
        operation.produce = { .success("hello") }

        var captured: Result<String, PEError>?
        operation.onResult = { captured = $0 }

        let exp = expectation(description: "completion")
        operation.completionBlock = { exp.fulfill() }
        OperationQueue().addOperation(operation)
        wait(for: [exp], timeout: 1.0)

        XCTAssertNotNil(captured)
        if case .success(let value) = captured! {
            XCTAssertEqual(value, "hello")
        } else {
            XCTFail("Expected success")
        }
        XCTAssertTrue(operation.isFinished)
    }

    func test_asyncResultOperation_finishWithFailure_callsOnResult() {
        let operation = TestResultOperation()
        operation.produce = { .failure(.networkError) }

        var captured: Result<String, PEError>?
        operation.onResult = { captured = $0 }

        let exp = expectation(description: "completion")
        operation.completionBlock = { exp.fulfill() }
        OperationQueue().addOperation(operation)
        wait(for: [exp], timeout: 1.0)

        if case .failure(.networkError) = captured! {
            // ok
        } else {
            XCTFail("Expected failure(.networkError), got \(String(describing: captured))")
        }
    }

    // MARK: - ChainedAsyncResultOperation — input injection from dependencies

    private final class StringProducer: AsyncResultOperation<String, PEError> {
        var produce: () -> Result<String, PEError> = { .success("upstream") }
        override func main() { finish(with: produce()) }
        override func cancel() { cancel(with: .cancelled) }
    }

    private final class StringConsumer: ChainedAsyncResultOperation<String, String, PEError> {
        var capturedInput: String?
        override func main() {
            capturedInput = input
            finish(with: .success(input ?? "no-input"))
        }
        override func cancel() { cancel(with: .cancelled) }
    }

    func test_chainedOperation_pullsInputFromUpstreamDependency() {
        let producer = StringProducer()
        let consumer = StringConsumer()
        consumer.addDependency(producer)

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let exp = expectation(description: "consumer done")
        consumer.completionBlock = { exp.fulfill() }

        queue.addOperations([producer, consumer], waitUntilFinished: false)
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(consumer.capturedInput, "upstream",
                       "Consumer must receive the producer's success output as its input")
    }

    func test_chainedOperation_explicitInputIsNotOverridden() {
        let producer = StringProducer()  // would output "upstream"
        let consumer = StringConsumer(input: "explicit")
        consumer.addDependency(producer)

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let exp = expectation(description: "consumer done")
        consumer.completionBlock = { exp.fulfill() }
        queue.addOperations([producer, consumer], waitUntilFinished: false)
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(consumer.capturedInput, "explicit",
                       "Explicit init input must take precedence over upstream dependency output")
    }

    // MARK: - DownloadAttachmentOperation

    // For the cancel-during-main paths we drive the operation synchronously via
    // `start()` rather than an OperationQueue, because the SDK's cancel(with:)
    // does NOT advance isFinished, so the queue's completionBlock would never
    // fire and the test would time out.

    func test_downloadAttachmentOperation_nilInput_cancels() {
        let op = DownloadAttachmentOperation(inputValue: nil)
        op.start()

        XCTAssertTrue(op.isCancelled)
        if case .failure(.cancelled) = op.result {
            // ok
        } else {
            XCTFail("Expected cancelled result, got \(String(describing: op.result))")
        }
    }

    func test_downloadAttachmentOperation_emptyAttachmentString_cancels() {
        let content = UNMutableNotificationContent()
        let network = MockNetworkRouter()
        let op = DownloadAttachmentOperation(inputValue: (attachmentString: nil,
                                                          contentToModifiy: content,
                                                          networkService: network))
        op.start()

        XCTAssertTrue(op.isCancelled)
        XCTAssertEqual(network.downloadCallCount, 0,
                       "Nil attachmentString must short-circuit before any network call")
        XCTAssertEqual(network.cancelCallCount, 1,
                       "Cancel path also calls networkService.cancel()")
    }

    func test_downloadAttachmentOperation_networkFailure_finishesWithUnderlyingError() {
        let content = UNMutableNotificationContent()
        let network = MockNetworkRouter()
        network.defaultDownloadResult = .failure(.networkError)
        let op = DownloadAttachmentOperation(inputValue: (attachmentString: "https://example.test/img.png",
                                                          contentToModifiy: content,
                                                          networkService: network))
        let queue = OperationQueue()
        let exp = expectation(description: "done")
        op.completionBlock = { exp.fulfill() }
        queue.addOperation(op)
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(network.downloadCallCount, 1)
        if case .failure(.underlying) = op.result {
            // ok
        } else {
            XCTFail("Expected underlying-error failure, got \(String(describing: op.result))")
        }
    }

    // MARK: - SponseredNotifictaionOperation

    private func sponsoredInput(notification: PENotification = PENotification(userInfo: Fixtures.sponsoredPayload),
                                lifecycle: MockNotificationLifeCycleService = MockNotificationLifeCycleService(),
                                network: MockNetworkRouter = MockNetworkRouter())
        -> SponseredNotificationInput {
        return (previousAttachment: "https://previous/img.png",
                mutableContent: UNMutableNotificationContent(),
                notificationLifeCycle: lifecycle,
                network: network,
                notification: notification)
    }

    func test_sponseredOperation_success_appliesContentAndFinishesWithDownloadInput() {
        let lifecycle = MockNotificationLifeCycleService()
        let sponsoredData = sampleSponsoredData()
        lifecycle.sponseredResult = .success(sponsoredData)

        var input = sponsoredInput(lifecycle: lifecycle)
        input.mutableContent.userInfo = ["pe": ["tag": "orig"]]
        let op = SponseredNotifictaionOperation(input: input)

        let queue = OperationQueue()
        let exp = expectation(description: "done")
        op.completionBlock = { exp.fulfill() }
        queue.addOperation(op)
        wait(for: [exp], timeout: 1.0)

        // Content mutated with the sponsored response
        XCTAssertEqual(input.mutableContent.title, "Sponsored Title")
        XCTAssertEqual(input.mutableContent.body, "Sponsored Body")

        // Success result is the download input (icon, content, network)
        if case .success(let downloadInput) = op.result {
            XCTAssertEqual(downloadInput.attachmentString, "https://sponsored/icon.png")
        } else {
            XCTFail("Expected success download input")
        }
    }

    func test_sponseredOperation_failure_finishesWithSponseredFailWithContent() {
        let lifecycle = MockNotificationLifeCycleService()
        lifecycle.sponseredResult = .failure(.networkError)
        let op = SponseredNotifictaionOperation(input: sponsoredInput(lifecycle: lifecycle))

        let queue = OperationQueue()
        let exp = expectation(description: "done")
        op.completionBlock = { exp.fulfill() }
        queue.addOperation(op)
        wait(for: [exp], timeout: 1.0)

        if case .failure(.sponseredfailWithContent(let attachment, _)) = op.result {
            XCTAssertEqual(attachment, "https://previous/img.png",
                           "Failure case must carry the previousAttachment forward")
        } else {
            XCTFail("Expected sponseredfailWithContent, got \(String(describing: op.result))")
        }
    }

    // MARK: - Sponsored data fixture (decoded from JSON since SponsoredData has no public init)

    private func sampleSponsoredData() -> SponsoredData {
        let json = """
        {
          "t": "Sponsored Title",
          "b": "Sponsored Body",
          "att": "https://sponsored/icon.png",
          "tag": "sponsored-tag",
          "u": "https://example.test/sponsored",
          "ab": [{"b": "sponsor-action-1"}]
        }
        """
        return try! JSONDecoder().decode(SponsoredData.self, from: Data(json.utf8))
    }
}
