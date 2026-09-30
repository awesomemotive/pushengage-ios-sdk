import XCTest
@testable import PushEngage

/// Offline sync queue: priority ordering, same-type deduplication, and
/// UserDefaults persistence, plus the IAMSyncOperation wire round-trip.
/// The shared queue is paused for the duration of each test so operations
/// stay observable instead of being processed.
final class IAMOfflineQueueTests: XCTestCase {

    private var queue: IAMOfflineQueue!

    override func setUp() {
        super.setUp()
        queue = IAMOfflineQueue.shared
        queue.pauseQueue()
        queue.clearQueue()
    }

    override func tearDown() {
        queue.clearQueue()
        queue.resumeQueue()
        super.tearDown()
    }

    // MARK: - Ordering and deduplication

    func testOperationsDequeueInPriorityOrder() {
        queue.enqueueOperation(IAMSyncOperation(type: .syncTriggers, priority: 2))
        queue.enqueueOperation(IAMSyncOperation(type: .fetchMessages, priority: 0))
        queue.enqueueOperation(IAMSyncOperation(type: .uploadAnalytics, priority: 1))

        XCTAssertEqual(queue.dequeueNextOperation()?.type, .fetchMessages)
        XCTAssertEqual(queue.dequeueNextOperation()?.type, .uploadAnalytics)
        XCTAssertEqual(queue.dequeueNextOperation()?.type, .syncTriggers)
    }

    func testEnqueueReplacesAnExistingOperationOfTheSameType() {
        queue.enqueueOperation(IAMSyncOperation(type: .fetchMessages,
                                                priority: 0,
                                                parameters: ["v": "old"]))
        queue.enqueueOperation(IAMSyncOperation(type: .fetchMessages,
                                                priority: 0,
                                                parameters: ["v": "new"]))

        let first = queue.dequeueNextOperation()
        XCTAssertEqual(first?.parameters?["v"], "new")
        XCTAssertNil(queue.dequeueNextOperation())
    }

    /// A same-type replace used to take the incoming operation wholesale, so a fresh
    /// enqueue (retryCount 0) arriving between retries reset the counter and `maxRetries`
    /// stopped bounding anything.
    func testReplacingAnOperationKeepsTheHigherRetryCount() {
        var retried = IAMSyncOperation(type: .uploadAnalytics, priority: 1)
        retried.retryCount = 2
        queue.enqueueOperation(retried)

        queue.enqueueOperation(IAMSyncOperation(type: .uploadAnalytics, priority: 1))

        XCTAssertEqual(queue.dequeueNextOperation()?.retryCount, 2,
                       "a fresh enqueue must not reset the retry budget")
    }

    /// The reverse direction: a retry arriving over a fresh entry must still win.
    func testReplacingAnOperationTakesTheIncomingHigherRetryCount() {
        queue.enqueueOperation(IAMSyncOperation(type: .fetchMessages, priority: 0))

        var retried = IAMSyncOperation(type: .fetchMessages, priority: 0)
        retried.retryCount = 1
        queue.enqueueOperation(retried)

        XCTAssertEqual(queue.dequeueNextOperation()?.retryCount, 1)
    }

    func testDequeueOnAnEmptyQueueReturnsNil() {
        XCTAssertNil(queue.dequeueNextOperation())
    }

    // MARK: - Persistence

    func testEnqueuePersistsOperationsToUserDefaults() throws {
        queue.enqueueOperation(IAMSyncOperation(type: .uploadAnalytics, priority: 1))

        let data = try XCTUnwrap(
            UserDefaults.standard.data(forKey: "com.pushengage.iam.offlineQueue")
        )
        let stored = try JSONDecoder().decode([IAMSyncOperation].self, from: data)
        XCTAssertEqual(stored.map { $0.type }, [.uploadAnalytics])
    }

    func testClearQueuePersistsTheEmptyQueue() throws {
        queue.enqueueOperation(IAMSyncOperation(type: .fetchMessages))

        queue.clearQueue()

        let data = try XCTUnwrap(
            UserDefaults.standard.data(forKey: "com.pushengage.iam.offlineQueue")
        )
        let stored = try JSONDecoder().decode([IAMSyncOperation].self, from: data)
        XCTAssertTrue(stored.isEmpty)
        XCTAssertNil(queue.dequeueNextOperation())
    }

    // MARK: - Concurrency

    /// `operations` and `isProcessing` are reached from the main thread (the reachability
    /// listener and the enqueue paths) and from a URLSession completion thread (the
    /// `processQueue` continuation). Unsynchronized, two threads mutating the same Swift
    /// Array is undefined behaviour — a crash, or a silently dropped/duplicated operation.
    func testConcurrentEnqueueAndDequeueKeepsTheQueueValid() {
        let types: [IAMSyncOperation.OperationType] = [.fetchMessages, .uploadAnalytics, .syncTriggers]

        DispatchQueue.concurrentPerform(iterations: 300) { iteration in
            let type = types[iteration % types.count]
            self.queue.enqueueOperation(IAMSyncOperation(type: type, priority: iteration % 3))
            _ = self.queue.dequeueNextOperation()
        }

        // Same-type entries replace rather than accumulate, so a queue that survived
        // intact holds at most one operation per type.
        var drained = 0
        while queue.dequeueNextOperation() != nil {
            drained += 1
        }
        XCTAssertLessThanOrEqual(drained, types.count,
                                 "queue holds more entries than there are operation types — "
                                  + "the dedup invariant was lost to a race")
    }

    // MARK: - IAMSyncOperation wire format

    func testSyncOperationCodableRoundTrip() throws {
        var operation = IAMSyncOperation(type: .fetchMessages,
                                         priority: 3,
                                         parameters: ["key": "value"])
        operation.retryCount = 2

        let data = try JSONEncoder().encode(operation)
        let decoded = try JSONDecoder().decode(IAMSyncOperation.self, from: data)

        XCTAssertEqual(decoded.type, .fetchMessages)
        XCTAssertEqual(decoded.priority, 3)
        XCTAssertEqual(decoded.parameters?["key"], "value")
        XCTAssertEqual(decoded.retryCount, 2)
        XCTAssertEqual(decoded.timestamp.timeIntervalSinceReferenceDate,
                       operation.timestamp.timeIntervalSinceReferenceDate,
                       accuracy: 0.001)
    }

    func testSyncOperationDefaultsToZeroRetriesAndNilParameters() {
        let operation = IAMSyncOperation(type: .syncTriggers)
        XCTAssertEqual(operation.retryCount, 0)
        XCTAssertEqual(operation.priority, 0)
        XCTAssertNil(operation.parameters)
    }
}
