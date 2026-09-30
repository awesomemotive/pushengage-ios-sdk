import XCTest
@testable import PushEngage

/// Analytics tracking pipeline: track calls must land in the local store with the
/// right event type and button payload, tolerate concurrent callers, and
/// processPendingEvents must be safe when there is nothing to process.
///
/// Events are asserted by polling immediately after tracking because the manager
/// schedules background processing of recorded events on its own.
final class IAMAnalyticsManagerTests: XCTestCase {

    private var repository: IAMRepository!
    private var manager: IAMAnalyticsManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(IAMCoreDataManager.shared.isStoreAvailable, "IAM persistent store unavailable")
        repository = IAMRepository()
        try purgeEvents()
        manager = IAMAnalyticsManager(repository: repository)
    }

    override func tearDownWithError() throws {
        manager = nil
        try? purgeEvents()
        repository = nil
        try super.tearDownWithError()
    }

    private func purgeEvents() throws {
        let events = try repository.fetchUnsyncdAnalyticsEvents(limit: 10_000)
        try repository.deleteAnalyticsEvents(events)
    }

    /// A tracked event's fields, snapshotted in the same pass as the lookup so
    /// assertions are immune to the manager's own background processing.
    private struct Snapshot {
        let type: String
        let btnId: String?
        let btnText: String?
        let btnType: String?
    }

    private func waitForEvent(messageId: String, timeout: TimeInterval = 3) throws -> Snapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let events = try repository.fetchUnsyncdAnalyticsEvents(limit: 1_000)
            if let match = events.first(where: { $0.messageId == messageId }) {
                return Snapshot(type: match.eventType,
                                btnId: match.btnId,
                                btnText: match.btnText,
                                btnType: match.btnType)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return nil
    }

    // MARK: - Impressions

    func testTrackImpressionRecordsAnImpressionEventWithNoButtonPayload() throws {
        let id = "imp-\(UUID().uuidString)"

        manager.trackImpression(messageId: id)

        let event = try XCTUnwrap(waitForEvent(messageId: id))
        XCTAssertEqual(event.type, "impression")
        XCTAssertNil(event.btnId)
        XCTAssertNil(event.btnText)
        XCTAssertNil(event.btnType)
    }

    // MARK: - Clicks

    func testRecordActionTapStoresTheFullButtonPayload() throws {
        let id = "click-\(UUID().uuidString)"
        let action = IAMAction(type: .openURL, parameters: ["url": "https://x.y"], label: "Learn More")

        manager.recordActionTap(messageId: id, actionId: "cta", action: action)

        let event = try XCTUnwrap(waitForEvent(messageId: id))
        XCTAssertEqual(event.type, "click")
        XCTAssertEqual(event.btnId, "cta")
        XCTAssertEqual(event.btnText, "Learn More")
        XCTAssertEqual(event.btnType, "open_url")
    }

    func testADismissButtonTapIsRecordedAsAClickCarryingTheDismissType() throws {
        // This is how `Closes` gets populated: the backend routes a click whose
        // btn_type is `dismiss` to the close column. iOS previously skipped dismiss
        // buttons entirely, so that metric could never be non-zero.
        let id = "dismiss-\(UUID().uuidString)"
        let action = IAMAction(type: .dismiss, parameters: [:], label: "Not Now")

        manager.recordActionTap(messageId: id, actionId: "close", action: action)

        let event = try XCTUnwrap(waitForEvent(messageId: id))
        XCTAssertEqual(event.type, "click")
        XCTAssertEqual(event.btnType, "dismiss")
        XCTAssertEqual(event.btnText, "Not Now")
    }

    func testAnActionWithNoLabelRecordsNoButtonText() throws {
        // IAMAction.label is nullable, so btn_text is simply absent — worth knowing
        // if backend validation ever makes it required.
        let id = "nolabel-\(UUID().uuidString)"
        let action = IAMAction(type: .custom, parameters: [:], label: nil)

        manager.recordActionTap(messageId: id, actionId: "act", action: action)

        let event = try XCTUnwrap(waitForEvent(messageId: id))
        XCTAssertEqual(event.btnType, "custom")
        XCTAssertNil(event.btnText)
    }

    func testEveryActionTypeRecordsItsLowercaseWireValue() throws {
        let expected: [(IAMActionType, String)] = [
            (.openURL, "open_url"),
            (.requestNotificationPermission, "request_notification_permission"),
            (.dismiss, "dismiss"),
            (.custom, "custom")
        ]

        for (type, wireValue) in expected {
            let id = "type-\(wireValue)-\(UUID().uuidString)"
            manager.recordActionTap(messageId: id,
                                    actionId: "b",
                                    action: IAMAction(type: type, parameters: [:], label: nil))
            let event = try XCTUnwrap(waitForEvent(messageId: id))
            XCTAssertEqual(event.btnType, wireValue)
        }
    }

    // MARK: - Durability

    func testTrackedEventsSurviveUntilExplicitlyUploaded() throws {
        let id = "keep-\(UUID().uuidString)"

        manager.trackImpression(messageId: id)
        _ = try XCTUnwrap(waitForEvent(messageId: id))

        RunLoop.current.run(until: Date().addingTimeInterval(1.2))

        let stillStored = try repository.fetchUnsyncdAnalyticsEvents(limit: 1_000)
            .contains { $0.messageId == id }
        XCTAssertTrue(stillStored, "events must stay queued until actually uploaded")
    }

    func testTrackingFromConcurrentThreadsDoesNotCrash() {
        DispatchQueue.concurrentPerform(iterations: 12) { index in
            manager.trackImpression(messageId: "concurrent-\(index)")
            manager.recordClick(messageId: "concurrent-\(index)",
                                actionId: "e\(index)",
                                label: "L",
                                actionType: "custom")
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    // MARK: - Upload pipeline

    func testProcessPendingEventsDelegatesToTheUploadPipeline() throws {
        let id = "delegate-\(UUID().uuidString)"
        manager.trackImpression(messageId: id)
        _ = try XCTUnwrap(waitForEvent(messageId: id))

        let uploaded = expectation(description: "upload handler invoked")
        manager.setUploadHandler { completion in
            uploaded.fulfill()
            completion(nil)
        }

        let completed = expectation(description: "completion")
        manager.processPendingEvents { result in
            if case .success(let count) = result {
                XCTAssertGreaterThanOrEqual(count, 1)
            } else {
                XCTFail("expected success, got \(result)")
            }
            completed.fulfill()
        }
        wait(for: [uploaded, completed], timeout: 5)
    }

    func testProcessPendingEventsReportsPipelineFailures() throws {
        let id = "pipeline-fail-\(UUID().uuidString)"
        manager.trackImpression(messageId: id)
        _ = try XCTUnwrap(waitForEvent(messageId: id))

        manager.setUploadHandler { completion in
            completion(.connectionFailed)
        }

        let completed = expectation(description: "completion")
        manager.processPendingEvents { result in
            if case .success = result {
                XCTFail("expected failure")
            }
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)

        let stillStored = try repository.fetchUnsyncdAnalyticsEvents(limit: 1_000)
            .contains { $0.messageId == id }
        XCTAssertTrue(stillStored)
    }

    // MARK: - The message is the authored HTML, nothing else

    /// The SDK adds no chrome of its own: the campaign's HTML draws the whole
    /// message, close control included. A native close button here was an
    /// invisible tappable patch over every message — its image was looked up in the
    /// host app's bundle, where the SDK ships nothing — and Android renders none
    /// either, so one payload has to behave the same on both.
    func testNoNativeCloseControlIsAddedOverTheMessage() throws {
        let message = try makeStoredMessage(id: "no-chrome-\(UUID().uuidString)")
        let controller = IAMViewController(message: message)
        controller.loadViewIfNeeded()

        XCTAssertNil(firstButton(in: controller.view),
                     "the SDK must not add its own controls over the authored HTML")
    }

    /// The scrim behind the message stays light. It covers the whole screen for
    /// EVERY position, banners included, so a heavy value made a `top` banner read as
    /// a modal takeover rather than Android's floating card over an untouched screen.
    /// Pinned because it is a one-character regression away from being heavy again.
    func testBackdropScrimIsLightForEveryPosition() throws {
        for position in [IAMPosition.top, .bottom, .center, .full] {
            let message = try makeStoredMessage(id: "scrim-\(position.rawValue)-\(UUID().uuidString)",
                                                position: position)
            let controller = IAMViewController(message: message)
            controller.loadViewIfNeeded()

            var alpha: CGFloat = 0
            XCTAssertTrue(controller.view.backgroundColor?.getWhite(nil, alpha: &alpha) ?? false,
                          "\(position.rawValue): expected a greyscale scrim colour")
            XCTAssertEqual(alpha, IAMViewController.backdropAlpha, accuracy: 0.001,
                           "\(position.rawValue): scrim opacity drifted from the agreed value")
            XCTAssertLessThanOrEqual(alpha, 0.2,
                                     "\(position.rawValue): scrim is heavy enough to make a banner look modal")
            XCTAssertGreaterThan(alpha, 0,
                                 "\(position.rawValue): scrim must stay hit-testable for the outside tap")
        }
    }

    private func firstButton(in view: UIView) -> UIButton? {
        if let button = view as? UIButton { return button }
        for subview in view.subviews {
            if let found = firstButton(in: subview) { return found }
        }
        return nil
    }

    private func makeStoredMessage(id: String,
                                   position: IAMPosition = .center) throws -> IAMMessage {
        try repository.saveMessage(IAMMessageResponse(
            id: id,
            position: position,
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
        ))
        return try XCTUnwrap(repository.fetchMessage(withId: id))
    }

    /// `isSyncing` used to be checked and set on the caller's thread while being reset
    /// on main, so two callers arriving on different threads could both pass the guard
    /// and start overlapping flushes of the same events.
    func testOverlappingFlushesInvokeTheUploadHandlerOnce() throws {
        let id = "overlap-\(UUID().uuidString)"
        manager.trackImpression(messageId: id)
        _ = try XCTUnwrap(waitForEvent(messageId: id))

        // Held open so the first flush is still in flight when the second arrives.
        let lock = NSLock()
        var handlerCalls = 0
        var release: ((IAMSyncError?) -> Void)?
        let firstCall = expectation(description: "upload handler invoked")
        manager.setUploadHandler { completion in
            lock.lock()
            handlerCalls += 1
            let isFirst = handlerCalls == 1
            lock.unlock()
            if isFirst {
                release = completion
                firstCall.fulfill()
            } else {
                completion(nil)
            }
        }

        manager.processPendingEvents()
        wait(for: [firstCall], timeout: 5)

        // Second flush while the first is still in flight, from another thread.
        let second = expectation(description: "second flush answered")
        DispatchQueue.global().async {
            self.manager.processPendingEvents { _ in second.fulfill() }
        }
        wait(for: [second], timeout: 5)

        lock.lock()
        let calls = handlerCalls
        lock.unlock()
        XCTAssertEqual(calls, 1, "the in-flight flush must absorb the second caller")

        release?(nil)
    }

    func testProcessPendingEventsWithNothingToProcessReportsZero() throws {
        try purgeEvents()

        let expectation = expectation(description: "completion")
        manager.processPendingEvents { result in
            if case .success(let count) = result {
                XCTAssertEqual(count, 0)
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }
}
