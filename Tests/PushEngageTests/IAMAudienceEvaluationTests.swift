import XCTest
import CoreData
@testable import PushEngage

/// Audience evaluation: the grouped `{match, groups}` shape, the four-type
/// system, the full operator set, the field catalogue, and subscriber-state
/// deferral.
///
/// Mirrors Android's IAMRulesEngineTest coverage for C1/C3/C4 of
/// docs/plans/2026-07-27-iam-dashboard-design-changes.md (in the Android repo).
/// Scalar/legacy-array behaviour that predates C1 stays in
/// IAMDisplayRulesEngineTests.
final class IAMAudienceEvaluationTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!
    private var userDefaults: UserDefaults!
    private var engine: IAMDisplayRulesEngine!

    private static let suiteName = "IAMAudienceEvaluationTests"

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

    private var messageCounter = 0

    private func makeMessage(_ audienceJSON: String?) throws -> IAMMessage {
        messageCounter += 1
        let response = IAMMessageResponse(
            id: "audience-\(messageCounter)",
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
            trigger: IAMTriggerCondition(type: "custom", event: "test_event")
        )
        let message = try IAMMessage.create(from: response, in: context)
        if let audienceJSON = audienceJSON {
            message.audience = Data(audienceJSON.utf8)
        }
        try context.save()
        return message
    }

    /// Whether a campaign with this audience is eligible. Dates and frequency
    /// are unset, so only the audience decides.
    private func matches(_ audienceJSON: String?) throws -> Bool {
        engine.isEligibleForDisplay(try makeMessage(audienceJSON))
    }

    // MARK: - C1: grouped shape

    func testSingleGroupWithEveryConditionPassingIsEligible() throws {
        engine.setUserAttribute("gold", for: "plan")
        engine.setUserAttribute("500", for: "ltv")
        XCTAssertTrue(try matches("""
        {"match":"any","groups":[{"match":"all","conditions":[
          {"field":"plan","type":"string","op":"eq","value":["gold"]},
          {"field":"ltv","type":"number","op":"gte","value":["500"]}]}]}
        """))
    }

    func testSingleGroupWithOneFailingConditionIsNotEligible() throws {
        engine.setUserAttribute("gold", for: "plan")
        engine.setUserAttribute("100", for: "ltv")
        XCTAssertFalse(try matches("""
        {"match":"any","groups":[{"match":"all","conditions":[
          {"field":"plan","type":"string","op":"eq","value":["gold"]},
          {"field":"ltv","type":"number","op":"gte","value":["500"]}]}]}
        """))
    }

    func testOrAcrossGroupsPassesOnTheSecondGroupAlone() throws {
        // First group cannot match; the campaign is eligible purely on the second.
        engine.setUserAttribute("gold", for: "plan")
        XCTAssertTrue(try matches("""
        {"match":"any","groups":[
          {"match":"all","conditions":[{"field":"plan","op":"eq","value":["silver"]}]},
          {"match":"all","conditions":[{"field":"plan","op":"eq","value":["gold"]}]}]}
        """))
    }

    func testOrAcrossGroupsFailsWhenNoGroupMatches() throws {
        engine.setUserAttribute("bronze", for: "plan")
        XCTAssertFalse(try matches("""
        {"match":"any","groups":[
          {"match":"all","conditions":[{"field":"plan","op":"eq","value":["silver"]}]},
          {"match":"all","conditions":[{"field":"plan","op":"eq","value":["gold"]}]}]}
        """))
    }

    func testAllAcrossGroupsRequiresEveryGroupToMatch() throws {
        engine.setUserAttribute("gold", for: "plan")
        engine.setUserAttribute("IN", for: "device_region")
        XCTAssertFalse(try matches("""
        {"match":"all","groups":[
          {"match":"all","conditions":[{"field":"plan","op":"eq","value":["gold"]}]},
          {"match":"all","conditions":[{"field":"device_region","op":"eq","value":["US"]}]}]}
        """))
    }

    func testAllAcrossGroupsPassesWhenEveryGroupMatches() throws {
        engine.setUserAttribute("gold", for: "plan")
        engine.setUserAttribute("US", for: "device_region")
        XCTAssertTrue(try matches("""
        {"match":"all","groups":[
          {"match":"all","conditions":[{"field":"plan","op":"eq","value":["gold"]}]},
          {"match":"all","conditions":[{"field":"device_region","op":"eq","value":["US"]}]}]}
        """))
    }

    func testAnyWithinAGroupIsSupported() throws {
        // `any` at the group level is CNF — free to support, since the fold is
        // the same code at both levels.
        engine.setUserAttribute("bronze", for: "plan")
        engine.setUserAttribute("US", for: "device_region")
        XCTAssertTrue(try matches("""
        {"match":"all","groups":[{"match":"any","conditions":[
          {"field":"plan","op":"eq","value":["gold"]},
          {"field":"device_region","op":"eq","value":["US"]}]}]}
        """))
    }

    func testAnyWithinAGroupFailsWhenNoConditionHolds() throws {
        engine.setUserAttribute("bronze", for: "plan")
        engine.setUserAttribute("IN", for: "device_region")
        XCTAssertFalse(try matches("""
        {"match":"all","groups":[{"match":"any","conditions":[
          {"field":"plan","op":"eq","value":["gold"]},
          {"field":"device_region","op":"eq","value":["US"]}]}]}
        """))
    }

    func testAbsentAudienceMeansEveryone() throws {
        XCTAssertTrue(try matches(nil))
    }

    func testAudienceObjectWithNoGroupsKeyMeansEveryone() throws {
        XCTAssertTrue(try matches(#"{"match":"any"}"#))
    }

    func testAudienceObjectWithEmptyGroupsArrayMeansEveryone() throws {
        XCTAssertTrue(try matches(#"{"match":"any","groups":[]}"#))
    }

    func testNullAudienceLiteralMeansEveryone() throws {
        XCTAssertTrue(try matches("null"))
    }

    func testEmptyGroupIsSkippedRatherThanVacuouslyTrue() throws {
        // An empty AND is vacuously true, so treating it literally would let one
        // stray empty group open the campaign to everybody. Skipping it leaves
        // the failing group as the only evaluable one.
        engine.setUserAttribute("bronze", for: "plan")
        XCTAssertFalse(try matches("""
        {"match":"any","groups":[
          {"match":"all","conditions":[]},
          {"match":"all","conditions":[{"field":"plan","op":"eq","value":["gold"]}]}]}
        """))
    }

    func testEmptyGroupIsSkippedButAMatchingGroupStillWins() throws {
        engine.setUserAttribute("gold", for: "plan")
        XCTAssertTrue(try matches("""
        {"match":"any","groups":[
          {"match":"all","conditions":[]},
          {"match":"all","conditions":[{"field":"plan","op":"eq","value":["gold"]}]}]}
        """))
    }

    func testGroupWithNoConditionsKeyIsSkipped() throws {
        engine.setUserAttribute("bronze", for: "plan")
        XCTAssertFalse(try matches("""
        {"match":"any","groups":[
          {"match":"all"},
          {"match":"all","conditions":[{"field":"plan","op":"eq","value":["gold"]}]}]}
        """))
    }

    func testEveryGroupEmptyFailsClosed() throws {
        // Criteria were present but none usable — fail closed rather than
        // treating it as "no criteria".
        XCTAssertFalse(try matches("""
        {"match":"any","groups":[{"match":"all","conditions":[]},{"match":"all","conditions":[]}]}
        """))
    }

    func testUnknownTopLevelMatchModeFailsClosed() throws {
        engine.setUserAttribute("gold", for: "plan")
        XCTAssertFalse(try matches("""
        {"match":"most","groups":[{"match":"all","conditions":[
          {"field":"plan","op":"eq","value":["gold"]}]}]}
        """))
    }

    func testUnknownGroupMatchModeFailsClosed() throws {
        engine.setUserAttribute("gold", for: "plan")
        XCTAssertFalse(try matches("""
        {"match":"any","groups":[{"match":"some","conditions":[
          {"field":"plan","op":"eq","value":["gold"]}]}]}
        """))
    }

    func testMatchModesAreCaseInsensitive() throws {
        engine.setUserAttribute("gold", for: "plan")
        XCTAssertTrue(try matches("""
        {"match":"ANY","groups":[{"match":"All","conditions":[
          {"field":"plan","op":"eq","value":["gold"]}]}]}
        """))
    }

    func testAbsentMatchDefaultsToAnyAtTheTopAndAllInAGroup() throws {
        engine.setUserAttribute("gold", for: "plan")
        engine.setUserAttribute("US", for: "device_region")
        // Group defaults to `all`, so both conditions must hold.
        XCTAssertTrue(try matches("""
        {"groups":[{"conditions":[
          {"field":"plan","op":"eq","value":["gold"]},
          {"field":"device_region","op":"eq","value":["US"]}]}]}
        """))
        XCTAssertFalse(try matches("""
        {"groups":[{"conditions":[
          {"field":"plan","op":"eq","value":["gold"]},
          {"field":"device_region","op":"eq","value":["IN"]}]}]}
        """))
    }

    func testExplicitNullMatchIsTreatedAsAbsentNotUnknown() throws {
        // Emitting explicit nulls for absent optional fields is common serializer
        // behaviour; it must not be read as an unrecognised mode and fail closed.
        engine.setUserAttribute("gold", for: "plan")
        XCTAssertTrue(try matches("""
        {"match":null,"groups":[{"match":null,"conditions":[
          {"field":"plan","op":"eq","value":["gold"]}]}]}
        """))
    }

    func testMalformedGroupEntryFailsClosed() throws {
        XCTAssertFalse(try matches(#"{"match":"any","groups":[42]}"#))
    }

    func testIndexKeyedGroupsObjectFailsClosedRatherThanOpeningReach() throws {
        // A serializer that re-encodes an array as an index-keyed object is a
        // malformed audience, not an absent one. The group inside would match, so
        // reading it as "no criteria" would show a targeted campaign to everybody.
        engine.setUserAttribute("gold", for: "plan")
        XCTAssertFalse(try matches("""
        {"match":"any","groups":{"0":{"match":"all","conditions":[
          {"field":"plan","op":"eq","value":["gold"]}]}}}
        """))
    }

    func testScalarGroupsValueFailsClosed() throws {
        XCTAssertFalse(try matches(#"{"match":"any","groups":"all-users"}"#))
        XCTAssertFalse(try matches(#"{"match":"any","groups":7}"#))
    }

    func testGroupsThatCannotBeReadReportNoFieldsRatherThanAnEmptySet() throws {
        // nil distinguishes "unreadable" from "no criteria" for the evaluation log,
        // so a malformed audience is not reported as an unconditional one.
        let malformed = Data(#"{"match":"any","groups":{"0":{"conditions":[]}}}"#.utf8)
        XCTAssertNil(IAMConditionEvaluator.audienceFields(malformed))
    }

    func testMalformedConditionEntryFailsClosed() throws {
        XCTAssertFalse(try matches("""
        {"match":"any","groups":[{"match":"all","conditions":["not-an-object"]}]}
        """))
    }

    func testConditionMissingFieldFailsClosed() throws {
        XCTAssertFalse(try matches("""
        {"match":"any","groups":[{"match":"all","conditions":[{"op":"eq","value":["gold"]}]}]}
        """))
    }

    func testConditionMissingOperatorFailsClosed() throws {
        engine.setUserAttribute("gold", for: "plan")
        XCTAssertFalse(try matches("""
        {"match":"any","groups":[{"match":"all","conditions":[{"field":"plan","value":["gold"]}]}]}
        """))
    }

    func testConditionMissingValueFailsClosed() throws {
        engine.setUserAttribute("gold", for: "plan")
        XCTAssertFalse(try matches("""
        {"match":"any","groups":[{"match":"all","conditions":[{"field":"plan","op":"eq"}]}]}
        """))
    }

    func testLegacyFlatArrayStillEvaluatesAsOneAndedGroup() throws {
        // Rows persisted by a previous build stay in the store until the next
        // sync full-replaces them; without this they would fail closed meanwhile.
        engine.setUserAttribute("gold", for: "plan")
        engine.setUserAttribute("US", for: "device_region")
        XCTAssertTrue(try matches("""
        [{"field":"plan","op":"eq","value":["gold"]},
         {"field":"device_region","op":"eq","value":["US"]}]
        """))
        XCTAssertFalse(try matches("""
        [{"field":"plan","op":"eq","value":["gold"]},
         {"field":"device_region","op":"eq","value":["IN"]}]
        """))
    }

    func testGroupsBeyondTheAuthoringCapStillEvaluate() throws {
        // Authoring caps groups × conditions, but the SDK must not fall over on a
        // larger payload even if the dashboard prevents it.
        engine.setUserAttribute("gold", for: "plan")
        let groups = (0..<40).map { index in
            """
            {"match":"all","conditions":[{"field":"plan","op":"eq","value":["tier-\(index)"]}]}
            """
        }.joined(separator: ",")
        XCTAssertFalse(try matches(#"{"match":"any","groups":[\#(groups)]}"#))
    }

    // MARK: - C3: version type

    func testVersionsCompareComponentWiseNotLexically() throws {
        // "14" > "8.1.0" component-wise, though "14" < "8" as text.
        engine.setUserAttribute("14", for: "os_version")
        XCTAssertTrue(try matches(#"[{"field":"os_version","op":"gt","value":["8.1.0"]}]"#))
    }

    func testVersionMissingComponentsCountAsZero() throws {
        engine.setUserAttribute("8.1", for: "os_version")
        XCTAssertTrue(try matches(#"[{"field":"os_version","op":"eq","value":["8.1.0"]}]"#))
    }

    func testVersionPreReleaseSuffixComparesOnItsNumericCore() throws {
        engine.setUserAttribute("1.0.0-beta", for: "app_version")
        XCTAssertTrue(try matches(#"[{"field":"app_version","op":"eq","value":["1.0.0"]}]"#))
    }

    func testVersionBuildMetadataSuffixComparesOnItsNumericCore() throws {
        engine.setUserAttribute("2.1.0+build77", for: "app_version")
        XCTAssertTrue(try matches(#"[{"field":"app_version","op":"gte","value":["2.1.0"]}]"#))
    }

    func testVersionCodenameCannotBeOrderedAndFailsTheCondition() throws {
        // A preview codename is not orderable, so beta-OS users drop out of
        // `os_version >` campaigns rather than the comparison throwing.
        engine.setUserAttribute("VanillaIceCream", for: "os_version")
        XCTAssertFalse(try matches(#"[{"field":"os_version","op":"gt","value":["8"]}]"#))
        XCTAssertFalse(try matches(#"[{"field":"os_version","op":"lt","value":["8"]}]"#))
    }

    func testVersionContainsIsRefused() throws {
        // `contains` on a version matches 1/10/11/12/13/14/21 — sensible-looking
        // and nonsense.
        engine.setUserAttribute("14.1", for: "os_version")
        XCTAssertFalse(try matches(#"[{"field":"os_version","op":"contains","value":["1"]}]"#))
    }

    func testVersionMembershipComparesUnderTheVersionType() throws {
        engine.setUserAttribute("8.1", for: "os_version")
        XCTAssertTrue(try matches(#"[{"field":"os_version","op":"in","value":["8.1.0","9.0"]}]"#))
    }

    // MARK: - C3/C4: ordering operators

    func testGteIsInclusiveAtTheBoundary() throws {
        engine.setUserAttribute("500", for: "ltv")
        XCTAssertTrue(try matches(#"[{"field":"ltv","type":"number","op":"gte","value":["500"]}]"#))
    }

    func testLteIsInclusiveAtTheBoundary() throws {
        engine.setUserAttribute("500", for: "ltv")
        XCTAssertTrue(try matches(#"[{"field":"ltv","type":"number","op":"lte","value":["500"]}]"#))
    }

    func testGtIsStrictAtTheBoundary() throws {
        // The reason gte/lte are required: `> 12` wrongly includes nothing at 12
        // but also cannot express "12 and above".
        engine.setUserAttribute("500", for: "ltv")
        XCTAssertFalse(try matches(#"[{"field":"ltv","type":"number","op":"gt","value":["500"]}]"#))
    }

    func testGteFailsBelowTheBoundary() throws {
        engine.setUserAttribute("499", for: "ltv")
        XCTAssertFalse(try matches(#"[{"field":"ltv","type":"number","op":"gte","value":["500"]}]"#))
    }

    func testLteFailsAboveTheBoundary() throws {
        engine.setUserAttribute("501", for: "ltv")
        XCTAssertFalse(try matches(#"[{"field":"ltv","type":"number","op":"lte","value":["500"]}]"#))
    }

    func testNumericEqualityIgnoresFormatting() throws {
        engine.setUserAttribute("100", for: "ltv")
        XCTAssertTrue(try matches(#"[{"field":"ltv","type":"number","op":"eq","value":["100.0"]}]"#))
    }

    func testNotANumberCannotBeOrderedAndFailsTheCondition() throws {
        // "nan" parses as a Double but has no ordering, so every comparison against
        // it must be refused rather than answered.
        engine.setUserAttribute("nan", for: "ltv")
        XCTAssertFalse(try matches("""
        [{"field":"ltv","type":"number","op":"gte","value":["500"]}]
        """))
        XCTAssertFalse(try matches("""
        [{"field":"ltv","type":"number","op":"gt","value":["500"]}]
        """))
        XCTAssertFalse(try matches("""
        [{"field":"ltv","type":"number","op":"lt","value":["500"]}]
        """))
        XCTAssertFalse(try matches("""
        [{"field":"ltv","type":"number","op":"eq","value":["nan"]}]
        """))
    }

    func testNotANumberOnTheTargetSideAlsoFailsTheCondition() throws {
        engine.setUserAttribute("750", for: "ltv")
        XCTAssertFalse(try matches("""
        [{"field":"ltv","type":"number","op":"gte","value":["nan"]}]
        """))
    }

    func testLanguageResolvesToTheBareCodeNotTheRegionQualifiedForm() throws {
        // Android sends and the dashboard authors `en`; `Locale.preferredLanguages`
        // yields `en-US`, which could never match it. Pinned by shape rather than by
        // value, so the test does not depend on the simulator's locale.
        XCTAssertFalse(try matches(#"[{"field":"language","op":"contains","value":["-"]}]"#),
                       "language must not carry a region suffix")
        XCTAssertTrue(try matches(#"[{"field":"language","op":"contains","value":[""]}]"#),
                      "language must still resolve to something")
    }

    func testEqualityAgainstAMultiValueArrayComparesTheFirstEntryOnly() throws {
        // The contract sends single-value operators as a one-element array. `eq`
        // against several values is not any-of — `in` is the operator for that.
        engine.setUserAttribute("silver", for: "plan")
        XCTAssertFalse(try matches(#"[{"field":"plan","op":"eq","value":["gold","silver"]}]"#))
        engine.setUserAttribute("gold", for: "plan")
        XCTAssertTrue(try matches(#"[{"field":"plan","op":"eq","value":["gold","silver"]}]"#))
    }

    func testMembershipOperatorsRequireAnArrayAndFailClosedOnAScalar() throws {
        // `nin` is the dangerous half: without the array guard, "not contained in a
        // non-list" would answer true and pass everybody.
        engine.setUserAttribute("gold", for: "plan")
        XCTAssertFalse(try matches(#"[{"field":"plan","op":"in","value":"gold"}]"#))
        XCTAssertFalse(try matches(#"[{"field":"plan","op":"nin","value":"silver"}]"#))
    }

    func testOrderingIsRefusedOnADeclaredStringAttribute() throws {
        // Lexical order would answer a different question — "9" > "10" as text.
        engine.setUserAttribute("9", for: "code")
        XCTAssertFalse(try matches(#"[{"field":"code","type":"string","op":"gt","value":["10"]}]"#))
    }

    func testOrderingIsRefusedOnADeclaredBooleanAttribute() throws {
        engine.setUserAttribute("true", for: "is_premium")
        XCTAssertFalse(try matches(#"[{"field":"is_premium","type":"boolean","op":"gt","value":["false"]}]"#))
    }

    func testOrderingIsRefusedOnABuiltInStringField() throws {
        engine.setUserAttribute("US", for: "device_region")
        XCTAssertFalse(try matches(#"[{"field":"device_region","op":"gt","value":["AA"]}]"#))
    }

    func testOrderingIsInferredNumericallyForAnUndeclaredAttribute() throws {
        // Reaching for `gt` states the intent to order, and numeric order is
        // well-defined; lexical order never is.
        engine.setUserAttribute("10", for: "visits")
        XCTAssertTrue(try matches(#"[{"field":"visits","op":"gt","value":["9"]}]"#))
    }

    func testOrderingFallsBackToVersionForAnUndeclaredDottedAttribute() throws {
        engine.setUserAttribute("2.10.0", for: "last_seen")
        XCTAssertTrue(try matches(#"[{"field":"last_seen","op":"gt","value":["2.9.0"]}]"#))
    }

    func testOrderingFailsForAnUndeclaredNonNumericAttribute() throws {
        engine.setUserAttribute("many", for: "visits")
        XCTAssertFalse(try matches(#"[{"field":"visits","op":"gt","value":["9"]}]"#))
    }

    // MARK: - C3: catalogue is authoritative

    func testDeclaredTypeIsIgnoredOnABuiltInField() throws {
        // A payload must not be able to claim os_version is a string and turn
        // `>` into lexical comparison.
        engine.setUserAttribute("14", for: "os_version")
        XCTAssertTrue(try matches("""
        [{"field":"os_version","type":"string","op":"gt","value":["8.1.0"]}]
        """))
    }

    func testBooleanSpellingIsStrict() throws {
        engine.setUserAttribute("true", for: "notification_enabled")
        XCTAssertTrue(try matches(#"[{"field":"notification_enabled","op":"eq","value":["true"]}]"#))
        XCTAssertFalse(try matches(#"[{"field":"notification_enabled","op":"eq","value":["1"]}]"#))
        XCTAssertFalse(try matches(#"[{"field":"notification_enabled","op":"eq","value":["yes"]}]"#))
    }

    func testBooleanComparisonIsCaseInsensitive() throws {
        engine.setUserAttribute("TRUE", for: "notification_enabled")
        XCTAssertTrue(try matches(#"[{"field":"notification_enabled","op":"eq","value":["true"]}]"#))
    }

    func testNeqFailsClosedWhenTheValuesCannotBeCompared() throws {
        // If the pair can't be compared under `type`, we can't claim they differ.
        engine.setUserAttribute("abc", for: "ltv")
        XCTAssertFalse(try matches(#"[{"field":"ltv","type":"number","op":"neq","value":["100"]}]"#))
    }

    func testCoercionFailureFailsTheConditionInBothDirections() throws {
        engine.setUserAttribute("maybe", for: "is_premium")
        XCTAssertFalse(try matches(#"[{"field":"is_premium","type":"boolean","op":"eq","value":["true"]}]"#))
        XCTAssertFalse(try matches(#"[{"field":"is_premium","type":"boolean","op":"neq","value":["true"]}]"#))
    }

    func testAbsentTypeIsTreatedAsStringForEquality() throws {
        engine.setUserAttribute("gold", for: "plan")
        XCTAssertTrue(try matches(#"[{"field":"plan","op":"eq","value":["gold"]}]"#))
    }

    func testContainsIsRefusedForDeclaredNumbersAndBooleans() throws {
        engine.setUserAttribute("1500", for: "ltv")
        XCTAssertFalse(try matches(#"[{"field":"ltv","type":"number","op":"contains","value":["50"]}]"#))
        engine.setUserAttribute("true", for: "flag")
        XCTAssertFalse(try matches(#"[{"field":"flag","type":"boolean","op":"contains","value":["ru"]}]"#))
    }

    // MARK: - C3: field catalogue

    func testPlatformResolvesToTheCanonicalIOSValue() throws {
        XCTAssertTrue(try matches(#"[{"field":"platform","op":"eq","value":["iOS"]}]"#))
        XCTAssertFalse(try matches(#"[{"field":"platform","op":"eq","value":["ios"]}]"#))
        XCTAssertFalse(try matches(#"[{"field":"platform","op":"eq","value":["Android"]}]"#))
    }

    func testDeviceModelIsNoLongerResolvable() throws {
        // Opaque part numbers with OEM-varying casing are not reliably
        // authorable, so a condition on it fails closed rather than mis-targeting.
        XCTAssertFalse(try matches(#"[{"field":"device_model","op":"contains","value":[""]}]"#))
    }

    func testBareCountryIsNoLongerResolvable() throws {
        // The locale region and the backend's IP-derived country genuinely
        // disagree, so neither may own the bare name.
        XCTAssertFalse(try matches(#"[{"field":"country","op":"contains","value":[""]}]"#))
    }

    func testOsVersionResolvesFromTheDevice() throws {
        XCTAssertTrue(try matches(#"[{"field":"os_version","op":"gte","value":["1.0"]}]"#))
    }

    func testLanguageResolvesFromTheDevice() throws {
        XCTAssertTrue(try matches(#"[{"field":"language","op":"contains","value":[""]}]"#))
    }

    func testDeviceRegionResolvesFromTheDevice() throws {
        XCTAssertTrue(try matches(#"[{"field":"device_region","op":"contains","value":[""]}]"#))
    }

    func testTimezoneResolvesFromTheDevice() throws {
        XCTAssertTrue(try matches(#"[{"field":"timezone","op":"contains","value":[""]}]"#))
    }

    func testAppVersionResolvesFromTheHostBundle() throws {
        XCTAssertTrue(try matches(#"[{"field":"app_version","op":"gte","value":["0"]}]"#))
    }

    func testNotificationEnabledIsUnresolvableUntilItHasBeenCached() throws {
        // The authorization status is only available asynchronously, so it is
        // read during the app-open pass and cached for synchronous evaluation.
        XCTAssertFalse(try matches(#"[{"field":"notification_enabled","op":"in","value":["true","false"]}]"#))

        engine.cacheNotificationPermission(enabled: true)
        XCTAssertTrue(try matches(#"[{"field":"notification_enabled","op":"eq","value":["true"]}]"#))

        engine.cacheNotificationPermission(enabled: false)
        XCTAssertTrue(try matches(#"[{"field":"notification_enabled","op":"eq","value":["false"]}]"#))
    }

    // MARK: - C3 pass 2: segments

    func testSegmentsIncludesMatchesOnIntersection() throws {
        engine.applySubscriberState(segments: ["qatest", "vip"], attributes: [:], scalars: [:], identity: "hash-a")
        XCTAssertTrue(try matches(#"[{"field":"segments","op":"includes","value":["vip","whale"]}]"#))
    }

    func testSegmentsIncludesFailsWithoutIntersection() throws {
        engine.applySubscriberState(segments: ["qatest"], attributes: [:], scalars: [:], identity: "hash-a")
        XCTAssertFalse(try matches(#"[{"field":"segments","op":"includes","value":["no-such-segment"]}]"#))
    }

    func testSegmentsExcludesInvertsOnTheSameValue() throws {
        engine.applySubscriberState(segments: ["qatest"], attributes: [:], scalars: [:], identity: "hash-a")
        XCTAssertTrue(try matches(#"[{"field":"segments","op":"excludes","value":["no-such-segment"]}]"#))
        XCTAssertFalse(try matches(#"[{"field":"segments","op":"excludes","value":["qatest"]}]"#))
    }

    func testSegmentsRefusesScalarOperators() throws {
        // `segments eq "vip"` must fail rather than being quietly reinterpreted
        // as membership.
        engine.applySubscriberState(segments: ["vip"], attributes: [:], scalars: [:], identity: "hash-a")
        for op in ["eq", "neq", "in", "nin", "contains", "gt", "lt", "gte", "lte"] {
            XCTAssertFalse(try matches(#"[{"field":"segments","op":"\#(op)","value":["vip"]}]"#),
                           "segments must refuse the scalar operator \(op)")
        }
    }

    func testSegmentsIncludesRequiresAnArrayValue() throws {
        engine.applySubscriberState(segments: ["vip"], attributes: [:], scalars: [:], identity: "hash-a")
        XCTAssertFalse(try matches(#"[{"field":"segments","op":"includes","value":"vip"}]"#))
    }

    func testSegmentNamesAreMatchedExactly() throws {
        engine.applySubscriberState(segments: ["QAtest"], attributes: [:], scalars: [:], identity: "hash-a")
        XCTAssertFalse(try matches(#"[{"field":"segments","op":"includes","value":["qatest"]}]"#))
    }

    // MARK: - C3 pass 2: attr. namespace and scalars

    func testSubscriberAttributesResolveUnderTheAttrNamespace() throws {
        engine.applySubscriberState(segments: [], attributes: ["plan": "gold"], scalars: [:], identity: "hash-a")
        XCTAssertTrue(try matches(#"[{"field":"attr.plan","type":"string","op":"eq","value":["gold"]}]"#))
    }

    func testSubscriberAttributeCannotShadowABuiltInField() throws {
        // An attribute called `language` must not override the device locale.
        engine.applySubscriberState(segments: [], attributes: ["language": "klingon"], scalars: [:], identity: "hash-a")
        XCTAssertFalse(try matches(#"[{"field":"language","op":"eq","value":["klingon"]}]"#))
        XCTAssertTrue(try matches(#"[{"field":"attr.language","op":"eq","value":["klingon"]}]"#))
    }

    func testApplySubscriberStateReplacesRatherThanMerges() throws {
        // A removed segment or attribute must actually disappear, or a stale
        // value outlives the data it came from.
        engine.applySubscriberState(segments: ["vip"],
                                    attributes: ["plan": "gold", "ltv": "750"],
                                    scalars: ["city": "Santa Cruz"], identity: "hash-a")
        engine.applySubscriberState(segments: ["qatest"], attributes: ["plan": "silver"], scalars: [:], identity: "hash-a")

        XCTAssertTrue(try matches(#"[{"field":"attr.plan","op":"eq","value":["silver"]}]"#))
        XCTAssertFalse(try matches(#"[{"field":"attr.ltv","op":"eq","value":["750"]}]"#))
        XCTAssertFalse(try matches(#"[{"field":"city","op":"eq","value":["Santa Cruz"]}]"#))
        XCTAssertFalse(try matches(#"[{"field":"segments","op":"includes","value":["vip"]}]"#))
        XCTAssertTrue(try matches(#"[{"field":"segments","op":"includes","value":["qatest"]}]"#))
    }

    func testGeoScalarsResolveFromTheSubscriberRecord() throws {
        engine.applySubscriberState(segments: [],
                                    attributes: [:],
                                    scalars: ["city": "Santa Cruz",
                                              "state": "Maharashtra",
                                              "geo_country": "India"], identity: "hash-a")
        XCTAssertTrue(try matches(#"[{"field":"city","op":"eq","value":["Santa Cruz"]}]"#))
        XCTAssertTrue(try matches(#"[{"field":"state","op":"eq","value":["Maharashtra"]}]"#))
        XCTAssertTrue(try matches(#"[{"field":"geo_country","op":"eq","value":["India"]}]"#))
    }

    func testGeoCountryAndDeviceRegionCanDiffersimultaneously() throws {
        // Verified in production: locale US, IP-derived India, both at once.
        engine.setUserAttribute("US", for: "device_region")
        engine.applySubscriberState(segments: [], attributes: [:], scalars: ["geo_country": "India"], identity: "hash-a")
        XCTAssertTrue(try matches("""
        {"match":"all","groups":[{"match":"all","conditions":[
          {"field":"device_region","op":"eq","value":["US"]},
          {"field":"geo_country","op":"eq","value":["India"]}]}]}
        """))
    }

    func testHasUnsubscribedIsEvaluatedAsABoolean() throws {
        engine.applySubscriberState(segments: [], attributes: [:], scalars: ["has_unsubscribed": "false"], identity: "hash-a")
        XCTAssertTrue(try matches(#"[{"field":"has_unsubscribed","op":"eq","value":["false"]}]"#))
        XCTAssertFalse(try matches(#"[{"field":"has_unsubscribed","op":"eq","value":["0"]}]"#))
    }

    // MARK: - C3 pass 2: deferral

    func testSubscriberBackedAudienceIsDeferredBeforeAnyFetch() throws {
        for field in ["segments", "city", "state", "geo_country", "has_unsubscribed", "attr.plan"] {
            let json = field == "segments"
                ? #"[{"field":"segments","op":"includes","value":["vip"]}]"#
                : #"[{"field":"\#(field)","op":"eq","value":["x"]}]"#
            let message = try makeMessage(json)
            XCTAssertTrue(engine.requiresUnavailableSubscriberState(message),
                          "\(field) should defer until subscriber state has been fetched")
        }
    }

    func testDeviceOnlyAudienceIsNeverDeferred() throws {
        let message = try makeMessage(#"[{"field":"platform","op":"eq","value":["iOS"]}]"#)
        XCTAssertFalse(engine.requiresUnavailableSubscriberState(message))
    }

    func testNothingIsDeferredOnceSubscriberStateHasBeenApplied() throws {
        engine.applySubscriberState(segments: ["vip"], attributes: [:], scalars: [:], identity: "hash-a")
        let message = try makeMessage(#"[{"field":"segments","op":"includes","value":["vip"]}]"#)
        XCTAssertFalse(engine.requiresUnavailableSubscriberState(message))
    }

    func testAnEmptySubscriberFetchStillCountsAsStateHavingLoaded() throws {
        // A subscriber with no segments is a real answer, not a missing one.
        engine.applySubscriberState(segments: [], attributes: [:], scalars: [:], identity: "hash-a")
        let message = try makeMessage(#"[{"field":"segments","op":"includes","value":["vip"]}]"#)
        XCTAssertFalse(engine.requiresUnavailableSubscriberState(message))
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testDeferralScansGroupedAndLegacyShapesAlike() throws {
        let grouped = try makeMessage("""
        {"match":"any","groups":[
          {"match":"all","conditions":[{"field":"platform","op":"eq","value":["iOS"]}]},
          {"match":"all","conditions":[{"field":"segments","op":"includes","value":["vip"]}]}]}
        """)
        XCTAssertTrue(engine.requiresUnavailableSubscriberState(grouped))

        let legacy = try makeMessage(#"[{"field":"attr.ltv","op":"gte","value":["500"]}]"#)
        XCTAssertTrue(engine.requiresUnavailableSubscriberState(legacy))
    }

    func testMalformedAudienceIsNotDeferredBecauseItAlreadyFailsClosed() throws {
        let message = try makeMessage("not json at all")
        XCTAssertFalse(engine.requiresUnavailableSubscriberState(message))
        XCTAssertFalse(engine.isEligibleForDisplay(message))
    }

    func testAbsentAudienceIsNotDeferred() throws {
        let message = try makeMessage(nil)
        XCTAssertFalse(engine.requiresUnavailableSubscriberState(message))
    }

    func testDeferralRemovesTheOrGroupHazardItExistsFor() throws {
        // The hazard is real, not theoretical: a negative operator on data we
        // have never fetched passes, and with OR groups that single group is
        // enough to show the campaign to EVERYONE. If the defer check is ever
        // removed, this test fails and this comment says why.
        let message = try makeMessage("""
        {"match":"any","groups":[
          {"match":"all","conditions":[{"field":"geo_country","op":"neq","value":["India"]}]},
          {"match":"all","conditions":[{"field":"platform","op":"eq","value":["Android"]}]}]}
        """)
        XCTAssertTrue(engine.requiresUnavailableSubscriberState(message))
        // Evaluated directly it would have matched — which is the bug deferral avoids.
        XCTAssertTrue(engine.isEligibleForDisplay(message))
    }
}
