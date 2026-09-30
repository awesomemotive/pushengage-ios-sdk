import XCTest
import CoreData
@testable import PushEngage

/// Crash-safety and liveness tests for the message queue manager: every public
/// entry point must be callable from any thread, tolerate an empty/idle queue,
/// and completion variants must always call back. The queue is paused so
/// enqueued messages are never presented.
final class IAMQueueManagerTests: XCTestCase {

    private var queueManager: IAMQueueManager!
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        queueManager = IAMQueueManager.shared
        queueManager.pauseQueue()
        let cleared = expectation(description: "queue cleared")
        queueManager.clearQueue { cleared.fulfill() }
        wait(for: [cleared], timeout: 5)

        let model = try XCTUnwrap(IAMCoreDataManager.managedObjectModel)
        container = NSPersistentContainer(name: "InAppMessaging", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        let loaded = expectation(description: "store loaded")
        container.loadPersistentStores { _, error in
            XCTAssertNil(error)
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 5)
        context = container.viewContext
    }

    override func tearDown() {
        let cleared = expectation(description: "queue cleared")
        queueManager.clearQueue { cleared.fulfill() }
        wait(for: [cleared], timeout: 5)
        queueManager.resumeQueue()
        queueManager.pauseQueue()
        container = nil
        context = nil
        super.tearDown()
    }

    override class func tearDown() {
        IAMQueueManager.shared.resumeQueue()
        super.tearDown()
    }

    private func makeMessage(id: String, priority: Int16 = 1) throws -> IAMMessage {
        let response = IAMMessageResponse(
            id: id,
            position: .center,
            htmlContent: "<html></html>",
            displayDuration: 0,
            shouldDismissOnTap: false,
            actions: [:],
            startDate: nil,
            endDate: nil,
            priority: priority,
            audience: nil,
            frequency: nil,
            trigger: IAMTriggerCondition(type: "custom", event: "evt", parameters: nil)
        )
        let message = try IAMMessage.create(from: response, in: context)
        try context.save()
        return message
    }

    // MARK: - Completion liveness

    func testAddMessagesCompletionFires() throws {
        let messages = [try makeMessage(id: "q1"), try makeMessage(id: "q2")]

        let expectation = expectation(description: "completion")
        queueManager.addMessages(messages) { expectation.fulfill() }
        wait(for: [expectation], timeout: 5)
    }

    func testClearQueueCompletionFires() {
        let expectation = expectation(description: "completion")
        queueManager.clearQueue { expectation.fulfill() }
        wait(for: [expectation], timeout: 5)
    }

    func testPauseAndResumeCompletionsFire() {
        let paused = expectation(description: "paused")
        queueManager.pauseQueue { paused.fulfill() }
        wait(for: [paused], timeout: 5)

        let resumed = expectation(description: "resumed")
        queueManager.resumeQueue { resumed.fulfill() }
        wait(for: [resumed], timeout: 5)

        queueManager.pauseQueue()
    }

    func testDismissActiveMessageWithNothingActiveCallsCompletion() {
        let expectation = expectation(description: "completion")
        queueManager.dismissActiveMessage { expectation.fulfill() }
        wait(for: [expectation], timeout: 5)
    }

    // MARK: - Idle-state resilience

    func testDelegateCallbacksWithNoActiveMessageDoNotCrash() {
        queueManager.messageDidDismiss()
        queueManager.handleCustomAction(actionId: "any", parameters: ["k": "v"])
    }

    func testRemoveMessageForAnUnknownIdDoesNotCrash() {
        queueManager.removeMessage(withId: "ghost")
    }

    func testDismissActiveMessageWithNothingActiveFromABackgroundThreadDoesNotCrash() {
        DispatchQueue.global().sync { [queueManager] in
            queueManager?.dismissActiveMessage()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }

    // MARK: - Queue behaviour (observable via queuedMessageIds)

    private var hasTopViewController: Bool {
        if #available(iOS 13.0, *) {
            return UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive })
                .flatMap { $0 as? UIWindowScene }
                .flatMap { $0.windows.first(where: { $0.isKeyWindow }) }?
                .rootViewController != nil
        }
        return UIApplication.shared.keyWindow?.rootViewController != nil
    }

    // MARK: - Invalidated objects

    func testADeletedMessageIsRefusedRatherThanQueuedAsAPhantom() throws {
        // A campaign row can be deleted while something still holds the object — a
        // sync full-replaces the set. The non-optional `id` then reads back as "",
        // so the entry cannot be deduped, removed by id, or attributed.
        let message = try makeMessage(id: "deleted")
        context.delete(message)
        try context.save()

        queueManager.addMessage(message)

        XCTAssertTrue(queueManager.queuedMessageIds.isEmpty)
    }

    func testAMessageWithNoContextIsRefused() throws {
        let message = try makeMessage(id: "detached")
        context.delete(message)
        try context.save()
        context.reset()

        queueManager.addMessage(message)

        XCTAssertTrue(queueManager.queuedMessageIds.isEmpty)
    }

    func testQueueOrdersMessagesByPriority() throws {
        let low = try makeMessage(id: "low", priority: 9)
        let high = try makeMessage(id: "high", priority: 1)
        let mid = try makeMessage(id: "mid", priority: 5)

        queueManager.addMessages([low, high, mid])

        XCTAssertEqual(queueManager.queuedMessageIds, ["high", "mid", "low"])
    }

    func testDuplicateAddsKeepASingleQueueEntry() throws {
        let message = try makeMessage(id: "unique")

        queueManager.addMessage(message)
        queueManager.addMessage(message)
        queueManager.addMessages([message, message])

        XCTAssertEqual(queueManager.queuedMessageIds.filter { $0 == "unique" }, ["unique"])
    }

    func testSelectorAddGoesThroughTheDedupePipeline() throws {
        let message = try makeMessage(id: "sel-1")

        queueManager.addMessageFromSelector(message)
        queueManager.addMessageFromSelector(message)

        XCTAssertEqual(queueManager.queuedMessageIds.filter { $0 == "sel-1" }, ["sel-1"])
    }

    func testQueueOverflowKeepsTheHigherPriorityMessage() throws {
        for index in 0..<10 {
            queueManager.addMessage(try makeMessage(id: "bulk-\(index)", priority: 5))
        }

        queueManager.addMessage(try makeMessage(id: "vip", priority: 1))
        XCTAssertEqual(queueManager.queuedMessageIds.count, 10)
        XCTAssertEqual(queueManager.queuedMessageIds.first, "vip")

        queueManager.addMessage(try makeMessage(id: "loser", priority: 9))
        XCTAssertFalse(queueManager.queuedMessageIds.contains("loser"))
    }

    /// The overflow branch used to run before the dedupe guard, so re-adding an id that
    /// was already queued evicted a *different* campaign to make room for a duplicate.
    func testReEnqueuingAQueuedIdOnAFullQueueEvictsNothing() throws {
        for index in 0..<10 {
            queueManager.addMessage(try makeMessage(id: "bulk-\(index)", priority: 5))
        }
        let before = queueManager.queuedMessageIds
        XCTAssertEqual(before.count, 10, "precondition: the queue is full")

        // Same id as one already queued, at a better priority than the queue's worst —
        // the combination that reached handleQueueOverflow before the dedupe check.
        queueManager.addMessage(try makeMessage(id: "bulk-3", priority: 1))

        XCTAssertEqual(queueManager.queuedMessageIds, before,
                       "a duplicate id must be dropped, not evict another campaign")
        XCTAssertEqual(queueManager.queuedMessageIds.filter { $0 == "bulk-3" }.count, 1)
    }

    func testRemoveMessageFromABackgroundThreadRemovesTheMessage() throws {
        let message = try makeMessage(id: "bg-remove")
        queueManager.addMessage(message)

        DispatchQueue.global().sync { [queueManager] in
            queueManager?.removeMessage(withId: "bg-remove")
        }

        let settled = expectation(description: "main queue settled")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 5)

        XCTAssertFalse(queueManager.queuedMessageIds.contains("bg-remove"))
    }

    func testMessageIsRequeuedWhenNoTopViewControllerIsAvailable() throws {
        try XCTSkipIf(hasTopViewController, "test host can present UI — drop path not reachable")

        queueManager.resumeQueue()
        let message = try makeMessage(id: "requeue-1")
        queueManager.addMessage(message)
        queueManager.pauseQueue()

        XCTAssertTrue(queueManager.queuedMessageIds.contains("requeue-1"),
                      "a message that could not be presented must not be lost")
    }

    // MARK: - Thread-safety hammer

    func testConcurrentQueueOperationsFromManyThreadsDoNotCrash() throws {
        var messages: [IAMMessage] = []
        for index in 0..<15 {
            messages.append(try makeMessage(id: "hammer-\(index)", priority: Int16(index % 5)))
        }

        DispatchQueue.concurrentPerform(iterations: 15) { [queueManager] index in
            let message = messages[index]
            queueManager?.addMessage(message)
            queueManager?.addMessages([message])
            DispatchQueue.main.async {
                queueManager?.removeMessage(withId: "hammer-\(index)")
            }
            queueManager?.pauseQueue()
        }

        let settled = expectation(description: "main queue settled")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 5)

        let cleared = expectation(description: "queue cleared")
        queueManager.clearQueue { cleared.fulfill() }
        wait(for: [cleared], timeout: 5)
    }

    func testQueueOverflowBeyondCapacityDoesNotCrash() throws {
        var messages: [IAMMessage] = []
        for index in 0..<14 {
            messages.append(try makeMessage(id: "overflow-\(index)",
                                            priority: Int16(index)))
        }

        queueManager.addMessages(messages)

        let settled = expectation(description: "settled")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 5)
    }
}
