import XCTest
import CoreData
@testable import PushEngage

/// CoreData stack behaviour: background-task write visibility, error
/// propagation, entity clearing, fetch-request options, and concurrent
/// background tasks against the real SQLite store.
final class IAMCoreDataManagerTests: XCTestCase {

    private struct WorkError: Error {}

    private var manager: IAMCoreDataManager!
    private var repository: IAMRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        manager = IAMCoreDataManager.shared
        try XCTSkipUnless(manager.isStoreAvailable, "IAM persistent store unavailable")
        repository = IAMRepository()
        try purgeStore()
    }

    override func tearDownWithError() throws {
        try? purgeStore()
        repository = nil
        try super.tearDownWithError()
    }

    private func purgeStore() throws {
        try repository.replaceAllMessages([])
        let events = try repository.fetchUnsyncdAnalyticsEvents(limit: 10_000)
        try repository.deleteAnalyticsEvents(events)
    }

    func testPerformBackgroundTaskPersistsChangesVisibleToLaterFetches() throws {
        try manager.performBackgroundTask { context in
            _ = try IAMAnalyticsEvent.create(type: .impression,
                                             messageId: "bg-write",
                                             in: context)
        }

        let events = try manager.executeFetchRequest(IAMAnalyticsEvent.fetchRequest())
        XCTAssertEqual(events.map { $0.messageId }, ["bg-write"])
    }

    func testPerformBackgroundTaskPropagatesWorkErrors() {
        XCTAssertThrowsError(try manager.performBackgroundTask { _ in
            throw WorkError()
        }) { error in
            XCTAssertTrue(error is WorkError)
        }
    }

    func testPerformBackgroundTaskWithNoChangesCompletesWithoutError() {
        XCTAssertNoThrow(try manager.performBackgroundTask { _ in })
    }

    func testSaveContextWithoutChangesDoesNotThrow() throws {
        try manager.performBackgroundTask { [manager] context in
            try manager?.saveContext(context)
        }
    }

    func testClearAllRecordsWipesTheEntity() throws {
        try manager.performBackgroundTask { context in
            for index in 0..<3 {
                _ = try IAMAnalyticsEvent.create(type: .impression,
                                                 messageId: "clear-\(index)",
                                                 in: context)
            }
        }

        try manager.clearAllRecords(forEntityName: "IAMAnalyticsEvent")

        let events = try manager.executeFetchRequest(IAMAnalyticsEvent.fetchRequest())
        XCTAssertEqual(events.count, 0)
    }

    func testExecuteFetchRequestSupportsPredicatesAndLimits() throws {
        try manager.performBackgroundTask { context in
            _ = try IAMAnalyticsEvent.create(type: .impression, messageId: "match", in: context)
            _ = try IAMAnalyticsEvent.create(type: .click, messageId: "match", in: context)
            _ = try IAMAnalyticsEvent.create(type: .impression, messageId: "other", in: context)
        }

        let request = IAMAnalyticsEvent.fetchRequest()
        request.predicate = NSPredicate(format: "messageId == %@", "match")
        request.fetchLimit = 1
        XCTAssertEqual(try manager.executeFetchRequest(request).count, 1)

        request.fetchLimit = 0
        XCTAssertEqual(try manager.executeFetchRequest(request).count, 2)
    }

    func testPerformBackgroundTaskWaitsForSlowWorkToFinish() throws {
        try manager.performBackgroundTask { context in
            Thread.sleep(forTimeInterval: 5.5)
            _ = try IAMAnalyticsEvent.create(type: .impression,
                                             messageId: "slow-write",
                                             in: context)
        }

        let events = try manager.executeFetchRequest(IAMAnalyticsEvent.fetchRequest())
        XCTAssertEqual(events.map { $0.messageId }, ["slow-write"])
    }

    func testConcurrentBackgroundTasksDoNotCrashOrDeadlock() throws {
        DispatchQueue.concurrentPerform(iterations: 30) { index in
            try? manager.performBackgroundTask { context in
                _ = try IAMAnalyticsEvent.create(type: .impression,
                                                 messageId: "concurrent-\(index)",
                                                 in: context)
            }
        }

        let events = try manager.executeFetchRequest(IAMAnalyticsEvent.fetchRequest())
        XCTAssertEqual(events.count, 30)
    }
}
