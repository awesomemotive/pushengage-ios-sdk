import XCTest
import CoreData
@testable import PushEngage

/// CRUD and persistence-integrity tests for the IAM CoreData layer:
/// upsert semantics, full-replace, display-record accumulation and lifetime
/// frequency-cap history, expiry cleanup, analytics event lifecycle, and
/// concurrent-write safety against the real SQLite store.
final class IAMRepositoryTests: XCTestCase {

    private var repository: IAMRepository!
    private var coreData: IAMCoreDataManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        coreData = IAMCoreDataManager.shared
        try XCTSkipUnless(coreData.isStoreAvailable, "IAM persistent store unavailable")
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
        // Display records are Nullify now, so a full-replace deliberately leaves them
        // behind. Tests must clear them explicitly or they leak between cases.
        try coreData.performBackgroundTask { context in
            for record in try context.fetch(IAMDisplayRecord.fetchRequest()) {
                context.delete(record)
            }
        }
    }

    // MARK: - Builders

    private func campaign(id: String,
                          event: String? = "test_event",
                          triggerType: String = "custom",
                          priority: Int16 = 1,
                          startDate: Date? = nil,
                          endDate: Date? = nil,
                          frequency: IAMFrequency? = nil,
                          html: String = "<html></html>") -> IAMMessageResponse {
        IAMMessageResponse(
            id: id,
            position: .center,
            htmlContent: html,
            displayDuration: 0,
            shouldDismissOnTap: false,
            actions: [:],
            startDate: startDate,
            endDate: endDate,
            priority: priority,
            audience: nil,
            frequency: frequency,
            trigger: IAMTriggerCondition(type: triggerType, event: event, parameters: nil)
        )
    }

    private func displayRecordCount() throws -> Int {
        try coreData.executeFetchRequest(IAMDisplayRecord.fetchRequest()).count
    }

    /// Background-context saves merge into the view context asynchronously on
    /// the main run loop, so a previously materialised object can serve stale
    /// values for a tick. Spins the run loop until the merge lands.
    private func waitForMergedValue(timeout: TimeInterval = 2,
                                    condition: () throws -> Bool) rethrows {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    // MARK: - Save / upsert

    func testSaveMessagePersistsTheCampaign() throws {
        try repository.saveMessage(campaign(id: "c1"))

        let stored = try XCTUnwrap(repository.fetchMessage(withId: "c1"))
        XCTAssertEqual(stored.id, "c1")
        XCTAssertEqual(stored.position, "center")
        XCTAssertEqual(stored.htmlContent, "<html></html>")
        XCTAssertEqual(stored.decodedTrigger?.event, "test_event")
    }

    func testSaveMessageWithSameIdUpdatesInPlaceWithoutDuplicating() throws {
        try repository.saveMessage(campaign(id: "c1", priority: 1, html: "<p>old</p>"))
        try repository.saveMessage(campaign(id: "c1", priority: 5, html: "<p>new</p>"))

        let all = try repository.fetchAllMessages()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.priority, 5)
        XCTAssertEqual(all.first?.htmlContent, "<p>new</p>")
    }

    func testSaveMessageUpsertPreservesDisplayHistory() throws {
        try repository.saveMessage(campaign(id: "c1"))
        let stored = try XCTUnwrap(repository.fetchMessage(withId: "c1"))
        try repository.recordDisplay(for: stored)

        try repository.saveMessage(campaign(id: "c1", html: "<p>updated</p>"))

        try waitForMergedValue {
            try repository.fetchMessage(withId: "c1")?.htmlContent == "<p>updated</p>"
        }
        let updated = try XCTUnwrap(repository.fetchMessage(withId: "c1"))
        XCTAssertEqual(updated.htmlContent, "<p>updated</p>")
        XCTAssertEqual((updated.displayRecords as? Set<IAMDisplayRecord>)?.count, 1)
    }

    /// Frequency caps are read from the `displayRecords` relationship, and the record is
    /// written on a background context that merges into the view context
    /// asynchronously. Every other test here waits for that merge — production does not:
    /// the next trigger can arrive well inside the window. If the cap reads a stale
    /// relationship it over-admits, and a `one_time` campaign shows twice.
    func testAOneTimeCampaignIsNotDisplayableImmediatelyAfterRecordingItsDisplay() throws {
        try repository.saveMessage(campaign(id: "c1", frequency: IAMFrequency(type: .oneTime)))
        let stored = try XCTUnwrap(repository.fetchMessage(withId: "c1"))
        XCTAssertTrue(stored.canDisplay(), "precondition: unshown one_time campaign is displayable")

        try repository.recordDisplay(for: stored)

        // Deliberately no waitForMergedValue — this is the production timing.
        XCTAssertFalse(try XCTUnwrap(repository.fetchMessage(withId: "c1")).canDisplay(),
                       "a one_time campaign must stop being displayable the moment its "
                        + "display is recorded, not once the context merge lands")
    }

    func testUpsertClearsAFrequencyRuleTheResponseNoLongerCarries() throws {
        // The upsert updates in place to keep display history, so an omitted
        // `frequency` must clear the stored rule. Otherwise a campaign whose cap was
        // removed in the dashboard stays capped on this device for good.
        try repository.saveMessage(campaign(id: "c1", frequency: IAMFrequency(type: .oneTime)))
        try waitForMergedValue { try repository.fetchMessage(withId: "c1")?.frequency != nil }
        XCTAssertNotNil(try XCTUnwrap(repository.fetchMessage(withId: "c1")).frequency)

        try repository.saveMessage(campaign(id: "c1", frequency: nil))

        try waitForMergedValue { try repository.fetchMessage(withId: "c1")?.frequency == nil }
        let updated = try XCTUnwrap(repository.fetchMessage(withId: "c1"))
        XCTAssertNil(updated.frequency, "a removed frequency rule must not survive the upsert")
    }

    func testUpsertClearingFrequencyMakesAOneTimeCampaignDisplayableAgain() throws {
        try repository.saveMessage(campaign(id: "c1", frequency: IAMFrequency(type: .oneTime)))
        let stored = try XCTUnwrap(repository.fetchMessage(withId: "c1"))
        try repository.recordDisplay(for: stored)
        try waitForMergedValue { try repository.fetchMessage(withId: "c1")?.canDisplay() == false }
        XCTAssertFalse(try XCTUnwrap(repository.fetchMessage(withId: "c1")).canDisplay())

        try repository.saveMessage(campaign(id: "c1", frequency: nil))

        try waitForMergedValue { try repository.fetchMessage(withId: "c1")?.canDisplay() == true }
        XCTAssertTrue(try XCTUnwrap(repository.fetchMessage(withId: "c1")).canDisplay(),
                      "an uncapped campaign must be displayable again once its rule is gone")
    }

    func testTriggerDelayAndConditionsSurviveTheRealPersistPath() throws {
        // Not a hand-rolled re-encode: this goes through `IAMMessage.create`, the
        // path that dropped `delay` on the way into the store because the model did
        // not carry the field. Reading the stored bytes back is what proves it.
        let conditions = try IAMRawJSON(data: Data("""
        [{"field":"cart_value","type":"number","op":"gte","value":["100"]}]
        """.utf8))
        try repository.saveMessage(IAMMessageResponse(
            id: "persisted-trigger",
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
                                         event: "checkout",
                                         match: "all",
                                         conditions: conditions,
                                         delay: 8)
        ))

        let stored = try XCTUnwrap(repository.fetchMessage(withId: "persisted-trigger"))
        let triggerJSON = try XCTUnwrap(stored.trigger)
        let tree = try XCTUnwrap(JSONSerialization.jsonObject(with: triggerJSON) as? [String: Any])

        XCTAssertEqual(tree["delay"] as? Double, 8, "delay must reach the stored trigger JSON")
        XCTAssertEqual(tree["match"] as? String, "all")
        let storedConditions = try XCTUnwrap(tree["conditions"] as? [[String: Any]])
        XCTAssertEqual(storedConditions.first?["field"] as? String, "cart_value")
        XCTAssertEqual(storedConditions.first?["op"] as? String, "gte")
        // And the decoded view agrees, so the matcher sees the same thing.
        XCTAssertEqual(stored.decodedTrigger?.delay, 8)
        XCTAssertNotNil(stored.decodedTrigger?.conditions)
    }

    func testAnAbsentTriggerDelayStaysAbsentRatherThanBecomingZero() throws {
        try repository.saveMessage(campaign(id: "no-delay"))

        let stored = try XCTUnwrap(repository.fetchMessage(withId: "no-delay"))
        let tree = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(stored.trigger)) as? [String: Any]
        )
        XCTAssertNil(tree["delay"], "absent must stay absent — 0 is a different instruction")
    }

    func testSaveMessagesPersistsTheWholeBatch() throws {
        try repository.saveMessages([campaign(id: "c1"), campaign(id: "c2"), campaign(id: "c3")])
        XCTAssertEqual(try repository.fetchAllMessages().count, 3)
    }

    func testSaveMessagesWithEmptyArrayIsANoOp() throws {
        XCTAssertNoThrow(try repository.saveMessages([]))
        XCTAssertEqual(try repository.fetchAllMessages().count, 0)
    }

    // MARK: - Full replace (backend contract §2.2)

    func testReplaceAllMessagesDeletesCampaignsAbsentFromTheNewSet() throws {
        try repository.saveMessages([campaign(id: "keep"), campaign(id: "drop")])

        try repository.replaceAllMessages([campaign(id: "keep"), campaign(id: "new")])

        let ids = Set(try repository.fetchAllMessages().map { $0.id })
        XCTAssertEqual(ids, ["keep", "new"])
    }

    func testReplaceAllMessagesWithEmptyListPurgesEverything() throws {
        try repository.saveMessages([campaign(id: "c1"), campaign(id: "c2")])

        try repository.replaceAllMessages([])

        XCTAssertEqual(try repository.fetchAllMessages().count, 0)
    }

    /// Previously asserted the opposite: the relationship was Cascade, so a full-replace
    /// took the display history with the campaign. That is the defect — frequency caps are
    /// lifetime, and a campaign the server stops sending for one sync cycle must not come
    /// back with a clean slate. The records now outlive the campaign row.
    func testReplaceAllMessagesKeepsDisplayRecordsOfDroppedCampaigns() throws {
        try repository.saveMessage(campaign(id: "c1"))
        let stored = try XCTUnwrap(repository.fetchMessage(withId: "c1"))
        try repository.recordDisplay(for: stored)
        XCTAssertEqual(try displayRecordCount(), 1)

        try repository.replaceAllMessages([])

        XCTAssertNil(try repository.fetchMessage(withId: "c1"), "the campaign row is gone")
        XCTAssertEqual(try displayRecordCount(), 1,
                       "its display history is not, so the cap survives the round trip")
    }

    // MARK: - Fetching

    func testFetchAllMessagesIsSortedByPriorityAndIncludesExpired() throws {
        let expired = campaign(id: "expired", priority: 2,
                               endDate: Date().addingTimeInterval(-3600))
        try repository.saveMessages([campaign(id: "low", priority: 9),
                                     expired,
                                     campaign(id: "high", priority: 1)])

        let all = try repository.fetchAllMessages()
        XCTAssertEqual(all.map { $0.id }, ["high", "expired", "low"])
    }

    func testFetchValidMessagesExcludesExpiredAndNotYetStarted() throws {
        try repository.saveMessages([
            campaign(id: "valid"),
            campaign(id: "expired", endDate: Date().addingTimeInterval(-60)),
            campaign(id: "future", startDate: Date().addingTimeInterval(3600))
        ])

        let valid = try repository.fetchValidMessages()
        XCTAssertEqual(valid.map { $0.id }, ["valid"])
    }

    func testFetchValidMessagesIncludesOpenEndedCampaigns() throws {
        try repository.saveMessage(campaign(id: "open", startDate: nil, endDate: nil))
        XCTAssertEqual(try repository.fetchValidMessages().count, 1)
    }

    func testFetchMessagesForTriggerMatchesOnlyThatEvent() throws {
        try repository.saveMessages([campaign(id: "a", event: "purchase"),
                                     campaign(id: "b", event: "purchase"),
                                     campaign(id: "c", event: "signup")])

        let matches = try repository.fetchMessages(forTrigger: "purchase")
        XCTAssertEqual(Set(matches.map { $0.id }), ["a", "b"])
    }

    func testFetchMessagesForTriggerSkipsCampaignsWithCorruptTriggerData() throws {
        try repository.saveMessage(campaign(id: "corrupt", event: "purchase"))
        let stored = try XCTUnwrap(repository.fetchMessage(withId: "corrupt"))
        stored.trigger = Data("not json".utf8)
        try stored.managedObjectContext?.save()

        XCTAssertEqual(try repository.fetchMessages(forTrigger: "purchase").count, 0)
    }

    func testFetchMessageWithUnknownIdReturnsNil() throws {
        XCTAssertNil(try repository.fetchMessage(withId: "does-not-exist"))
    }

    // MARK: - Display records / frequency capping state

    func testRecordDisplayAppendsARecordEachTime() throws {
        try repository.saveMessage(campaign(id: "c1"))
        let stored = try XCTUnwrap(repository.fetchMessage(withId: "c1"))

        try repository.recordDisplay(for: stored)
        try repository.recordDisplay(for: stored)

        let refetched = try XCTUnwrap(repository.fetchMessage(withId: "c1"))
        XCTAssertEqual((refetched.displayRecords as? Set<IAMDisplayRecord>)?.count, 2)
        XCTAssertEqual(try displayRecordCount(), 2)
    }

    func testRecordDisplayFlipsOneTimeFrequencyToNotDisplayable() throws {
        let frequency = IAMFrequency(type: .oneTime, count: 1, interval: 0)
        try repository.saveMessage(campaign(id: "once", frequency: frequency))
        let stored = try XCTUnwrap(repository.fetchMessage(withId: "once"))
        XCTAssertTrue(stored.canDisplay())

        try repository.recordDisplay(for: stored)

        let refetched = try XCTUnwrap(repository.fetchMessage(withId: "once"))
        XCTAssertFalse(refetched.canDisplay())
    }

    func testRecordDisplayForADeletedCampaignDoesNotCrashOrCreateOrphans() throws {
        try repository.saveMessage(campaign(id: "gone"))
        let stored = try XCTUnwrap(repository.fetchMessage(withId: "gone"))

        try repository.replaceAllMessages([])

        XCTAssertNoThrow(try repository.recordDisplay(for: stored))
        XCTAssertEqual(try displayRecordCount(), 0)
    }

    // MARK: - Expiry cleanup

    func testDeleteExpiredMessagesRemovesOnlyExpiredCampaigns() throws {
        try repository.saveMessages([
            campaign(id: "expired", endDate: Date().addingTimeInterval(-3600)),
            campaign(id: "active", endDate: Date().addingTimeInterval(3600)),
            campaign(id: "open-ended", endDate: nil)
        ])

        try repository.deleteExpiredMessages()

        let ids = Set(try repository.fetchAllMessages().map { $0.id })
        XCTAssertEqual(ids, ["active", "open-ended"])
    }

    // MARK: - Lifetime frequency caps across campaign removal

    /// Caps are lifetime. `displayRecords` is Nullify rather than Cascade so a campaign
    /// dropped by a full-replace leaves its history behind, and the history is re-linked
    /// by id when the campaign comes back — otherwise pausing and resuming a campaign in
    /// the dashboard re-shows it to someone who already dismissed it.
    func testAOneTimeCampaignStaysCappedAfterLeavingAndRejoiningTheCampaignSet() throws {
        try repository.saveMessage(campaign(id: "c1", frequency: IAMFrequency(type: .oneTime)))
        let stored = try XCTUnwrap(repository.fetchMessage(withId: "c1"))
        try repository.recordDisplay(for: stored)
        try waitForMergedValue { try repository.fetchMessage(withId: "c1")?.canDisplay() == false }

        // The campaign stops being sent, then comes back with the same id.
        try repository.replaceAllMessages([])
        XCTAssertNil(try repository.fetchMessage(withId: "c1"), "precondition: campaign dropped")
        try repository.replaceAllMessages([campaign(id: "c1",
                                                    frequency: IAMFrequency(type: .oneTime))])

        let returned = try XCTUnwrap(repository.fetchMessage(withId: "c1"))
        XCTAssertFalse(returned.canDisplay(),
                       "a one_time campaign must not become displayable again by "
                        + "leaving and rejoining the campaign set")
    }

    func testACappedCampaignKeepsItsCountAfterLeavingAndRejoining() throws {
        let capped = IAMFrequency(type: .capped, count: 2)
        try repository.saveMessage(campaign(id: "c1", frequency: capped))
        let stored = try XCTUnwrap(repository.fetchMessage(withId: "c1"))
        try repository.recordDisplay(for: stored)
        try repository.recordDisplay(for: stored)
        try waitForMergedValue { try repository.fetchMessage(withId: "c1")?.canDisplay() == false }

        try repository.replaceAllMessages([])
        try repository.replaceAllMessages([campaign(id: "c1", frequency: capped)])

        let returned = try XCTUnwrap(repository.fetchMessage(withId: "c1"))
        XCTAssertFalse(returned.canDisplay(), "the cap of 2 was already spent")
        XCTAssertEqual((returned.displayRecords as? Set<IAMDisplayRecord>)?.count, 2,
                       "both displays must be re-linked, not just the most recent")
    }

    /// The expiry sweep deletes campaign rows too, so it must not take history with it.
    func testDisplayHistorySurvivesTheExpirySweep() throws {
        try repository.saveMessage(campaign(id: "c1",
                                            endDate: Date().addingTimeInterval(-60),
                                            frequency: IAMFrequency(type: .oneTime)))
        let stored = try XCTUnwrap(repository.fetchMessage(withId: "c1"))
        try repository.recordDisplay(for: stored)
        try waitForMergedValue { try self.displayRecordCount() == 1 }

        try repository.deleteExpiredMessages()
        try waitForMergedValue { try repository.fetchMessage(withId: "c1") == nil }

        XCTAssertEqual(try displayRecordCount(), 1,
                       "the record outlives the expired campaign")
        try repository.replaceAllMessages([campaign(id: "c1",
                                                    frequency: IAMFrequency(type: .oneTime))])
        XCTAssertFalse(try XCTUnwrap(repository.fetchMessage(withId: "c1")).canDisplay())
    }

    /// Records written before `messageId` existed carry the relationship only. The upsert
    /// stamps them, so they survive the campaign's next removal rather than orphaning.
    func testRecordsPredatingMessageIdAreStampedOnUpsert() throws {
        try repository.saveMessage(campaign(id: "c1", frequency: IAMFrequency(type: .oneTime)))
        let stored = try XCTUnwrap(repository.fetchMessage(withId: "c1"))
        try repository.recordDisplay(for: stored)
        try waitForMergedValue { try self.displayRecordCount() == 1 }

        // Simulate a pre-migration row: relationship intact, no messageId.
        try coreData.performBackgroundTask { context in
            for record in try context.fetch(IAMDisplayRecord.fetchRequest()) {
                record.messageId = nil
            }
        }

        // The next sync of this campaign stamps it...
        try repository.replaceAllMessages([campaign(id: "c1",
                                                    frequency: IAMFrequency(type: .oneTime))])
        // ...so a later removal and return still keeps the cap.
        try repository.replaceAllMessages([])
        try repository.replaceAllMessages([campaign(id: "c1",
                                                    frequency: IAMFrequency(type: .oneTime))])

        XCTAssertFalse(try XCTUnwrap(repository.fetchMessage(withId: "c1")).canDisplay(),
                       "a stamped legacy record must still cap the campaign")
    }

    // MARK: - Analytics events

    /// Bounds the head-of-line block: a persistently failing endpoint keeps the oldest
    /// event at the front of every fetch window, so without an attempt budget nothing
    /// behind it ever uploads.
    func testRecordFailedUploadIncrementsAttemptsAndKeepsTheEvent() throws {
        try repository.recordAnalyticsEvent(type: .impression, messageId: "c1")
        let event = try XCTUnwrap(repository.fetchUnsyncdAnalyticsEvents().first)
        XCTAssertEqual(event.uploadAttempts, 0, "a fresh event starts with no attempts")

        let dropped = try repository.recordFailedUpload(for: [event], maxAttempts: 3)

        XCTAssertTrue(dropped.isEmpty, "one failure is inside the budget")
        try waitForMergedValue {
            try self.repository.fetchUnsyncdAnalyticsEvents().first?.uploadAttempts == 1
        }
        XCTAssertEqual(try repository.fetchUnsyncdAnalyticsEvents().count, 1)
    }

    func testRecordFailedUploadDropsTheEventOnceItsBudgetIsSpent() throws {
        try repository.recordAnalyticsEvent(type: .impression, messageId: "c1")

        var dropped: [UUID] = []
        for _ in 0..<3 {
            let event = try XCTUnwrap(repository.fetchUnsyncdAnalyticsEvents().first)
            dropped = try repository.recordFailedUpload(for: [event], maxAttempts: 3)
        }

        XCTAssertEqual(dropped.count, 1, "the third failure spends the budget")
        try waitForMergedValue { try self.repository.fetchUnsyncdAnalyticsEvents().isEmpty }
        XCTAssertTrue(try repository.fetchUnsyncdAnalyticsEvents().isEmpty,
                      "the blocking event is dropped so the queue behind it can move")
    }

    /// Only the event a batch stopped on is charged, so a second event queued behind it
    /// must keep a full budget of its own.
    func testRecordFailedUploadChargesOnlyTheGivenEvent() throws {
        try repository.recordAnalyticsEvent(type: .impression, messageId: "head")
        try repository.recordAnalyticsEvent(type: .impression, messageId: "behind")
        let events = try repository.fetchUnsyncdAnalyticsEvents()
        let head = try XCTUnwrap(events.first { $0.messageId == "head" })

        try repository.recordFailedUpload(for: [head], maxAttempts: 3)

        try waitForMergedValue {
            try self.repository.fetchUnsyncdAnalyticsEvents()
                .first { $0.messageId == "head" }?.uploadAttempts == 1
        }
        let behind = try XCTUnwrap(
            repository.fetchUnsyncdAnalyticsEvents().first { $0.messageId == "behind" }
        )
        XCTAssertEqual(behind.uploadAttempts, 0)
    }

    func testRecordAnalyticsEventPersistsTypeMessageIdAndDate() throws {
        let before = Date()
        try repository.recordAnalyticsEvent(type: .impression, messageId: "c1")

        let events = try repository.fetchUnsyncdAnalyticsEvents()
        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.eventType, "impression")
        XCTAssertEqual(event.messageId, "c1")
        XCTAssertGreaterThanOrEqual(event.eventDate.timeIntervalSince(before), -1)
    }

    func testAnalyticsEventButtonPayloadRoundTrips() throws {
        try repository.recordAnalyticsEvent(type: .click,
                                           messageId: "c1",
                                           btnId: "cta",
                                           btnText: "Learn More",
                                           btnType: "open_url")

        let event = try XCTUnwrap(repository.fetchUnsyncdAnalyticsEvents().first)
        XCTAssertEqual(event.btnId, "cta")
        XCTAssertEqual(event.btnText, "Learn More")
        XCTAssertEqual(event.btnType, "open_url")
    }

    func testAnalyticsEventWithoutAButtonPayloadStoresNils() throws {
        try repository.recordAnalyticsEvent(type: .impression, messageId: "c1")

        let event = try XCTUnwrap(repository.fetchUnsyncdAnalyticsEvents().first)
        XCTAssertNil(event.btnId)
        XCTAssertNil(event.btnText)
        XCTAssertNil(event.btnType)
    }

    func testFetchUnsyncedAnalyticsEventsReturnsOldestFirst() throws {
        try repository.recordAnalyticsEvent(type: .impression, messageId: "first")
        try repository.recordAnalyticsEvent(type: .impression, messageId: "second")
        try repository.recordAnalyticsEvent(type: .impression, messageId: "third")

        let events = try repository.fetchUnsyncdAnalyticsEvents()
        XCTAssertEqual(events.map { $0.messageId }, ["first", "second", "third"])
    }

    func testFetchUnsyncedAnalyticsEventsHonoursTheLimit() throws {
        for index in 0..<5 {
            try repository.recordAnalyticsEvent(type: .impression, messageId: "m\(index)")
        }

        let events = try repository.fetchUnsyncdAnalyticsEvents(limit: 3)
        XCTAssertEqual(events.map { $0.messageId }, ["m0", "m1", "m2"])
    }

    func testDeleteAnalyticsEventsRemovesOnlyTheGivenEvents() throws {
        try repository.recordAnalyticsEvent(type: .impression, messageId: "keep")
        try repository.recordAnalyticsEvent(type: .impression, messageId: "drop")
        let events = try repository.fetchUnsyncdAnalyticsEvents()
        let toDelete = events.filter { $0.messageId == "drop" }

        try repository.deleteAnalyticsEvents(toDelete)

        let remaining = try repository.fetchUnsyncdAnalyticsEvents()
        XCTAssertEqual(remaining.map { $0.messageId }, ["keep"])
    }

    func testDeleteAnalyticsEventsToleratesAlreadyDeletedEvents() throws {
        try repository.recordAnalyticsEvent(type: .impression, messageId: "c1")
        let events = try repository.fetchUnsyncdAnalyticsEvents()

        try repository.deleteAnalyticsEvents(events)
        XCTAssertNoThrow(try repository.deleteAnalyticsEvents(events))
        XCTAssertEqual(try repository.unsyncedAnalyticsEventCount(), 0)
    }

    func testUnsyncedAnalyticsEventCountTracksInsertionsAndDeletions() throws {
        XCTAssertEqual(try repository.unsyncedAnalyticsEventCount(), 0)

        try repository.recordAnalyticsEvent(type: .impression, messageId: "c1")
        try repository.recordAnalyticsEvent(type: .click, messageId: "c1")
        XCTAssertEqual(try repository.unsyncedAnalyticsEventCount(), 2)

        try repository.deleteAnalyticsEvents(repository.fetchUnsyncdAnalyticsEvents())
        XCTAssertEqual(try repository.unsyncedAnalyticsEventCount(), 0)
    }

    // MARK: - Diagnostics / concurrency

    func testDiagnosticDisplayRecordsCheckDoesNotCrash() throws {
        try repository.saveMessage(campaign(id: "c1"))
        repository.diagnosticDisplayRecordsCheck()
    }

    func testConcurrentReadsAndWritesFromBackgroundThreadsDoNotCrash() throws {
        try repository.saveMessages((0..<5).map { campaign(id: "rw-\($0)") })
        let extras = (0..<10).map { campaign(id: "rw-new-\($0)") }

        let group = DispatchGroup()
        for index in 0..<30 {
            DispatchQueue.global().async(group: group) { [repository] in
                switch index % 3 {
                case 0:
                    try? repository?.saveMessage(extras[index / 3])
                case 1:
                    _ = try? repository?.fetchValidMessages()
                default:
                    _ = try? repository?.fetchMessage(withId: "rw-\(index % 5)")
                }
            }
        }

        let deadline = Date().addingTimeInterval(10)
        while group.wait(timeout: .now()) == .timedOut && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(group.wait(timeout: .now()), .success, "background work must finish")

        XCTAssertEqual(try repository.fetchAllMessages().count, 15)
    }

    func testConcurrentWritesFromManyThreadsDoNotCrash() throws {
        DispatchQueue.concurrentPerform(iterations: 20) { index in
            try? repository.saveMessage(campaign(id: "concurrent-\(index)"))
            try? repository.recordAnalyticsEvent(type: .impression,
                                                 messageId: "concurrent-\(index)")
        }

        XCTAssertEqual(try repository.fetchAllMessages().count, 20)
        XCTAssertEqual(try repository.unsyncedAnalyticsEventCount(), 20)
    }
}
