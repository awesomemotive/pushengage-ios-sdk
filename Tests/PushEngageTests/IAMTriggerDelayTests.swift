import XCTest
import CoreData
@testable import PushEngage

/// `trigger.delay` — the pre-display wait for app-open campaigns (C6b).
///
/// The countdown starts at app open (so a slow sync is absorbed rather than added
/// on top), freezes while backgrounded, and applies to `auto` triggers only.
final class IAMTriggerDelayReadingTests: XCTestCase {

    private func trigger(_ json: String) -> Data { Data(json.utf8) }

    // MARK: - Reading the field

    func testAbsentDelayMeansShowImmediately() {
        XCTAssertEqual(IAMTriggerDelay.remaining(triggerJSON: trigger(#"{"type":"auto"}"#),
                                                 appOpenAt: 100, now: 100), 0)
    }

    func testZeroDelayMeansShowImmediately() {
        XCTAssertEqual(IAMTriggerDelay.remaining(triggerJSON: trigger(#"{"type":"auto","delay":0}"#),
                                                 appOpenAt: 100, now: 100), 0)
    }

    func testNegativeDelayMeansShowImmediately() {
        XCTAssertEqual(IAMTriggerDelay.remaining(triggerJSON: trigger(#"{"type":"auto","delay":-5}"#),
                                                 appOpenAt: 100, now: 100), 0)
    }

    func testDelayIsReadAsSecondsNotMilliseconds() {
        // The unit is not in the field name (matching frequency.interval and
        // displayDuration, also bare seconds), so it is pinned here: a millis
        // regression would make every delay 1000× too short and look like "the
        // delay does nothing".
        XCTAssertEqual(IAMTriggerDelay.remaining(triggerJSON: trigger(#"{"type":"auto","delay":5}"#),
                                                 appOpenAt: 100, now: 100), 5)
    }

    func testFractionalDelaysAreRead() {
        XCTAssertEqual(IAMTriggerDelay.remaining(triggerJSON: trigger(#"{"type":"auto","delay":1.5}"#),
                                                 appOpenAt: 100, now: 100), 1.5)
    }

    func testMalformedTriggerJSONMeansNoDelay() {
        XCTAssertEqual(IAMTriggerDelay.remaining(triggerJSON: trigger("not json"),
                                                 appOpenAt: 100, now: 100), 0)
        XCTAssertEqual(IAMTriggerDelay.remaining(triggerJSON: nil, appOpenAt: 100, now: 100), 0)
    }

    func testNonNumericDelayMeansNoDelay() {
        XCTAssertEqual(IAMTriggerDelay.remaining(triggerJSON: trigger(#"{"type":"auto","delay":"soon"}"#),
                                                 appOpenAt: 100, now: 100), 0)
    }

    // MARK: - Measured from app open

    func testTimeAlreadySpentSinceAppOpenIsSubtracted() {
        // Sync time is absorbed BY the delay, not added on top of it.
        XCTAssertEqual(IAMTriggerDelay.remaining(triggerJSON: trigger(#"{"type":"auto","delay":12}"#),
                                                 appOpenAt: 100, now: 103.16),
                       8.84, accuracy: 0.001)
    }

    func testADelayThatElapsedDuringTheSyncQueuesImmediately() {
        XCTAssertEqual(IAMTriggerDelay.remaining(triggerJSON: trigger(#"{"type":"auto","delay":3}"#),
                                                 appOpenAt: 100, now: 109), 0)
    }

    func testWithoutARecordedAppOpenInstantTheDelayRunsFromNow() {
        // Auto triggers evaluated outside the app-open path have no origin to
        // measure from, so the full delay applies.
        XCTAssertEqual(IAMTriggerDelay.remaining(triggerJSON: trigger(#"{"type":"auto","delay":7}"#),
                                                 appOpenAt: nil, now: 500), 7)
    }
}

/// The pausable countdown itself.
final class IAMTriggerDelaySchedulerTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!
    private var clock: TimeInterval = 0
    private var timers: ManualTimerFactory!
    private var released: [String] = []
    private var scheduler: IAMTriggerDelayScheduler!

    override func setUpWithError() throws {
        try super.setUpWithError()
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

        clock = 1000
        timers = ManualTimerFactory()
        released = []
        scheduler = IAMTriggerDelayScheduler(clock: { [unowned self] in self.clock },
                                             timerFactory: timers) { [unowned self] messageId in
            self.released.append(messageId)
        }
    }

    override func tearDown() {
        scheduler = nil
        timers = nil
        container = nil
        context = nil
        super.tearDown()
    }

    private var counter = 0

    private func makeMessage() throws -> IAMMessage {
        counter += 1
        let response = IAMMessageResponse(
            id: "delay-\(counter)",
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
            trigger: IAMTriggerCondition(type: "auto")
        )
        let message = try IAMMessage.create(from: response, in: context)
        try context.save()
        return message
    }

    // MARK: - Immediate release

    func testANonPositiveDelayReleasesImmediately() throws {
        let message = try makeMessage()
        scheduler.schedule(messageId: message.id, after: 0)
        XCTAssertEqual(released, [message.id])
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    // MARK: - Withholding

    func testAScheduledMessageIsWithheldUntilItsTimerFires() throws {
        let message = try makeMessage()
        scheduler.schedule(messageId: message.id, after: 5)

        XCTAssertTrue(released.isEmpty)
        XCTAssertEqual(scheduler.pendingCount, 1)
        XCTAssertEqual(timers.pending.last?.delay, 5)

        timers.fireAll()
        XCTAssertEqual(released, [message.id])
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testRescheduglingAnAlreadyWaitingMessageIsIgnored() throws {
        let message = try makeMessage()
        scheduler.schedule(messageId: message.id, after: 5)
        scheduler.schedule(messageId: message.id, after: 5)

        XCTAssertEqual(scheduler.pendingCount, 1)
        XCTAssertEqual(timers.pending.count, 1)

        timers.fireAll()
        XCTAssertEqual(released, [message.id], "must not double-queue")
    }

    func testEachMessageGetsItsOwnCountdown() throws {
        let first = try makeMessage()
        let second = try makeMessage()
        scheduler.schedule(messageId: first.id, after: 5)
        scheduler.schedule(messageId: second.id, after: 10)

        XCTAssertEqual(scheduler.pendingCount, 2)
        timers.fire(at: 0)
        XCTAssertEqual(released, [first.id])
        XCTAssertEqual(scheduler.pendingCount, 1)

        timers.fireAll()
        XCTAssertEqual(released, [first.id, second.id])
    }

    // MARK: - Pause and resume

    func testBackgroundingFreezesTheCountdownAndResumingUsesTheRemainingTime() throws {
        // A 5s delay backgrounded at 2s has 3s left when the app returns —
        // background time never counts toward the delay.
        let message = try makeMessage()
        scheduler.schedule(messageId: message.id, after: 5)

        clock += 2
        scheduler.pause()
        XCTAssertTrue(timers.pending.isEmpty, "the timer is cancelled while paused")

        clock += 300  // a long time in the background
        scheduler.resume()

        XCTAssertEqual(timers.pending.last?.delay, 3)
        XCTAssertTrue(released.isEmpty)
        timers.fireAll()
        XCTAssertEqual(released, [message.id])
    }

    func testRepeatedPauseAndResumeCyclesDoNotLoseTime() throws {
        let message = try makeMessage()
        scheduler.schedule(messageId: message.id, after: 10)

        clock += 4
        scheduler.pause()
        clock += 100
        scheduler.resume()
        XCTAssertEqual(timers.pending.last?.delay, 6)

        clock += 5
        scheduler.pause()
        clock += 100
        scheduler.resume()
        XCTAssertEqual(timers.pending.last?.delay, 1)
    }

    func testACountdownThatWouldHaveElapsedInTheBackgroundResumesWithNoTimeLeft() throws {
        let message = try makeMessage()
        scheduler.schedule(messageId: message.id, after: 5)

        clock += 5
        scheduler.pause()
        scheduler.resume()

        XCTAssertEqual(timers.pending.last?.delay, 0)
        timers.fireAll()
        XCTAssertEqual(released, [message.id])
    }

    func testSchedulingWhilePausedWaitsForTheResume() throws {
        let message = try makeMessage()
        scheduler.pause()
        scheduler.schedule(messageId: message.id, after: 5)

        XCTAssertTrue(timers.pending.isEmpty)
        XCTAssertEqual(scheduler.pendingCount, 1)

        clock += 50
        scheduler.resume()
        XCTAssertEqual(timers.pending.last?.delay, 5, "the full delay, unspent")
    }

    func testPauseAndResumeAreIdempotent() throws {
        let message = try makeMessage()
        scheduler.schedule(messageId: message.id, after: 5)

        clock += 1
        scheduler.pause()
        clock += 1
        scheduler.pause()  // second pause must not bank the extra second again
        scheduler.resume()
        scheduler.resume()  // second resume must not restart the countdown

        XCTAssertEqual(timers.pending.count, 1)
        XCTAssertEqual(timers.pending.last?.delay, 4)
    }

    func testResumingWithNothingPendingDoesNothing() {
        scheduler.pause()
        scheduler.resume()
        XCTAssertTrue(timers.pending.isEmpty)
        XCTAssertTrue(released.isEmpty)
    }

    // MARK: - Clearing

    func testClearDropsPendingCountdownsWithoutReleasingThem() throws {
        let message = try makeMessage()
        scheduler.schedule(messageId: message.id, after: 5)
        scheduler.clear()

        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertTrue(timers.pending.isEmpty)
        timers.fireAll()
        XCTAssertTrue(released.isEmpty)
    }
}

/// Which paths honour `trigger.delay` — app open only (D2).
final class IAMTriggerDelayWiringTests: XCTestCase {

    private var controller: IAMController!
    private var repository: IAMRepository!
    private var timers: ManualTimerFactory!
    private var released: [String] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(IAMCoreDataManager.shared.isStoreAvailable, "IAM persistent store unavailable")

        controller = IAMController.shared
        repository = IAMRepository()
        try repository.replaceAllMessages([])
        IAMQueueStateManager.shared.clearAllStates()
        IAMQueueManager.shared.pauseQueue()
        controller.enable()

        timers = ManualTimerFactory()
        released = []
        // Only the timers are stubbed: releases go through the controller's real
        // resolution path, so what it does with a vanished campaign is under test.
        controller.triggerDelayScheduler = IAMTriggerDelayScheduler(timerFactory: timers) {
            [unowned self] messageId in
            self.released.append(messageId)
            self.controller.releaseDelayedMessage(id: messageId)
        }
    }

    override func tearDownWithError() throws {
        let cleanup = expectation(description: "queue cleared")
        IAMQueueManager.shared.clearQueue { cleanup.fulfill() }
        wait(for: [cleanup], timeout: 5)
        controller.triggerDelayScheduler.clear()
        // Restore the production scheduler: this is the process-wide singleton, and
        // leaving hand-fired timers installed would strand any later suite's
        // delayed campaign.
        controller.triggerDelayScheduler = IAMController.productionDelayScheduler(for: controller)
        IAMQueueStateManager.shared.clearAllStates()
        try? repository.replaceAllMessages([])
        try super.tearDownWithError()
    }

    private func campaign(id: String, triggerJSON: String) -> IAMMessageResponse {
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
            // Persisted first, then overwritten with the raw trigger JSON below.
            trigger: IAMTriggerCondition(type: triggerJSON.contains("\"auto\"") ? "auto" : "custom",
                                         event: "delayed_event")
        )
    }

    private func store(_ responses: [(id: String, triggerJSON: String)]) throws {
        try repository.replaceAllMessages(responses.map { campaign(id: $0.id, triggerJSON: $0.triggerJSON) })
        for response in responses {
            let message = try XCTUnwrap(try repository.fetchMessage(withId: response.id))
            message.trigger = Data(response.triggerJSON.utf8)
            try message.managedObjectContext?.save()
        }
    }

    private func drainMain() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5)
    }

    func testAnAutoCampaignWithADelayIsHeldBackThenReleased() throws {
        try store([(id: "delayed", triggerJSON: #"{"type":"auto","delay":5}"#)])

        controller.processAutoTriggers()
        drainMain()

        XCTAssertFalse(IAMQueueManager.shared.queuedMessageIds.contains("delayed"))
        XCTAssertEqual(controller.triggerDelayScheduler.pendingCount, 1)
        XCTAssertEqual(timers.pending.last?.delay, 5)

        timers.fireAll()
        drainMain()
        XCTAssertEqual(released, ["delayed"])
        XCTAssertTrue(IAMQueueManager.shared.queuedMessageIds.contains("delayed"))
    }

    func testAnAutoCampaignWithoutADelayQueuesImmediately() throws {
        try store([(id: "prompt", triggerJSON: #"{"type":"auto"}"#)])

        controller.processAutoTriggers()
        drainMain()

        XCTAssertTrue(IAMQueueManager.shared.queuedMessageIds.contains("prompt"))
        XCTAssertEqual(controller.triggerDelayScheduler.pendingCount, 0)
    }

    func testACampaignDeletedDuringItsCountdownIsNotQueuedWhenTheDelayElapses() throws {
        // A sync full-replaces the campaign set, so a campaign the marketer paused
        // can vanish mid-countdown. Releasing it would show a campaign the backend
        // no longer has — and the row it points at is gone.
        try store([(id: "delayed", triggerJSON: #"{"type":"auto","delay":5}"#)])

        controller.processAutoTriggers()
        drainMain()
        XCTAssertEqual(controller.triggerDelayScheduler.pendingCount, 1)

        try repository.replaceAllMessages([])

        timers.fireAll()
        drainMain()
        // Emptiness, not merely absence of the id: an invalidated managed object
        // reads its non-optional `id` back as "", so a leaked campaign enters the
        // queue as an unattributable phantom rather than under its own id.
        XCTAssertTrue(IAMQueueManager.shared.queuedMessageIds.isEmpty,
                      "a deleted campaign must not be queued when its delay elapses")
    }

    func testACampaignThatExpiredDuringItsCountdownIsNotQueued() throws {
        // Eligibility is re-checked at release, not only at schedule time: a delay
        // window can outlive the campaign's own end date.
        try store([(id: "expiring", triggerJSON: #"{"type":"auto","delay":5}"#)])

        controller.processAutoTriggers()
        drainMain()
        XCTAssertEqual(controller.triggerDelayScheduler.pendingCount, 1)

        let message = try XCTUnwrap(try repository.fetchMessage(withId: "expiring"))
        message.endDate = Date().addingTimeInterval(-60)
        try message.managedObjectContext?.save()

        timers.fireAll()
        drainMain()
        XCTAssertTrue(IAMQueueManager.shared.queuedMessageIds.isEmpty,
                      "an expired campaign must not be queued when its delay elapses")
    }

    func testACustomTriggerIgnoresTheDelayField() throws {
        // D2: the dashboard only ever emits `delay` for app-open campaigns, and the
        // SDK must not honour it on the custom-trigger path.
        try store([(id: "custom-delayed",
                    triggerJSON: #"{"type":"custom","event":"delayed_event","delay":30}"#)])

        controller.processTrigger("delayed_event", parameters: nil)
        drainMain()

        XCTAssertTrue(IAMQueueManager.shared.queuedMessageIds.contains("custom-delayed"))
        XCTAssertEqual(controller.triggerDelayScheduler.pendingCount, 0)
        XCTAssertTrue(timers.pending.isEmpty)
    }
}

/// Timers the test fires by hand, so countdown arithmetic is asserted rather than
/// waited on.
private final class ManualTimerFactory: IAMDelayTimerFactory {

    final class Pending: IAMDelayTimer {
        let delay: TimeInterval
        let fire: () -> Void
        private(set) var isCancelled = false
        weak var factory: ManualTimerFactory?

        init(delay: TimeInterval, fire: @escaping () -> Void) {
            self.delay = delay
            self.fire = fire
        }

        func cancel() {
            isCancelled = true
            factory?.remove(self)
        }
    }

    private(set) var pending: [Pending] = []

    func timer(after delay: TimeInterval, _ fire: @escaping () -> Void) -> IAMDelayTimer {
        let timer = Pending(delay: delay, fire: fire)
        timer.factory = self
        pending.append(timer)
        return timer
    }

    func remove(_ timer: Pending) {
        pending.removeAll { $0 === timer }
    }

    func fire(at index: Int) {
        let timer = pending[index]
        pending.remove(at: index)
        timer.fire()
    }

    func fireAll() {
        let due = pending
        pending.removeAll()
        due.forEach { $0.fire() }
    }
}
