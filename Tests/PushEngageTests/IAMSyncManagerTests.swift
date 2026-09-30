import XCTest
import CoreData
@testable import PushEngage

/// Sync application + decoupling tests (contract §1–§2): the App-ID gate
/// (in-app messaging must work without a push subscription), full-replace
/// persistence, iam_status purge, and the analytics payload mapping.
final class IAMSyncManagerTests: XCTestCase {

    private final class NetworkServiceFake: IAMNetworkServiceType {
        var syncResult: Result<IAMCampaignSyncResult, Error> = .success(.unchanged())
        private(set) var syncCalls: [(siteKey: String, storedVersion: String?)] = []
        /// nil means "every payload synced"; set it to pin a partial or failed batch.
        var analyticsResult: Result<IAMReportOutcome, Error>?
        private(set) var analyticsCalls: [[IAMAnalyticsPayload]] = []

        /// Holds the campaign fetch's completion instead of answering inline, so another
        /// caller can arrive while the first is still on the wire — the shape of the
        /// real app-open burst.
        var deferSyncCompletions = false
        private(set) var heldSyncCompletions: [(Result<IAMCampaignSyncResult, Error>) -> Void] = []

        func syncCampaigns(siteKey: String,
                           storedVersion: String?,
                           completion: @escaping (Result<IAMCampaignSyncResult, Error>) -> Void) {
            syncCalls.append((siteKey, storedVersion))
            if deferSyncCompletions {
                heldSyncCompletions.append(completion)
            } else {
                completion(syncResult)
            }
        }

        func releaseHeldSyncCompletions() {
            let held = heldSyncCompletions
            heldSyncCompletions.removeAll()
            held.forEach { $0(syncResult) }
        }

        /// Holds each upload's completion instead of answering inline, so a second
        /// flush can be attempted while the first is still in flight.
        var deferCompletions = false
        private(set) var heldCompletions: [(payloads: [IAMAnalyticsPayload],
                                            completion: (Result<IAMReportOutcome, Error>) -> Void)] = []

        func reportAnalytics(payloads: [IAMAnalyticsPayload],
                             completion: @escaping (Result<IAMReportOutcome, Error>) -> Void) {
            analyticsCalls.append(payloads)
            if deferCompletions {
                heldCompletions.append((payloads, completion))
            } else {
                completion(outcome(for: payloads))
            }
        }

        func releaseHeldCompletions() {
            let held = heldCompletions
            heldCompletions.removeAll()
            held.forEach { $0.completion(outcome(for: $0.payloads)) }
        }

        private func outcome(for payloads: [IAMAnalyticsPayload]) -> Result<IAMReportOutcome, Error> {
            analyticsResult ?? .success(IAMReportOutcome(syncedIndices: Array(payloads.indices),
                                                         allSynced: true))
        }
    }

    private var prefs: IAMPrefs!
    private var configuration: IAMConfiguration!
    private var network: NetworkServiceFake!
    private var repository: IAMRepository!
    private var manager: IAMSyncManager!

    private static let suiteName = "IAMSyncManagerTests"

    override func setUpWithError() throws {
        try super.setUpWithError()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        defaults.removePersistentDomain(forName: Self.suiteName)
        prefs = IAMPrefs(defaults: defaults)
        configuration = IAMConfiguration()
        configuration.siteKey = nil
        network = NetworkServiceFake()
        repository = IAMRepository()
        try repository.replaceAllMessages([])
        manager = IAMSyncManager(repository: repository,
                                 networkService: network,
                                 prefs: prefs,
                                 configuration: configuration)
        network.syncResult = .success(.unchanged())
        // Init registers the manager as a network observer, which kicks off a
        // deferred startSync on the main queue (this test's and any prior
        // test's manager — sync timers keep them alive). Drain that work now
        // so it cannot race the events seeded by the test body.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    override func tearDown() {
        try? repository.replaceAllMessages([])
        try? purgeAnalyticsEvents()
        UserDefaults(suiteName: Self.suiteName)?.removePersistentDomain(forName: Self.suiteName)
        scratchContainer = nil
        super.tearDown()
    }

    private func campaign(id: String, trigger: String = "custom") -> IAMMessageResponse {
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
            trigger: IAMTriggerCondition(type: trigger, event: "evt", parameters: nil)
        )
    }

    private func syncOnce() -> IAMSyncError? {
        var captured: IAMSyncError?
        let expectation = expectation(description: "sync")
        manager.syncMessages { error in
            captured = error
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        return captured
    }

    private func storedMessageIds() throws -> Set<String> {
        Set(try repository.fetchValidMessages().compactMap { $0.id })
    }

    // MARK: - Decoupling (App-ID gate, not push subscription)

    func testSyncIsSkippedWhenNoAppIdIsConfigured() throws {
        configuration.siteKey = nil
        let baseline = network.syncCalls.count
        XCTAssertNil(syncOnce())
        XCTAssertEqual(network.syncCalls.count, baseline, "no network call without an App ID")
    }

    func testSyncRunsWithOnlyAnAppIdConfigured() throws {
        // No subscriber/siteId/push permission involved — the App ID alone
        // must be sufficient (flow doc decoupling; Android 8ec075b).
        configuration.siteKey = "app-id-only"
        XCTAssertNil(syncOnce())
        XCTAssertEqual(network.syncCalls.last?.siteKey, "app-id-only")
    }

    func testSyncPassesTheStoredVersion() throws {
        configuration.siteKey = "k"
        prefs.iamVersion = "v-7"
        _ = syncOnce()
        XCTAssertEqual(network.syncCalls.last?.storedVersion, "v-7")
    }

    // MARK: - App-open burst coalescing

    /// Four independent callers legitimately kick a sync around one app open, and none
    /// can be removed — each covers an integration path the others do not. `isSyncing`
    /// only dedupes concurrent calls; these arrive sequentially, so a cold launch did
    /// four full metadata round trips, and on a first install four campaign downloads
    /// and four full-replaces of the whole campaign set. Android does one per open.
    func testARepeatSyncInsideTheBurstWindowDoesNotHitTheNetworkAgain() throws {
        configuration.siteKey = "k"

        XCTAssertNil(syncOnce())
        XCTAssertEqual(network.syncCalls.count, 1, "the first sync must reach the network")

        // Three more callers piling on, exactly as they do on a cold launch.
        XCTAssertNil(syncOnce())
        XCTAssertNil(syncOnce())
        XCTAssertNil(syncOnce())

        XCTAssertEqual(network.syncCalls.count, 1,
                       "a burst around one app open must collapse to a single fetch")
    }

    /// The real app-open burst is **concurrent**, not sequential: the four callers all
    /// arrive before the first fetch answers, so a "recently completed" check cannot
    /// catch them — none has completed yet. Later callers must attach to the fetch in
    /// flight. Measured on device before this: 4 metadata round trips per cold launch.
    func testConcurrentCallersShareASingleInFlightFetch() throws {
        configuration.siteKey = "k"
        network.deferSyncCompletions = true

        var answered = 0
        for _ in 0..<4 {
            manager.syncMessages { _ in answered += 1 }
        }

        XCTAssertEqual(network.syncCalls.count, 1,
                       "four overlapping callers must produce one fetch, not four")
        XCTAssertEqual(answered, 0, "nobody is answered until the fetch returns")

        network.releaseHeldSyncCompletions()

        XCTAssertEqual(answered, 4, "every caller that joined must still get an answer")
        XCTAssertEqual(network.syncCalls.count, 1)
    }

    /// The in-flight slot must be released once the fetch answers. If it stuck, a later
    /// caller would be parked on the pending list and never called back at all — which
    /// is worse than a redundant fetch, because `startSync` chains analytics and
    /// triggers off this completion.
    func testTheInFlightSlotIsReleasedSoALaterCallerIsStillAnswered() throws {
        configuration.siteKey = "k"
        network.deferSyncCompletions = true
        manager.syncMessages { _ in }
        network.releaseHeldSyncCompletions()
        XCTAssertEqual(network.syncCalls.count, 1)

        // Inside the coalescing window this is answered without a fetch — but it MUST be
        // answered, which is what distinguishes "coalesced" from "stuck in flight".
        network.deferSyncCompletions = false
        var answered = false
        manager.syncMessages { _ in answered = true }

        XCTAssertTrue(answered, "a later caller must be answered, not parked forever")
        XCTAssertEqual(network.syncCalls.count, 1, "and answered from the recent fetch")
    }

    /// The coalescing must not swallow a genuine later sync — only a burst. A failed
    /// sync never stamps a completion time, so the next caller must still try.
    func testAFailedSyncIsRetriedImmediatelyRatherThanCoalesced() throws {
        configuration.siteKey = "k"
        network.syncResult = .failure(IAMSyncError.connectionFailed)

        XCTAssertNotNil(syncOnce())
        XCTAssertEqual(network.syncCalls.count, 1)

        XCTAssertNotNil(syncOnce())
        XCTAssertEqual(network.syncCalls.count, 2,
                       "a failure must not start a coalescing window — the campaigns "
                        + "were never fetched, so the next caller has to try again")
    }

    // MARK: - Result application

    func testActiveResultFullReplacesAndPersistsVersionStatusAndAnalyticsHost() throws {
        try repository.replaceAllMessages([campaign(id: "stale")])
        configuration.siteKey = "k"
        network.syncResult = .success(IAMCampaignSyncResult(
            status: .active,
            version: "v-9",
            campaigns: [campaign(id: "fresh-1"), campaign(id: "fresh-2")],
            campaignsHost: "https://campaigns.example.com/p/v1/",
            analyticsHost: "https://analytics.example.com/p/v1/"
        ))

        XCTAssertNil(syncOnce())

        XCTAssertEqual(try storedMessageIds(), ["fresh-1", "fresh-2"])
        XCTAssertEqual(prefs.iamVersion, "v-9")
        XCTAssertEqual(prefs.iamStatus, "active")
        XCTAssertEqual(prefs.iamAnalyticsUrl, "https://analytics.example.com/p/v1/")
    }

    func testInactiveResultPurgesLocalCampaigns() throws {
        try repository.replaceAllMessages([campaign(id: "doomed")])
        configuration.siteKey = "k"
        network.syncResult = .success(.inactive())

        XCTAssertNil(syncOnce())

        XCTAssertEqual(try storedMessageIds(), [])
        XCTAssertEqual(prefs.iamStatus, "inactive")
    }

    func testUnchangedResultLeavesEverythingAlone() throws {
        try repository.replaceAllMessages([campaign(id: "keeper")])
        prefs.iamVersion = "v-1"
        configuration.siteKey = "k"
        network.syncResult = .success(.unchanged())

        XCTAssertNil(syncOnce())

        XCTAssertEqual(try storedMessageIds(), ["keeper"])
        XCTAssertEqual(prefs.iamVersion, "v-1")
    }

    func testNetworkFailureSurfacesAnError() throws {
        configuration.siteKey = "k"
        network.syncResult = .failure(IAMNetworkError.httpError(500, endpoint: "metadata"))
        XCTAssertNotNil(syncOnce())
    }

    // MARK: - Full-replace persistence (§2.2)

    func testFullReplacePreservesDisplayHistoryOfSurvivingCampaigns() throws {
        try repository.replaceAllMessages([campaign(id: "survivor"), campaign(id: "doomed")])
        let survivor = try XCTUnwrap(repository.fetchMessage(withId: "survivor"))
        try repository.recordDisplay(for: survivor)

        try repository.replaceAllMessages([campaign(id: "survivor")])

        let after = try XCTUnwrap(repository.fetchMessage(withId: "survivor"))
        let records = after.displayRecords as? Set<IAMDisplayRecord> ?? []
        XCTAssertEqual(records.count, 1, "surviving campaigns keep their frequency-capping history")
        XCTAssertNil(try repository.fetchMessage(withId: "doomed"))
    }

    // MARK: - Database summary (internal diagnostics)

    func testDatabaseSummaryListsStoredCampaigns() throws {
        try repository.replaceAllMessages([campaign(id: "summary-test")])
        let summary = IAMController.shared.getDatabaseSummary()
        XCTAssertTrue(summary.contains("Total Campaigns: 1"), "got: \(summary.prefix(200))")
        XCTAssertTrue(summary.contains("ID: summary-test"))
        XCTAssertTrue(summary.contains("Position: center"))
        XCTAssertTrue(summary.contains("Unsynced Analytics Events:"))
    }

    // MARK: - Analytics upload lifecycle (§2.3)

    private func purgeAnalyticsEvents() throws {
        let events = try repository.fetchUnsyncdAnalyticsEvents(limit: 10_000)
        try repository.deleteAnalyticsEvents(events)
    }

    private func syncAnalyticsOnce() -> IAMSyncError? {
        var captured: IAMSyncError?
        let expectation = expectation(description: "analytics sync")
        manager.syncAnalytics { error in
            captured = error
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        return captured
    }

    func testSyncAnalyticsPurgesABatchThatMapsToNoPayloads() throws {
        try purgeAnalyticsEvents()
        // Stand in for an event type this build cannot upload — the retained
        // eventType column allows one to exist.
        try repository.recordAnalyticsEvent(type: .click, messageId: "c-1")
        let stored = try XCTUnwrap(repository.fetchUnsyncdAnalyticsEvents().first)
        stored.eventType = "display_duration"
        try stored.managedObjectContext?.save()

        XCTAssertNil(syncAnalyticsOnce())

        XCTAssertTrue(network.analyticsCalls.isEmpty, "nothing uploadable in the batch")
        XCTAssertEqual(try repository.unsyncedAnalyticsEventCount(), 0,
                       "unuploadable events must not accumulate and block the sync window")
    }

    func testSyncAnalyticsUploadsEveryQueuedEventAndClearsTheBatch() throws {
        try purgeAnalyticsEvents()
        try repository.recordAnalyticsEvent(type: .impression, messageId: "c-1")
        try repository.recordAnalyticsEvent(type: .click, messageId: "c-1",
                                            btnId: "cta", btnText: "Go", btnType: "open_url")

        XCTAssertNil(syncAnalyticsOnce())

        XCTAssertEqual(network.analyticsCalls.count, 1)
        XCTAssertEqual(network.analyticsCalls.first?.count, 2,
                       "every recorded event type is uploadable now")
        XCTAssertEqual(try repository.unsyncedAnalyticsEventCount(), 0)
    }

    // MARK: - One flush at a time

    /// Drains the main queue so a `DispatchQueue.main.async` hop lands.
    private func drainMain() {
        let drained = expectation(description: "main drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5)
    }

    func testASecondFlushWhileOneIsInFlightDoesNotUploadTheBatchTwice() throws {
        // Three callers reach syncAnalytics — the analytics manager's upload handler,
        // the campaign sync, and the offline queue — and only the first is guarded by
        // the analytics manager's own flag. Rows are deleted after the upload
        // completes, so an overlapping flush reads and sends the very same batch and
        // every impression and click in it is counted twice.
        try purgeAnalyticsEvents()
        try repository.recordAnalyticsEvent(type: .impression, messageId: "c-1")
        try repository.recordAnalyticsEvent(type: .click, messageId: "c-1",
                                           btnId: "cta", btnText: "Go", btnType: "open_url")
        network.deferCompletions = true

        var firstFinished = false
        manager.syncAnalytics { _ in firstFinished = true }
        drainMain()
        XCTAssertEqual(network.analyticsCalls.count, 1, "the first flush is in flight")

        var secondFinished = false
        manager.syncAnalytics { _ in secondFinished = true }
        drainMain()
        XCTAssertEqual(network.analyticsCalls.count, 1,
                       "an overlapping flush must not re-upload the in-flight batch")
        XCTAssertTrue(secondFinished, "the overlapping caller still gets its completion")

        network.releaseHeldCompletions()
        drainMain()
        XCTAssertTrue(firstFinished)
        XCTAssertEqual(network.analyticsCalls.count, 1)
        XCTAssertEqual(try repository.unsyncedAnalyticsEventCount(), 0)
    }

    func testAFlushIsAllowedAgainOnceTheInFlightOneCompletes() throws {
        try purgeAnalyticsEvents()
        try repository.recordAnalyticsEvent(type: .impression, messageId: "c-1")
        network.deferCompletions = true

        manager.syncAnalytics { _ in }
        drainMain()
        network.releaseHeldCompletions()
        drainMain()

        // A fresh event after the first flush settled must still be uploadable — the
        // guard must not latch.
        network.deferCompletions = false
        try repository.recordAnalyticsEvent(type: .click, messageId: "c-2")
        XCTAssertNil(syncAnalyticsOnce())
        XCTAssertEqual(network.analyticsCalls.count, 2)
    }

    func testSyncAnalyticsKeepsEveryEventWhenTheUploadFails() throws {
        try purgeAnalyticsEvents()
        try repository.recordAnalyticsEvent(type: .impression, messageId: "c-1")
        try repository.recordAnalyticsEvent(type: .click, messageId: "c-1",
                                           btnId: "cta", btnText: "Go", btnType: "open_url")
        network.analyticsResult = .failure(IAMNetworkError.httpError(500, endpoint: "analytics"))

        XCTAssertNotNil(syncAnalyticsOnce())

        XCTAssertEqual(try repository.unsyncedAnalyticsEventCount(), 2,
                       "a failed batch stays queued for the next flush")
    }

    func testSyncAnalyticsClearsOnlyTheEventsTheBackendAccountedFor() throws {
        try purgeAnalyticsEvents()
        try repository.recordAnalyticsEvent(type: .impression, messageId: "c-1")
        try repository.recordAnalyticsEvent(type: .click, messageId: "c-1",
                                           btnId: "cta", btnText: "Go", btnType: "open_url")
        try repository.recordAnalyticsEvent(type: .impression, messageId: "c-2")
        network.analyticsResult = .success(IAMReportOutcome(
            syncedIndices: [0],
            allSynced: false,
            failure: IAMNetworkError.httpError(503, endpoint: "analytics")))

        XCTAssertNotNil(syncAnalyticsOnce(), "a partly settled batch is still a failed sync")

        XCTAssertEqual(try repository.unsyncedAnalyticsEventCount(), 2,
                       "the delivered event is cleared so a retry cannot re-POST it")
    }

    func testSyncAnalyticsWithNoEventsSucceedsWithoutUploading() throws {
        try purgeAnalyticsEvents()

        XCTAssertNil(syncAnalyticsOnce())

        XCTAssertTrue(network.analyticsCalls.isEmpty)
    }

    // MARK: - Analytics payload mapping (§2.3)

    func testAnalyticsPayloadsMapImpressionsAndClicksOnly() throws {
        let model = try XCTUnwrap(IAMCoreDataManager.managedObjectModel)
        let container = NSPersistentContainer(name: "InAppMessaging", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        let storeExpectation = expectation(description: "store")
        container.loadPersistentStores { _, error in
            XCTAssertNil(error)
            storeExpectation.fulfill()
        }
        wait(for: [storeExpectation], timeout: 5)
        let ctx = container.viewContext

        let impression = try IAMAnalyticsEvent.create(type: .impression, messageId: "c-1", in: ctx)
        let click = try IAMAnalyticsEvent.create(type: .click, messageId: "c-1",
                                                 btnId: "ok", btnText: "OK", btnType: "custom",
                                                 in: ctx)

        let payloads = manager.analyticsPayloads(from: [impression, click])

        XCTAssertEqual(payloads.count, 2)
        XCTAssertEqual(payloads[0], IAMAnalyticsPayload(campaignId: "c-1", impression: 1, click: 0))
        XCTAssertEqual(payloads[1], IAMAnalyticsPayload(campaignId: "c-1", impression: 0, click: 1,
                                                        btnId: "ok", btnText: "OK", btnType: "custom"))
    }

    func testAnUnknownStoredEventTypeIsDroppedRatherThanInventedOntoTheWire() throws {
        let model = try XCTUnwrap(IAMCoreDataManager.managedObjectModel)
        let container = NSPersistentContainer(name: "InAppMessaging", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        let storeExpectation = expectation(description: "store")
        container.loadPersistentStores { _, error in
            XCTAssertNil(error)
            storeExpectation.fulfill()
        }
        wait(for: [storeExpectation], timeout: 5)

        // The eventType column is retained precisely so a future type needs no
        // migration; one this build does not know must not become a bogus payload.
        let unknown = try IAMAnalyticsEvent.create(type: .click, messageId: "c-2",
                                                   in: container.viewContext)
        unknown.eventType = "display_duration"

        XCTAssertTrue(manager.analyticsPayloads(from: [unknown]).isEmpty)
    }

    /// Retained for the duration of a test: releasing the container invalidates the
    /// objects created in its context, and reading them then traps.
    private var scratchContainer: NSPersistentContainer?

    /// An in-memory context for building analytics events directly.
    private func scratchContext() throws -> NSManagedObjectContext {
        let model = try XCTUnwrap(IAMCoreDataManager.managedObjectModel)
        let container = NSPersistentContainer(name: "InAppMessaging", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        let storeExpectation = expectation(description: "store")
        container.loadPersistentStores { _, error in
            XCTAssertNil(error)
            storeExpectation.fulfill()
        }
        wait(for: [storeExpectation], timeout: 5)
        scratchContainer = container
        return container.viewContext
    }

    func testClickPayloadCarriesTheButtonFieldsRecordedAtTapTime() throws {
        let click = try IAMAnalyticsEvent.create(type: .click, messageId: "c-btn",
                                                 btnId: "cta",
                                                 btnText: "Maybe Later",
                                                 btnType: "open_url",
                                                 in: try scratchContext())

        let payloads = manager.analyticsPayloads(from: [click])

        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads[0].btnId, "cta")
        XCTAssertEqual(payloads[0].btnText, "Maybe Later")
        // C10: lowercase, matching the inbound actions[].type vocabulary.
        XCTAssertEqual(payloads[0].btnType, "open_url")
    }

    func testAClickStillUploadsAfterItsCampaignHasBeenReplacedBySync() throws {
        // btn_* used to be re-resolved from the stored campaign, so a click that
        // outlived its campaign uploaded with no button payload at all. A sync
        // full-replaces the campaign set, so this is an ordinary occurrence.
        let click = try IAMAnalyticsEvent.create(type: .click, messageId: "long-gone",
                                                 btnId: "cta",
                                                 btnText: "Go",
                                                 btnType: "open_url",
                                                 in: try scratchContext())
        try repository.replaceAllMessages([])

        let payloads = manager.analyticsPayloads(from: [click])

        XCTAssertEqual(payloads[0].btnId, "cta")
        XCTAssertEqual(payloads[0].btnText, "Go")
        XCTAssertEqual(payloads[0].btnType, "open_url")
    }

    func testDismissClicksReportTheLowercaseTypeTheBackendRoutesToCloses() throws {
        // The backend splits click vs close on btn_type, so an uppercased value made
        // every dismiss tap increment `click` instead of `close`.
        let click = try IAMAnalyticsEvent.create(type: .click, messageId: "c-dismiss",
                                                 btnId: "close",
                                                 btnText: "Not Now",
                                                 btnType: "dismiss",
                                                 in: try scratchContext())

        let payloads = manager.analyticsPayloads(from: [click])

        XCTAssertEqual(payloads[0].btnType, "dismiss")
    }

    func testEveryActionTypeReportsItsWireValueVerbatim() {
        // Guards against a stringification that leaks the Swift case name: the
        // reported value must be exactly the wire value in both directions.
        for type in [IAMActionType.openURL, .requestNotificationPermission, .dismiss, .custom] {
            XCTAssertEqual(type.rawValue, type.rawValue.lowercased(),
                           "\(type) must have a lowercase wire value")
        }
        XCTAssertEqual(IAMActionType.openURL.rawValue, "open_url")
        XCTAssertEqual(IAMActionType.requestNotificationPermission.rawValue,
                       "request_notification_permission")
        XCTAssertEqual(IAMActionType.dismiss.rawValue, "dismiss")
        XCTAssertEqual(IAMActionType.custom.rawValue, "custom")
    }
}
