import XCTest
import CoreData
@testable import PushEngage

/// Trigger condition matching (C2 of the Android design-changes doc).
///
/// The campaign states **requirements** and the app supplies the **data**:
/// parameters no condition names are ignored, and absent or empty `conditions`
/// match any occurrence of the event. This reverses the previous rule, which
/// required every parameter the app sent to be declared on the campaign — a rule
/// that cannot express `cart_value > 100` at all.
final class IAMTriggerMatcherTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let model = try XCTUnwrap(IAMCoreDataManager.managedObjectModel)
        container = NSPersistentContainer(name: "InAppMessaging", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        let expectation = expectation(description: "store loaded")
        container.loadPersistentStores { _, error in
            XCTAssertNil(error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        context = container.viewContext
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Builders

    private var counter = 0

    /// A campaign whose stored trigger JSON is written verbatim, so both the
    /// current `conditions` shape and the legacy `parameters` map can be exercised.
    private func makeMessage(triggerJSON: String) throws -> IAMMessage {
        counter += 1
        let response = IAMMessageResponse(
            id: "trigger-\(counter)",
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
            trigger: IAMTriggerCondition(type: "custom", event: "evt")
        )
        let message = try IAMMessage.create(from: response, in: context)
        message.trigger = Data(triggerJSON.utf8)
        try context.save()
        return message
    }

    private func matches(_ triggerJSON: String, _ parameters: [String: Any]? = nil) throws -> Bool {
        IAMTriggerMatcher.matches(message: try makeMessage(triggerJSON: triggerJSON),
                                  parameters: parameters)
    }

    // MARK: - No requirements

    func testTriggerWithNoConditionsMatchesAnyOccurrence() throws {
        XCTAssertTrue(try matches(#"{"type":"custom","event":"evt"}"#))
    }

    func testAParameterlessCampaignUsedToBeSkippedWhenTheCallCarriedParameters() throws {
        // Behaviour change, kept in the name so the suite records it: the old rule
        // dropped a campaign with no parameters as soon as the call carried any.
        XCTAssertTrue(try matches(#"{"type":"custom","event":"evt"}"#, ["cart_value": 100]))
    }

    func testEmptyConditionsArrayMatchesAnyOccurrence() throws {
        XCTAssertTrue(try matches(#"{"type":"custom","event":"evt","conditions":[]}"#,
                                  ["anything": "goes"]))
    }

    // MARK: - Requirements

    func testEveryConditionMustHoldByDefault() throws {
        let trigger = """
        {"type":"custom","event":"evt","conditions":[
          {"field":"cart_value","type":"number","op":"gte","value":["100"]},
          {"field":"currency","type":"string","op":"eq","value":["USD"]}]}
        """
        XCTAssertTrue(try matches(trigger, ["cart_value": 150, "currency": "USD"]))
        XCTAssertFalse(try matches(trigger, ["cart_value": 150, "currency": "EUR"]))
    }

    func testMatchAnyNeedsOnlyOneCondition() throws {
        let trigger = """
        {"type":"custom","event":"evt","match":"any","conditions":[
          {"field":"currency","op":"eq","value":["USD"]},
          {"field":"currency","op":"eq","value":["EUR"]}]}
        """
        XCTAssertTrue(try matches(trigger, ["currency": "EUR"]))
        XCTAssertFalse(try matches(trigger, ["currency": "GBP"]))
    }

    func testAbsentMatchDefaultsToAll() throws {
        let trigger = """
        {"type":"custom","event":"evt","conditions":[
          {"field":"a","op":"eq","value":["1"]},
          {"field":"b","op":"eq","value":["2"]}]}
        """
        XCTAssertFalse(try matches(trigger, ["a": "1"]))
        XCTAssertTrue(try matches(trigger, ["a": "1", "b": "2"]))
    }

    func testUnknownMatchModeFailsClosed() throws {
        XCTAssertFalse(try matches("""
        {"type":"custom","event":"evt","match":"most","conditions":[
          {"field":"a","op":"eq","value":["1"]}]}
        """, ["a": "1"]))
    }

    func testExtraParametersTheCampaignDoesNotNameAreIgnored() throws {
        XCTAssertTrue(try matches("""
        {"type":"custom","event":"evt","conditions":[{"field":"a","op":"eq","value":["1"]}]}
        """, ["a": "1", "unrelated": "x", "another": 42]))
    }

    func testConditionsApplyEvenWhenTheCallCarriesNoParameters() throws {
        // A campaign with conditions must satisfy them even when nothing is passed.
        XCTAssertFalse(try matches("""
        {"type":"custom","event":"evt","conditions":[{"field":"a","op":"eq","value":["1"]}]}
        """, nil))
    }

    // MARK: - Missing parameters

    func testAConditionOnAnUnsentParameterFailsForPositiveOperators() throws {
        for op in ["eq", "gt", "lt", "gte", "lte", "in", "contains"] {
            XCTAssertFalse(try matches("""
            {"type":"custom","event":"evt","conditions":[
              {"field":"missing","op":"\(op)","value":["1"]}]}
            """, ["other": "x"]), "op \(op) should fail when the parameter was not sent")
        }
    }

    func testAConditionOnAnUnsentParameterPassesForNegativeOperators() throws {
        for op in ["neq", "nin"] {
            XCTAssertTrue(try matches("""
            {"type":"custom","event":"evt","conditions":[
              {"field":"missing","op":"\(op)","value":["1"]}]}
            """, ["other": "x"]), "op \(op) should pass when the parameter was not sent")
        }
    }

    // MARK: - Types (the erasure bug this fixes)

    func testADoubleParameterMatchesAWholeNumberTarget() throws {
        // triggerIAMEvent stringifies its values, so a Double 100 arrived
        // as "100.0" and never equalled "100". A declared type parses both sides.
        XCTAssertTrue(try matches("""
        {"type":"custom","event":"evt","conditions":[
          {"field":"cart_value","type":"number","op":"eq","value":["100"]}]}
        """, ["cart_value": 100.0]))
    }

    func testNumericOrderingIsNotLexical() throws {
        // "9" > "100" is true as text and false as a number.
        XCTAssertFalse(try matches("""
        {"type":"custom","event":"evt","conditions":[
          {"field":"qty","type":"number","op":"gt","value":["100"]}]}
        """, ["qty": 9]))
        XCTAssertTrue(try matches("""
        {"type":"custom","event":"evt","conditions":[
          {"field":"qty","type":"number","op":"lt","value":["100"]}]}
        """, ["qty": 9]))
    }

    func testAbsentTypeIsTreatedAsString() throws {
        XCTAssertTrue(try matches("""
        {"type":"custom","event":"evt","conditions":[
          {"field":"currency","op":"eq","value":["USD"]}]}
        """, ["currency": "USD"]))
    }

    func testBooleanParametersAreComparedStrictly() throws {
        XCTAssertTrue(try matches("""
        {"type":"custom","event":"evt","conditions":[
          {"field":"final","type":"boolean","op":"eq","value":["true"]}]}
        """, ["final": true]))
        XCTAssertFalse(try matches("""
        {"type":"custom","event":"evt","conditions":[
          {"field":"final","type":"boolean","op":"eq","value":["1"]}]}
        """, ["final": true]))
    }

    func testMembershipAndSubstringOperatorsWorkOnParameters() throws {
        XCTAssertTrue(try matches("""
        {"type":"custom","event":"evt","conditions":[
          {"field":"currency","op":"in","value":["USD","EUR"]}]}
        """, ["currency": "EUR"]))
        XCTAssertTrue(try matches("""
        {"type":"custom","event":"evt","conditions":[
          {"field":"sku","op":"contains","value":["-XL"]}]}
        """, ["sku": "shirt-XL"]))
    }

    func testVersionTypedParametersCompareComponentWise() throws {
        XCTAssertTrue(try matches("""
        {"type":"custom","event":"evt","conditions":[
          {"field":"app","type":"version","op":"gt","value":["2.9.0"]}]}
        """, ["app": "2.10.0"]))
    }

    func testSegmentsAreNotATriggerVocabulary() throws {
        // A trigger occurrence carries no segments, so such a condition never holds
        // rather than falling through to the subscriber's segments.
        XCTAssertFalse(try matches("""
        {"type":"custom","event":"evt","conditions":[
          {"field":"segments","op":"includes","value":["vip"]}]}
        """, ["segments": "vip"]))
    }

    func testSegmentsExcludesInATriggerIsRefusedRatherThanVacuouslyTrue() throws {
        // Segment membership is unknown in a trigger, so `excludes` must not pass on
        // an empty set — under `any` that would short-circuit past real conditions.
        XCTAssertFalse(try matches("""
        {"type":"custom","event":"evt","conditions":[
          {"field":"segments","op":"excludes","value":["vip"]}]}
        """, [:]))
        XCTAssertFalse(try matches("""
        {"type":"custom","event":"evt","match":"any","conditions":[
          {"field":"segments","op":"excludes","value":["vip"]},
          {"field":"cart_value","type":"number","op":"gte","value":["100"]}]}
        """, ["cart_value": "50"]))
    }

    func testNonArrayConditionsFailsClosedRatherThanMatchingEveryOccurrence() throws {
        // A single condition object not wrapped in an array is malformed, not
        // absent — falling through to "no conditions" would match every occurrence.
        XCTAssertFalse(try matches("""
        {"type":"custom","event":"evt","conditions":
          {"field":"cart_value","type":"number","op":"gte","value":["100"]}}
        """, ["cart_value": "150"]))
        XCTAssertFalse(try matches("""
        {"type":"custom","event":"evt","conditions":"cart_value>100"}
        """, ["cart_value": "150"]))
    }

    func testAbsentAndNullConditionsStillMatchAnyOccurrence() throws {
        XCTAssertTrue(try matches(#"{"type":"custom","event":"evt"}"#, ["any": "thing"]))
        XCTAssertTrue(try matches(#"{"type":"custom","event":"evt","conditions":null}"#, [:]))
        XCTAssertTrue(try matches(#"{"type":"custom","event":"evt","conditions":[]}"#, [:]))
    }

    // MARK: - Legacy parameters map

    func testLegacyParametersMapStillMatchesAsExactStringEquality() throws {
        // Campaigns stored by an earlier build remain in the store until the next
        // sync full-replaces them.
        XCTAssertTrue(try matches("""
        {"type":"custom","event":"evt","parameters":{"type":"banner"}}
        """, ["type": "banner"]))
    }

    func testLegacyParametersMapFailsOnADifferingValue() throws {
        XCTAssertFalse(try matches("""
        {"type":"custom","event":"evt","parameters":{"type":"banner"}}
        """, ["type": "modal"]))
    }

    func testLegacyParametersMapFailsWhenTheCallOmitsADeclaredKey() throws {
        XCTAssertFalse(try matches("""
        {"type":"custom","event":"evt","parameters":{"type":"banner","step":"1"}}
        """, ["type": "banner"]))
    }

    func testLegacyParametersMapIgnoresExtraCallParameters() throws {
        // Also a behaviour change: only the keys the campaign declares are checked.
        XCTAssertTrue(try matches("""
        {"type":"custom","event":"evt","parameters":{"type":"banner"}}
        """, ["type": "banner", "extra": "x"]))
    }

    func testEmptyLegacyParametersMapMatchesAnyOccurrence() throws {
        XCTAssertTrue(try matches("""
        {"type":"custom","event":"evt","parameters":{}}
        """, ["type": "banner"]))
    }

    func testConditionsWinOverALegacyParametersMapWhenBothArePresent() throws {
        // Nothing should send both, but if it does, the current shape decides.
        XCTAssertTrue(try matches("""
        {"type":"custom","event":"evt","parameters":{"type":"modal"},
         "conditions":[{"field":"type","op":"eq","value":["banner"]}]}
        """, ["type": "banner"]))
    }

    // MARK: - Malformed

    func testMalformedTriggerJSONFailsClosed() throws {
        XCTAssertFalse(try matches("not json at all", ["a": "1"]))
    }

    func testMissingTriggerDataFailsClosed() throws {
        let message = try makeMessage(triggerJSON: #"{"type":"custom","event":"evt"}"#)
        message.trigger = nil
        try context.save()
        XCTAssertFalse(IAMTriggerMatcher.matches(message: message, parameters: nil))
    }

    // MARK: - Filtering a list

    func testFilterKeepsOnlyCampaignsWhoseConditionsHold() throws {
        let matching = try makeMessage(triggerJSON: """
        {"type":"custom","event":"evt","conditions":[{"field":"type","op":"eq","value":["banner"]}]}
        """)
        let failing = try makeMessage(triggerJSON: """
        {"type":"custom","event":"evt","conditions":[{"field":"type","op":"eq","value":["modal"]}]}
        """)
        let unconditional = try makeMessage(triggerJSON: #"{"type":"custom","event":"evt"}"#)

        let kept = IAMTriggerMatcher.filter(messages: [matching, failing, unconditional],
                                           parameters: ["type": "banner"])
        XCTAssertEqual(kept.map { $0.id }, [matching.id, unconditional.id])
    }

    // MARK: - Stringification

    func testNonStringCallValuesAreComparedAsStrings() {
        let stringified = IAMTriggerMatcher.stringified(["step": 2, "ratio": 1.5, "final": true])
        XCTAssertEqual(stringified["step"], "2")
        XCTAssertEqual(stringified["ratio"], "1.5")
        // Booleans must not stringify as "1"/"0".
        XCTAssertEqual(stringified["final"], "true")
    }
}
