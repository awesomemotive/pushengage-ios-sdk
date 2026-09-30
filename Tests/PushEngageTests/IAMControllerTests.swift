import XCTest
@testable import PushEngage

/// IAMController public/internal surface: message persistence via
/// processNewMessage(s), the enable/disable gate, trigger processing from any
/// thread, database summary, and dismissal/queue completions. The shared queue
/// manager is paused throughout so no UI presentation is attempted.
final class IAMControllerTests: XCTestCase {

    private var controller: IAMController!
    private var repository: IAMRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(IAMCoreDataManager.shared.isStoreAvailable, "IAM persistent store unavailable")
        controller = IAMController.shared
        repository = IAMRepository()
        try repository.replaceAllMessages([])
        IAMQueueStateManager.shared.clearAllStates()
        controller.enable()
        IAMQueueManager.shared.pauseQueue()
    }

    override func tearDownWithError() throws {
        let cleanup = expectation(description: "queue cleared")
        IAMQueueManager.shared.clearQueue { cleanup.fulfill() }
        wait(for: [cleanup], timeout: 5)
        controller.enable()
        IAMQueueStateManager.shared.clearAllStates()
        try? repository.replaceAllMessages([])
        try super.tearDownWithError()
    }

    private func campaign(id: String,
                          event: String? = "controller_event",
                          triggerType: String = "custom") -> IAMMessageResponse {
        IAMMessageResponse(
            id: id,
            position: .center,
            htmlContent: "<html></html>",
            displayDuration: 0,
            shouldDismissOnTap: false,
            actions: [:],
            startDate: nil,
            endDate: nil,
            priority: 1,
            audience: nil,
            frequency: nil,
            trigger: IAMTriggerCondition(type: triggerType, event: event, parameters: nil)
        )
    }

    // MARK: - Message ingestion

    func testProcessNewMessagePersistsTheCampaign() throws {
        controller.processNewMessage(campaign(id: "ctrl-1"))

        XCTAssertNotNil(try repository.fetchMessage(withId: "ctrl-1"))
    }

    func testProcessNewMessageCompletionFiresAfterPersisting() throws {
        let expectation = expectation(description: "completion")
        controller.processNewMessage(campaign(id: "ctrl-2")) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        XCTAssertNotNil(try repository.fetchMessage(withId: "ctrl-2"))
    }

    func testProcessNewMessagesPersistsTheBatchAndCallsCompletionOnce() throws {
        let expectation = expectation(description: "completion")
        controller.processNewMessages([campaign(id: "b1"),
                                       campaign(id: "b2"),
                                       campaign(id: "b3")]) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        XCTAssertEqual(try repository.fetchAllMessages().count, 3)
    }

    func testProcessNewAutoTriggerMessageIsPersistedWithoutCrashing() throws {
        let expectation = expectation(description: "completion")
        controller.processNewMessage(campaign(id: "auto-1",
                                              event: nil,
                                              triggerType: "auto")) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        XCTAssertNotNil(try repository.fetchMessage(withId: "auto-1"))
    }

    // MARK: - Enable / disable gate

    func testProcessNewMessageWhenDisabledDoesNotPersist() throws {
        controller.disable()

        controller.processNewMessage(campaign(id: "gated"))

        XCTAssertNil(try repository.fetchMessage(withId: "gated"))
        controller.enable()
        IAMQueueManager.shared.pauseQueue()
    }

    func testProcessTriggerWhenDisabledStillCallsCompletion() {
        controller.disable()

        let expectation = expectation(description: "completion")
        controller.processTrigger("anything") { expectation.fulfill() }
        wait(for: [expectation], timeout: 5)

        controller.enable()
        IAMQueueManager.shared.pauseQueue()
    }

    // MARK: - Trigger processing

    func testProcessTriggerWithNoMatchingCampaignsCallsCompletion() {
        let expectation = expectation(description: "completion")
        controller.processTrigger("no-such-event") { expectation.fulfill() }
        wait(for: [expectation], timeout: 5)
    }

    func testProcessTriggerWithAMatchingCampaignEnqueuesIt() throws {
        controller.processNewMessage(campaign(id: "trig-1", event: "sale_started"))

        let expectation = expectation(description: "completion")
        controller.processTrigger("sale_started") { expectation.fulfill() }
        wait(for: [expectation], timeout: 5)

        XCTAssertTrue(IAMQueueManager.shared.queuedMessageIds.contains("trig-1"))
    }

    func testProcessTriggerWithParametersFromABackgroundThreadEnqueuesWithoutCrashing() throws {
        let parameterised = IAMMessageResponse(
            id: "trig-2",
            position: .center,
            htmlContent: "<html></html>",
            displayDuration: 0,
            shouldDismissOnTap: false,
            actions: [:],
            startDate: nil,
            endDate: nil,
            priority: 1,
            audience: nil,
            frequency: nil,
            trigger: IAMTriggerCondition(type: "custom",
                                         event: "purchase",
                                         parameters: ["amount": "42", "vip": "true"])
        )
        controller.processNewMessage(parameterised)

        DispatchQueue.global().async { [controller] in
            controller?.processTrigger("purchase", parameters: ["amount": 42, "vip": true])
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        XCTAssertTrue(IAMQueueManager.shared.queuedMessageIds.contains("trig-2"))
    }

    func testProcessAutoTriggersWithStoredAutoCampaignDoesNotCrash() throws {
        controller.processNewMessage(campaign(id: "auto-2", event: nil, triggerType: "auto"))

        controller.processAutoTriggers()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }

    // MARK: - Database summary

    func testGetDatabaseSummaryReportsCampaignsAndUnsyncedEvents() throws {
        controller.processNewMessage(campaign(id: "summary-1"))
        try repository.recordAnalyticsEvent(type: .impression, messageId: "summary-1")

        let summary = controller.getDatabaseSummary()

        XCTAssertTrue(summary.contains("Total Campaigns: 1"))
        XCTAssertTrue(summary.contains("summary-1"))
        XCTAssertTrue(summary.contains("Unsynced Analytics Events:"))

        try repository.deleteAnalyticsEvents(repository.fetchUnsyncdAnalyticsEvents())
    }

    // MARK: - Queue passthroughs

    func testDismissCurrentMessageCompletionFiresWhenNothingIsDisplaying() {
        let expectation = expectation(description: "completion")
        controller.dismissCurrentMessage { expectation.fulfill() }
        wait(for: [expectation], timeout: 5)
    }

    func testClearQueueCompletionFires() {
        let expectation = expectation(description: "completion")
        controller.clearQueue { expectation.fulfill() }
        wait(for: [expectation], timeout: 5)
    }

    // MARK: - Bundled reference content

    func testMockMessagesAreWellFormed() {
        let messages = IAMController.mockMessages()

        XCTAssertEqual(messages.count, 5)
        XCTAssertEqual(Set(messages.map { $0.id }).count, 5)
        for message in messages {
            XCTAssertFalse(message.htmlContent.isEmpty)
            XCTAssertEqual(message.trigger.type, "custom")
        }
    }
}
