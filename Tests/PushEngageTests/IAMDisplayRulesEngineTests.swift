import XCTest
import CoreData
@testable import PushEngage

/// Display-rule eligibility tests mirroring Android's IAMRulesEngineTest,
/// per docs/plans/2026-07-10-iam-sdk-flow-and-backend-contract.md
/// (§1.2 pipeline, §3.4 dates, §3.5 audience, §3.7 frequency).
final class IAMDisplayRulesEngineTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!
    private var userDefaults: UserDefaults!
    private var engine: IAMDisplayRulesEngine!

    private static let suiteName = "IAMDisplayRulesEngineTests"

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Share the single per-process model instance — a second
        // NSManagedObjectModel would break entity↔class resolution.
        let model = try XCTUnwrap(IAMCoreDataManager.managedObjectModel)
        container = NSPersistentContainer(name: "InAppMessaging", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]

        let expectation = expectation(description: "store loaded")
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        XCTAssertNil(loadError)
        context = container.viewContext

        userDefaults = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        userDefaults.removePersistentDomain(forName: Self.suiteName)
        engine = IAMDisplayRulesEngine(userDefaults: userDefaults)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: Self.suiteName)
        container = nil
        context = nil
        engine = nil
        super.tearDown()
    }

    // MARK: - Builders

    private func makeMessage(id: String = "m1",
                             startDate: Date? = nil,
                             endDate: Date? = nil,
                             audienceJSON: String? = nil,
                             frequencyJSON: String? = nil) throws -> IAMMessage {
        let response = IAMMessageResponse(
            id: id,
            position: .center,
            htmlContent: "<html></html>",
            displayDuration: 0,
            shouldDismissOnTap: false,
            actions: [:],
            startDate: startDate,
            endDate: endDate,
            priority: 1,
            audience: nil,
            frequency: nil,
            trigger: IAMTriggerCondition(type: "custom", event: "test_event", parameters: nil)
        )
        let message = try IAMMessage.create(from: response, in: context)
        if let audienceJSON = audienceJSON {
            message.audience = Data(audienceJSON.utf8)
        }
        if let frequencyJSON = frequencyJSON {
            message.frequency = Data(frequencyJSON.utf8)
        }
        try context.save()
        return message
    }

    @discardableResult
    private func recordDisplay(for message: IAMMessage, secondsAgo: TimeInterval = 0) -> IAMDisplayRecord {
        let record = IAMDisplayRecord(context: context)
        record.id = UUID()
        record.displayDate = Date().addingTimeInterval(-secondsAgo)
        record.message = message
        try? context.save()
        return record
    }

    // MARK: - Date window (§3.4)

    func testMessageWithinDateWindowIsEligible() throws {
        let message = try makeMessage(startDate: Date(timeIntervalSinceNow: -3600),
                                      endDate: Date(timeIntervalSinceNow: 3600))
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testMessageBeforeStartDateIsNotEligible() throws {
        let message = try makeMessage(startDate: Date(timeIntervalSinceNow: 3600))
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testMessageAfterEndDateIsNotEligible() throws {
        let message = try makeMessage(endDate: Date(timeIntervalSinceNow: -3600))
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testNilStartDateIsUnboundedAtTheStart() throws {
        let message = try makeMessage(endDate: Date(timeIntervalSinceNow: 3600))
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testNilEndDateIsUnboundedAtTheEnd() throws {
        let message = try makeMessage(startDate: Date(timeIntervalSinceNow: -3600))
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testBothDatesNilMeansAlwaysWithinWindow() throws {
        let message = try makeMessage()
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    // MARK: - Frequency (§3.7)

    func testOneTimeNeverDisplayedIsEligible() throws {
        let message = try makeMessage(frequencyJSON: #"{"type":"one_time","count":1,"interval":0}"#)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testOneTimeDisplayedOnceIsNotEligible() throws {
        let message = try makeMessage(frequencyJSON: #"{"type":"one_time","count":1,"interval":0}"#)
        recordDisplay(for: message)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testLegacyHyphenatedOneTimeStoredByOlderBuildDisplayedOnceIsNotEligible() throws {
        // Older iOS builds persisted the hyphenated raw value; stored JSON must stay readable.
        let message = try makeMessage(frequencyJSON: #"{"type":"one-time","count":1,"interval":0}"#)
        recordDisplay(for: message)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testCappedCount3WithZeroDisplaysIsEligible() throws {
        let message = try makeMessage(frequencyJSON: #"{"type":"capped","count":3,"interval":0}"#)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testCappedCount3WithTwoDisplaysIsEligible() throws {
        let message = try makeMessage(frequencyJSON: #"{"type":"capped","count":3,"interval":0}"#)
        recordDisplay(for: message, secondsAgo: 100)
        recordDisplay(for: message, secondsAgo: 50)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testCappedCount3WithThreeDisplaysIsNotEligible() throws {
        let message = try makeMessage(frequencyJSON: #"{"type":"capped","count":3,"interval":0}"#)
        recordDisplay(for: message, secondsAgo: 100)
        recordDisplay(for: message, secondsAgo: 50)
        recordDisplay(for: message, secondsAgo: 10)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testCappedWithMissingCountFailsClosed() throws {
        // Inverted by C5. `count` is required for `capped`, and the old
        // Int.MAX_VALUE-style fallback made a campaign that explicitly asked to be
        // capped UNLIMITED — failing open in the one place the author asked for a
        // limit.
        let message = try makeMessage(frequencyJSON: #"{"type":"capped","interval":0}"#)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testCappedIntervalNotMetIsNotEligible() throws {
        let message = try makeMessage(frequencyJSON: #"{"type":"capped","count":5,"interval":60}"#)
        recordDisplay(for: message, secondsAgo: 5)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testRecurringInterval10sWithLastDisplay5sAgoIsNotEligible() throws {
        let message = try makeMessage(frequencyJSON: #"{"type":"recurring","count":-1,"interval":10}"#)
        recordDisplay(for: message, secondsAgo: 5)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testRecurringInterval10sWithLastDisplay15sAgoIsEligible() throws {
        let message = try makeMessage(frequencyJSON: #"{"type":"recurring","count":-1,"interval":10}"#)
        recordDisplay(for: message, secondsAgo: 15)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testRecurringIntervalZeroIsAlwaysEligible() throws {
        let message = try makeMessage(frequencyJSON: #"{"type":"recurring","count":-1,"interval":0}"#)
        recordDisplay(for: message, secondsAgo: 1)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testRecurringWithMissingIntervalFailsClosed() throws {
        // Inverted by C5. `interval` is required for `recurring` — it is the only
        // rule that type has — so an absent one means the rule cannot be applied.
        // An explicit 0 stays legal (see testRecurringIntervalZeroIsAlwaysEligible).
        let message = try makeMessage(frequencyJSON: #"{"type":"recurring"}"#)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    // MARK: - Frequency, C5: count and interval together

    func testCappedWithinCountButInsideTheIntervalIsSuppressed() throws {
        // "Up to 3 times, at most once every 24h" is TWO constraints. Enforcing only
        // the count let all 3 displays fire back-to-back in one session.
        let message = try makeMessage(frequencyJSON: #"{"type":"capped","count":3,"interval":86400}"#)
        recordDisplay(for: message, secondsAgo: 60)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testCappedWithinCountPastTheIntervalIsShown() throws {
        let message = try makeMessage(frequencyJSON: #"{"type":"capped","count":3,"interval":3600}"#)
        recordDisplay(for: message, secondsAgo: 7200)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testCappedAtTheExactIntervalBoundaryIsShown() throws {
        let message = try makeMessage(frequencyJSON: #"{"type":"capped","count":3,"interval":60}"#)
        recordDisplay(for: message, secondsAgo: 60)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testCappedAtTheCountLimitStaysSuppressedEvenPastTheInterval() throws {
        // The cap is checked first: at its limit, spacing cannot revive it.
        let message = try makeMessage(frequencyJSON: #"{"type":"capped","count":2,"interval":60}"#)
        recordDisplay(for: message, secondsAgo: 7200)
        recordDisplay(for: message, secondsAgo: 3600)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testCappedWithAbsentIntervalIsAPureCountCap() throws {
        let message = try makeMessage(frequencyJSON: #"{"type":"capped","count":3}"#)
        recordDisplay(for: message, secondsAgo: 1)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testCappedWithExplicitZeroIntervalIsAPureCountCap() throws {
        // An explicit 0 is a legitimate "no spacing" value, distinct from absent.
        let message = try makeMessage(frequencyJSON: #"{"type":"capped","count":3,"interval":0}"#)
        recordDisplay(for: message, secondsAgo: 1)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testCappedWithAnIntervalButNoPreviousDisplayIsShown() throws {
        let message = try makeMessage(frequencyJSON: #"{"type":"capped","count":3,"interval":86400}"#)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testRecurringIgnoresCount() throws {
        // Recurring means "repeat with a minimum gap" and has no total cap — the
        // dashboard authors no count for it. A campaign needing both is `capped`.
        let message = try makeMessage(frequencyJSON: #"{"type":"recurring","count":1,"interval":60}"#)
        recordDisplay(for: message, secondsAgo: 7200)
        recordDisplay(for: message, secondsAgo: 3600)
        recordDisplay(for: message, secondsAgo: 1800)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testOneTimeIgnoresTheInterval() throws {
        let message = try makeMessage(frequencyJSON: #"{"type":"one_time","interval":86400}"#)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
        recordDisplay(for: message, secondsAgo: 999_999)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testRecurringWithNoPreviousDisplayIsEligible() throws {
        let message = try makeMessage(frequencyJSON: #"{"type":"recurring","count":-1,"interval":3600}"#)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testMalformedFrequencyJSONFailsClosed() throws {
        let message = try makeMessage(frequencyJSON: "not json at all")
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testUnknownFrequencyTypeDefaultsToEligible() throws {
        let message = try makeMessage(frequencyJSON: #"{"type":"weekly","count":1,"interval":0}"#)
        recordDisplay(for: message, secondsAgo: 5)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testNoFrequencyDefaultsToEligible() throws {
        let message = try makeMessage()
        recordDisplay(for: message, secondsAgo: 5)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    // MARK: - Audience (§3.5)

    private func setAttribute(_ value: String, for field: String) {
        engine.setUserAttribute(value, for: field)
    }

    func testEqOperatorPassesWhenAttributeMatches() throws {
        setAttribute("premium", for: "plan")
        let message = try makeMessage(audienceJSON: #"[{"field":"plan","op":"eq","value":["premium"]}]"#)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testEqOperatorFailsWhenAttributeDiffers() throws {
        setAttribute("free", for: "plan")
        let message = try makeMessage(audienceJSON: #"[{"field":"plan","op":"eq","value":["premium"]}]"#)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testEqOperatorMatchesBuiltInPlatformAttribute() throws {
        let message = try makeMessage(audienceJSON: #"[{"field":"platform","op":"eq","value":["iOS"]}]"#)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testNeqOperatorPassesWhenAttributeDiffers() throws {
        setAttribute("free", for: "plan")
        let message = try makeMessage(audienceJSON: #"[{"field":"plan","op":"neq","value":["premium"]}]"#)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testNeqOperatorFailsWhenAttributeMatches() throws {
        setAttribute("premium", for: "plan")
        let message = try makeMessage(audienceJSON: #"[{"field":"plan","op":"neq","value":["premium"]}]"#)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testGtOperatorPassesWhenAttributeIsNumericallyGreater() throws {
        setAttribute("10", for: "visits")
        let message = try makeMessage(audienceJSON: #"[{"field":"visits","op":"gt","value":[5]}]"#)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testGtOperatorFailsWhenAttributeIsEqualOrLess() throws {
        setAttribute("5", for: "visits")
        let equalMessage = try makeMessage(id: "gt-eq",
                                           audienceJSON: #"[{"field":"visits","op":"gt","value":[5]}]"#)
        XCTAssertFalse(engine.isEligibleForDisplay(equalMessage))

        setAttribute("3", for: "visits")
        let lessMessage = try makeMessage(id: "gt-less",
                                          audienceJSON: #"[{"field":"visits","op":"gt","value":[5]}]"#)
        XCTAssertFalse(engine.isEligibleForDisplay(lessMessage))
    }

    func testGtOperatorFailsWhenAttributeIsNotNumeric() throws {
        setAttribute("many", for: "visits")
        let message = try makeMessage(audienceJSON: #"[{"field":"visits","op":"gt","value":[5]}]"#)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testLtOperatorPassesWhenAttributeIsNumericallyLess() throws {
        setAttribute("3", for: "visits")
        let message = try makeMessage(audienceJSON: #"[{"field":"visits","op":"lt","value":[5]}]"#)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testLtOperatorFailsWhenAttributeIsEqualOrGreater() throws {
        setAttribute("5", for: "visits")
        let message = try makeMessage(audienceJSON: #"[{"field":"visits","op":"lt","value":[5]}]"#)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testInOperatorPassesWhenAttributeIsInTheList() throws {
        setAttribute("gold", for: "tier")
        let message = try makeMessage(audienceJSON: #"[{"field":"tier","op":"in","value":["gold","platinum"]}]"#)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testInOperatorFailsWhenAttributeIsNotInTheList() throws {
        setAttribute("silver", for: "tier")
        let message = try makeMessage(audienceJSON: #"[{"field":"tier","op":"in","value":["gold","platinum"]}]"#)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testNinOperatorPassesWhenAttributeIsNotInTheList() throws {
        setAttribute("silver", for: "tier")
        let message = try makeMessage(audienceJSON: #"[{"field":"tier","op":"nin","value":["gold","platinum"]}]"#)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testNinOperatorFailsWhenAttributeIsInTheList() throws {
        setAttribute("gold", for: "tier")
        let message = try makeMessage(audienceJSON: #"[{"field":"tier","op":"nin","value":["gold","platinum"]}]"#)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testContainsOperatorPassesWhenAttributeContainsTheValue() throws {
        setAttribute("hello world", for: "greeting")
        let message = try makeMessage(audienceJSON: #"[{"field":"greeting","op":"contains","value":["world"]}]"#)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testContainsOperatorFailsWhenAttributeDoesNotContainTheValue() throws {
        setAttribute("hello world", for: "greeting")
        let message = try makeMessage(audienceJSON: #"[{"field":"greeting","op":"contains","value":["mars"]}]"#)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testScalarAudienceValueIsAcceptedForBackwardCompatibility() throws {
        setAttribute("premium", for: "plan")
        let message = try makeMessage(audienceJSON: #"[{"field":"plan","op":"eq","value":"premium"}]"#)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testMultipleConditionsAllPassingIsEligible() throws {
        setAttribute("premium", for: "plan")
        let message = try makeMessage(audienceJSON: """
        [{"field":"plan","op":"eq","value":["premium"]},
         {"field":"platform","op":"eq","value":["iOS"]}]
        """)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testMultipleConditionsAreANDedSoOneFailureKillsEligibility() throws {
        setAttribute("premium", for: "plan")
        let message = try makeMessage(audienceJSON: """
        [{"field":"plan","op":"eq","value":["premium"]},
         {"field":"platform","op":"eq","value":["Android"]}]
        """)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testMissingUserAttributeMakesMessageNotEligibleForPositiveOperators() throws {
        for op in ["eq", "gt", "lt", "in", "contains"] {
            let message = try makeMessage(id: "missing-\(op)",
                                          audienceJSON: #"[{"field":"nonexistent","op":"\#(op)","value":["x"]}]"#)
            XCTAssertFalse(engine.isEligibleForDisplay(message), "op \(op) should fail when attribute is missing")
        }
    }

    func testNeqOperatorPassesWhenAttributeIsMissing() throws {
        // §3.5: an absent value is trivially "not equal to" the target,
        // e.g. `country neq US` reaches users whose country is unknown.
        let message = try makeMessage(audienceJSON: #"[{"field":"nonexistent","op":"neq","value":["US"]}]"#)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testNinOperatorPassesWhenAttributeIsMissing() throws {
        let message = try makeMessage(audienceJSON: #"[{"field":"nonexistent","op":"nin","value":["US"]}]"#)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testNoAudienceIsEligibleForEveryone() throws {
        let message = try makeMessage()
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testEmptyAudienceArrayIsEligibleForEveryone() throws {
        let message = try makeMessage(audienceJSON: "[]")
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }

    func testMalformedAudienceJSONMakesMessageNotEligible() throws {
        let message = try makeMessage(audienceJSON: "not json at all")
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testUnknownAudienceOperatorMakesMessageNotEligible() throws {
        setAttribute("premium", for: "plan")
        let message = try makeMessage(audienceJSON: #"[{"field":"plan","op":"matches_regex","value":["p.*"]}]"#)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testRemovedUserAttributeNoLongerSatisfiesCondition() throws {
        setAttribute("premium", for: "plan")
        engine.removeUserAttribute(for: "plan")
        let message = try makeMessage(audienceJSON: #"[{"field":"plan","op":"eq","value":["premium"]}]"#)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    // MARK: - Combined rules (§1.2)

    func testValidDatesAndFrequencyOkButAudienceFailingIsNotEligible() throws {
        setAttribute("free", for: "plan")
        let message = try makeMessage(startDate: Date(timeIntervalSinceNow: -3600),
                                      endDate: Date(timeIntervalSinceNow: 3600),
                                      audienceJSON: #"[{"field":"plan","op":"eq","value":["premium"]}]"#,
                                      frequencyJSON: #"{"type":"recurring","count":-1,"interval":0}"#)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testValidDatesAndAudienceOkButFrequencyExceededIsNotEligible() throws {
        setAttribute("premium", for: "plan")
        let message = try makeMessage(startDate: Date(timeIntervalSinceNow: -3600),
                                      endDate: Date(timeIntervalSinceNow: 3600),
                                      audienceJSON: #"[{"field":"plan","op":"eq","value":["premium"]}]"#,
                                      frequencyJSON: #"{"type":"one_time","count":1,"interval":0}"#)
        recordDisplay(for: message)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testExpiredDateWindowIsNotEligibleEvenWhenFrequencyAndAudiencePass() throws {
        setAttribute("premium", for: "plan")
        let message = try makeMessage(endDate: Date(timeIntervalSinceNow: -3600),
                                      audienceJSON: #"[{"field":"plan","op":"eq","value":["premium"]}]"#,
                                      frequencyJSON: #"{"type":"recurring","count":-1,"interval":0}"#)
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testAllChecksPassingMakesMessageEligible() throws {
        setAttribute("premium", for: "plan")
        let message = try makeMessage(startDate: Date(timeIntervalSinceNow: -3600),
                                      endDate: Date(timeIntervalSinceNow: 3600),
                                      audienceJSON: #"[{"field":"plan","op":"eq","value":["premium"]}]"#,
                                      frequencyJSON: #"{"type":"recurring","count":-1,"interval":0}"#)
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }
}
