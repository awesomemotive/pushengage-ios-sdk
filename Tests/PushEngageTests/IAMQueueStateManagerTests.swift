import XCTest
@testable import PushEngage

/// Queue state tracking: state transitions, display/dismiss timestamps, and
/// cleanup. Uses the shared state manager (singleton), cleared around each test.
final class IAMQueueStateManagerTests: XCTestCase {

    private var stateManager: IAMQueueStateManager!
    private var repository: IAMRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(IAMCoreDataManager.shared.isStoreAvailable, "IAM persistent store unavailable")
        stateManager = IAMQueueStateManager.shared
        stateManager.clearAllStates()
        repository = IAMRepository()
        try repository.replaceAllMessages([])
    }

    override func tearDownWithError() throws {
        stateManager.clearAllStates()
        try? repository.replaceAllMessages([])
        try super.tearDownWithError()
    }

    private func saveCampaign(id: String, position: IAMPosition = .center) throws -> IAMMessage {
        let response = IAMMessageResponse(
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
            trigger: IAMTriggerCondition(type: "custom", event: "evt", parameters: nil)
        )
        try repository.saveMessage(response)
        return try XCTUnwrap(repository.fetchMessage(withId: id))
    }

    // MARK: - Basic state transitions

    func testDefaultStateIsQueued() {
        XCTAssertEqual(stateManager.getState(for: "unknown"), .queued)
    }

    func testUpdatedStateIsReturnedByGetState() {
        stateManager.updateState(for: "m1", to: .ready)
        XCTAssertEqual(stateManager.getState(for: "m1"), .ready)
    }

    func testIsDisplayingReflectsTheDisplayingState() throws {
        _ = try saveCampaign(id: "m1")
        stateManager.updateState(for: "m1", to: .displaying)
        XCTAssertTrue(stateManager.isDisplaying("m1"))

        stateManager.updateState(for: "m1", to: .dismissed)
        XCTAssertFalse(stateManager.isDisplaying("m1"))
    }

    func testExpiredClearsTimestamps() throws {
        _ = try saveCampaign(id: "m1")
        stateManager.updateState(for: "m1", to: .displaying)
        stateManager.updateState(for: "m1", to: .dismissed)

        stateManager.updateState(for: "m1", to: .expired)

        XCTAssertNil(stateManager.getLastDisplayTime(for: "m1"))
        XCTAssertNil(stateManager.getLastDismissTime(for: "m1"))
        XCTAssertEqual(stateManager.getState(for: "m1"), .expired)
    }

    // MARK: - Timestamps

    func testDisplayDurationRequiresBothTimestamps() {
        XCTAssertNil(stateManager.getDisplayDuration(for: "m1"))

        stateManager.updateState(for: "m1", to: .displaying)
        XCTAssertNil(stateManager.getDisplayDuration(for: "m1"))
    }

    func testDisplayDurationIsTheGapBetweenDisplayAndDismiss() {
        stateManager.updateState(for: "m1", to: .displaying)
        stateManager.updateState(for: "m1", to: .dismissed)

        let duration = stateManager.getDisplayDuration(for: "m1")
        XCTAssertNotNil(duration)
        XCTAssertGreaterThanOrEqual(duration ?? -1, 0)
        XCTAssertLessThan(duration ?? 100, 5)
    }

    // MARK: - Cleanup and resilience

    func testClearStateResetsStateAndTimestamps() throws {
        _ = try saveCampaign(id: "m1")
        stateManager.updateState(for: "m1", to: .displaying)

        stateManager.clearState(for: "m1")

        XCTAssertEqual(stateManager.getState(for: "m1"), .queued)
        XCTAssertNil(stateManager.getLastDisplayTime(for: "m1"))
    }

    func testClearAllStatesResetsEverything() throws {
        _ = try saveCampaign(id: "m1")
        stateManager.updateState(for: "m1", to: .displaying)

        stateManager.clearAllStates()

        XCTAssertEqual(stateManager.getState(for: "m1"), .queued)
        XCTAssertNil(stateManager.getLastDisplayTime(for: "m1"))
    }

    func testUpdateStateForAnUnknownMessageDoesNotCrash() {
        stateManager.updateState(for: "not-in-db", to: .displaying)
        stateManager.updateState(for: "not-in-db", to: .dismissed)
        stateManager.updateState(for: "not-in-db", to: .expired)

        XCTAssertEqual(stateManager.getState(for: "not-in-db"), .expired)
    }
}
