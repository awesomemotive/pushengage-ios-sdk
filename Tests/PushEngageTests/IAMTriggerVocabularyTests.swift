import XCTest
@testable import PushEngage

/// Trigger parameters and audience conditions are **separate vocabularies**:
/// audience conditions read subscriber and device data only, trigger conditions
/// read the event payload only, and neither falls through to the other.
///
/// These drive the real controller, because the destructive behaviour they pin
/// lived in `processTrigger` — engine-level tests would not have caught it.
final class IAMTriggerVocabularyTests: XCTestCase {

    private var controller: IAMController!
    private var repository: IAMRepository!
    private var engine: IAMDisplayRulesEngine!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(IAMCoreDataManager.shared.isStoreAvailable, "IAM persistent store unavailable")

        controller = IAMController.shared
        repository = IAMRepository()
        engine = IAMDisplayRulesEngine.shared
        try repository.replaceAllMessages([])
        IAMQueueStateManager.shared.clearAllStates()
        IAMQueueManager.shared.pauseQueue()
        controller.enable()
        clearIAMDefaults()
    }

    override func tearDownWithError() throws {
        let cleanup = expectation(description: "queue cleared")
        IAMQueueManager.shared.clearQueue { cleanup.fulfill() }
        wait(for: [cleanup], timeout: 5)
        IAMQueueStateManager.shared.clearAllStates()
        try? repository.replaceAllMessages([])
        clearIAMDefaults()
        try super.tearDownWithError()
    }

    /// The shared engine reads standard UserDefaults, so state has to be reset
    /// between tests or one test's attributes decide the next one's audience.
    private func clearIAMDefaults() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(IAMDeviceProperties.StorageKey.attributePrefix)
            || key.hasPrefix("pe_iam_") {
            defaults.removeObject(forKey: key)
        }
    }

    private func campaign(id: String, audience: String?, triggerJSON: String? = nil) throws -> IAMMessageResponse {
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
            audience: try audience.map { try IAMRawJSON(data: Data($0.utf8)) },
            frequency: nil,
            trigger: IAMTriggerCondition(type: "custom", event: "checkout")
        )
    }

    private func fire(_ parameters: [String: Any]?) {
        controller.processTrigger("checkout", parameters: parameters)
        let drained = expectation(description: "trigger processed")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5)
    }

    private func clearQueue() {
        let cleared = expectation(description: "queue cleared")
        IAMQueueManager.shared.clearQueue { cleared.fulfill() }
        wait(for: [cleared], timeout: 5)
        IAMQueueStateManager.shared.clearAllStates()
    }

    // MARK: - The data-loss bug

    func testAStoredAttributeSurvivesATriggerCarryingTheSameKey() throws {
        // The old code wrote each trigger parameter into the attribute store and
        // then DELETED the key — so a colliding parameter destroyed the stored
        // value outright, and silently, because a missing attribute fails a
        // positive condition closed.
        engine.setUserAttribute("gold", for: "plan")
        try repository.replaceAllMessages([
            try campaign(id: "plan-gold", audience: #"[{"field":"plan","op":"eq","value":["gold"]}]"#)
        ])

        fire(["plan": "trial"])

        // Audience reads the store, not the parameters, so it still sees "gold".
        XCTAssertTrue(IAMQueueManager.shared.queuedMessageIds.contains("plan-gold"))

        clearQueue()

        // And the stored value is intact for the next evaluation.
        fire(nil)
        XCTAssertTrue(IAMQueueManager.shared.queuedMessageIds.contains("plan-gold"))
    }

    func testTriggerParametersAreNeverPersisted() throws {
        try repository.replaceAllMessages([
            try campaign(id: "leak-check", audience: #"[{"field":"promo","op":"eq","value":["summer"]}]"#)
        ])

        fire(["promo": "summer"])
        // Parameters are not an audience vocabulary, so this never matched...
        XCTAssertFalse(IAMQueueManager.shared.queuedMessageIds.contains("leak-check"))

        // ...and nothing was written, so a later evaluation cannot inherit it.
        XCTAssertNil(UserDefaults.standard
            .string(forKey: IAMDeviceProperties.StorageKey.attributePrefix + "promo"))
    }

    // MARK: - Separate vocabularies

    func testATriggerParameterCannotShadowABuiltInAudienceField() throws {
        // Previously a parameter named `platform` overrode the real value for that
        // evaluation. There was even a test asserting that override; it is inverted.
        try repository.replaceAllMessages([
            try campaign(id: "fake-android", audience: #"[{"field":"platform","op":"eq","value":["Android"]}]"#)
        ])

        fire(["platform": "Android"])

        XCTAssertFalse(IAMQueueManager.shared.queuedMessageIds.contains("fake-android"))
    }

    func testAudienceConditionsDoNotResolveTriggerParameters() throws {
        // `cart_value > 100` belongs in the trigger section — which is what C2 gives
        // operators and types to. The capability moved rather than going away.
        try repository.replaceAllMessages([
            try campaign(id: "audience-cart",
                         audience: #"[{"field":"cart_value","type":"number","op":"gte","value":["100"]}]"#)
        ])

        fire(["cart_value": 150])

        XCTAssertFalse(IAMQueueManager.shared.queuedMessageIds.contains("audience-cart"))
    }

    func testTriggerConditionsAndAudienceConditionsBothApply() throws {
        engine.setUserAttribute("gold", for: "plan")
        let response = try campaign(id: "both",
                                    audience: #"[{"field":"plan","op":"eq","value":["gold"]}]"#)
        try repository.replaceAllMessages([response])

        // Give the stored campaign a trigger condition on the event payload.
        let message = try XCTUnwrap(try repository.fetchMessage(withId: "both"))
        message.trigger = Data("""
        {"type":"custom","event":"checkout","conditions":[
          {"field":"cart_value","type":"number","op":"gte","value":["100"]}]}
        """.utf8)
        try message.managedObjectContext?.save()

        fire(["cart_value": 50])
        XCTAssertFalse(IAMQueueManager.shared.queuedMessageIds.contains("both"),
                       "trigger condition not satisfied")

        clearQueue()

        fire(["cart_value": 150])
        XCTAssertTrue(IAMQueueManager.shared.queuedMessageIds.contains("both"),
                      "both the trigger condition and the audience hold")
    }
}
