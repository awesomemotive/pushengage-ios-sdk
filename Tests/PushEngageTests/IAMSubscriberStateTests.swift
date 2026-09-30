import XCTest
@testable import PushEngage

/// Subscriber-backed audience data: the exact fields requested, how the payload
/// maps onto the audience vocabulary, and the app-open wiring that refreshes it
/// before auto-triggers are evaluated.
///
/// Mirrors Android's C3 pass 2 in docs/plans/2026-07-27-iam-dashboard-design-changes.md.
final class IAMSubscriberStateTests: XCTestCase {

    // MARK: - Requested fields

    func testRequestsExactlyTheSixAudienceFields() {
        XCTAssertEqual(IAMSubscriberStateMapper.requestedFields,
                       ["segments", "attributes", "city", "state", "country", "has_unsubscribed"])
    }

    func testRequestedFieldsCarryNoPII() {
        // The backend validator defaults an absent `fields` parameter to EVERY
        // field, so the list must be sent explicitly and must never grow to
        // include these.
        for pii in ["email", "first_name", "last_name", "date_of_birth"] {
            XCTAssertFalse(IAMSubscriberStateMapper.requestedFields.contains(pii),
                           "\(pii) must never be requested for audience targeting")
        }
    }

    // MARK: - Mapping

    func testMapsSegments() {
        let state = IAMSubscriberStateMapper.state(from: ["segments": ["qatest", "vip"]])
        XCTAssertEqual(state.segments, ["qatest", "vip"])
    }

    func testMapsAttributesStringifyingNonStringValues() {
        // Verified in production: the backend stores whatever type it was given,
        // so attribute values are genuinely mixed-type on the wire.
        let state = IAMSubscriberStateMapper.state(from: [
            "attributes": ["plan": "gold", "age": 25, "height": 6.1, "is_premium": true]
        ])
        XCTAssertEqual(state.attributes["plan"], "gold")
        XCTAssertEqual(state.attributes["age"], "25")
        XCTAssertEqual(state.attributes["height"], "6.1")
        XCTAssertEqual(state.attributes["is_premium"], "true")
    }

    func testMapsCityAndState() {
        let state = IAMSubscriberStateMapper.state(from: ["city": "Santa Cruz", "state": "Maharashtra"])
        XCTAssertEqual(state.scalars["city"], "Santa Cruz")
        XCTAssertEqual(state.scalars["state"], "Maharashtra")
    }

    func testMapsBackendCountryOntoGeoCountry() {
        // The backend calls the IP-derived value `country`; the audience field is
        // `geo_country`, kept distinct from the locale's `device_region`.
        let state = IAMSubscriberStateMapper.state(from: ["country": "India"])
        XCTAssertEqual(state.scalars["geo_country"], "India")
        XCTAssertNil(state.scalars["country"])
        XCTAssertNil(state.scalars["device_region"])
    }

    func testMapsNumericHasUnsubscribedOntoABoolean() {
        XCTAssertEqual(IAMSubscriberStateMapper.state(from: ["has_unsubscribed": 0])
                        .scalars["has_unsubscribed"], "false")
        XCTAssertEqual(IAMSubscriberStateMapper.state(from: ["has_unsubscribed": 1])
                        .scalars["has_unsubscribed"], "true")
    }

    func testAcceptsABooleanHasUnsubscribedToo() {
        XCTAssertEqual(IAMSubscriberStateMapper.state(from: ["has_unsubscribed": true])
                        .scalars["has_unsubscribed"], "true")
    }

    func testAbsentFieldsAreOmittedRatherThanStoredEmpty() {
        // Verified: fields with no value are absent from the payload, not null.
        // An absent key must mean unknown, so a positive condition fails closed.
        let state = IAMSubscriberStateMapper.state(from: [:])
        XCTAssertTrue(state.segments.isEmpty)
        XCTAssertTrue(state.attributes.isEmpty)
        XCTAssertTrue(state.scalars.isEmpty)
    }

    func testEmptyStringScalarsAreTreatedAsAbsent() {
        let state = IAMSubscriberStateMapper.state(from: ["city": "", "country": "India"])
        XCTAssertNil(state.scalars["city"])
        XCTAssertEqual(state.scalars["geo_country"], "India")
    }

    func testUnexpectedPayloadTypesAreIgnoredRatherThanCrashing() {
        let state = IAMSubscriberStateMapper.state(from: [
            "segments": "qatest",            // string where a list is expected
            "attributes": ["gold"],          // list where a map is expected
            "city": 42,                      // number where a string is expected
            "has_unsubscribed": "maybe"      // neither a number nor a boolean
        ])
        XCTAssertTrue(state.segments.isEmpty)
        XCTAssertTrue(state.attributes.isEmpty)
        XCTAssertEqual(state.scalars["city"], "42")  // scalars stringify
        XCTAssertNil(state.scalars["has_unsubscribed"])
    }

    func testNonStringSegmentEntriesAreStringified() {
        let state = IAMSubscriberStateMapper.state(from: ["segments": ["vip", 7]])
        XCTAssertEqual(state.segments, ["vip", "7"])
    }

    func testNullValuesAreSkipped() {
        let state = IAMSubscriberStateMapper.state(from: [
            "city": NSNull(),
            "attributes": ["plan": NSNull()],
            "segments": [NSNull(), "vip"]
        ])
        XCTAssertNil(state.scalars["city"])
        XCTAssertNil(state.attributes["plan"])
        XCTAssertEqual(state.segments, ["vip"])
    }
}

/// The app-open tail: refreshing the audience inputs, then evaluating
/// auto-triggers with deferral applied.
final class IAMAudienceInputRefreshTests: XCTestCase {

    private var controller: IAMController!
    private var repository: IAMRepository!
    private var provider: StubSubscriberStateProvider!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(IAMCoreDataManager.shared.isStoreAvailable, "IAM persistent store unavailable")

        controller = IAMController.shared
        repository = IAMRepository()
        try repository.replaceAllMessages([])
        IAMQueueStateManager.shared.clearAllStates()
        IAMQueueManager.shared.pauseQueue()
        controller.enable()

        // The shared rules engine reads standard UserDefaults, so a previous test's
        // snapshot would otherwise decide this one's deferral.
        Self.clearIAMDefaults()

        provider = StubSubscriberStateProvider()
        controller.subscriberStateProvider = provider
        // UNUserNotificationCenter.current() asserts in the test host (no app
        // bundle), so the permission read is stubbed unless a test needs it.
        controller.notificationPermissionReader = { completion in completion(false) }
    }

    override func tearDownWithError() throws {
        let cleanup = expectation(description: "queue cleared")
        IAMQueueManager.shared.clearQueue { cleanup.fulfill() }
        wait(for: [cleanup], timeout: 5)
        controller.subscriberStateProvider = IAMSubscriberStateProvider()
        controller.notificationPermissionReader = IAMController.systemNotificationPermissionReader
        IAMQueueStateManager.shared.clearAllStates()
        try? repository.replaceAllMessages([])
        Self.clearIAMDefaults()
        try super.tearDownWithError()
    }

    /// Removes everything `IAMDeviceProperties` persists, so each test starts with
    /// no subscriber snapshot and no cached permission state.
    private static func clearIAMDefaults() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(IAMDeviceProperties.StorageKey.attributePrefix)
            || key.hasPrefix("pe_iam_") {
            defaults.removeObject(forKey: key)
        }
    }

    private func autoCampaign(id: String, audience: String?) throws -> IAMMessageResponse {
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
            trigger: IAMTriggerCondition(type: "auto")
        )
    }

    private func refreshAndProcess() {
        let done = expectation(description: "audience inputs refreshed")
        controller.refreshAudienceInputs { done.fulfill() }
        wait(for: [done], timeout: 5)

        controller.processAutoTriggers()
        // processAutoTriggers hops to the main queue; drain it.
        let drained = expectation(description: "auto triggers processed")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5)
    }

    // MARK: - Refresh

    func testAppOpenAppliesTheSubscriberSnapshot() throws {
        provider.hasSubscriber = true
        provider.payload = ["segments": ["qatest"], "country": "India"]
        try repository.replaceAllMessages([
            try autoCampaign(id: "seg-match",
                             audience: #"[{"field":"segments","op":"includes","value":["qatest"]}]"#),
            try autoCampaign(id: "geo-match",
                             audience: #"[{"field":"geo_country","op":"eq","value":["India"]}]"#),
            try autoCampaign(id: "seg-miss",
                             audience: #"[{"field":"segments","op":"includes","value":["nope"]}]"#)
        ])

        refreshAndProcess()

        let queued = IAMQueueManager.shared.queuedMessageIds
        XCTAssertTrue(queued.contains("seg-match"))
        XCTAssertTrue(queued.contains("geo-match"))
        // The control: proves the state genuinely loaded rather than `includes`
        // passing everything.
        XCTAssertFalse(queued.contains("seg-miss"))
    }

    func testTheSubscriberFetchAsksForTheExactFieldList() {
        provider.hasSubscriber = true
        provider.payload = [:]

        let done = expectation(description: "refreshed")
        controller.refreshAudienceInputs { done.fulfill() }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(provider.requestedFields, IAMSubscriberStateMapper.requestedFields)
    }

    func testNoFetchIsAttemptedWithoutASubscriber() {
        // No hash means subscribe has not completed — there is nothing to fetch,
        // and subscriber-backed conditions stay deferred.
        provider.hasSubscriber = false

        let done = expectation(description: "refreshed")
        controller.refreshAudienceInputs { done.fulfill() }
        wait(for: [done], timeout: 5)

        XCTAssertNil(provider.requestedFields)
    }

    func testAFailedFetchIsNonFatalAndKeepsTheCachedSnapshot() throws {
        provider.hasSubscriber = true
        provider.payload = ["segments": ["qatest"]]
        try repository.replaceAllMessages([
            try autoCampaign(id: "cached",
                             audience: #"[{"field":"segments","op":"includes","value":["qatest"]}]"#)
        ])
        refreshAndProcess()
        XCTAssertTrue(IAMQueueManager.shared.queuedMessageIds.contains("cached"))

        let cleared = expectation(description: "queue cleared")
        IAMQueueManager.shared.clearQueue { cleared.fulfill() }
        wait(for: [cleared], timeout: 5)
        IAMQueueStateManager.shared.clearAllStates()

        // Second pass fails: evaluating against yesterday's data beats evaluating
        // against none.
        provider.payload = nil
        refreshAndProcess()
        XCTAssertTrue(IAMQueueManager.shared.queuedMessageIds.contains("cached"))
    }

    func testAFailedFirstFetchLeavesCampaignsDeferredRatherThanEvaluated() throws {
        // The third branch of the refresh: a subscriber exists, the very first fetch
        // fails, and there is no cached snapshot. Marking the state loaded here would
        // evaluate against nothing — and a negative operator would then pass, showing
        // the campaign to every fresh install with a flaky network.
        provider.hasSubscriber = true
        provider.payload = nil
        try repository.replaceAllMessages([
            try autoCampaign(id: "positive",
                             audience: #"[{"field":"segments","op":"includes","value":["qatest"]}]"#),
            try autoCampaign(id: "negative",
                             audience: #"[{"field":"geo_country","op":"neq","value":["India"]}]"#)
        ])

        refreshAndProcess()

        let queued = IAMQueueManager.shared.queuedMessageIds
        XCTAssertFalse(queued.contains("positive"))
        XCTAssertFalse(queued.contains("negative"),
                       "a negative operator must not pass against a snapshot that was never fetched")

        // Deferred, not permanently failed: the next successful fetch releases it.
        provider.payload = ["segments": ["qatest"]]
        refreshAndProcess()
        XCTAssertTrue(IAMQueueManager.shared.queuedMessageIds.contains("positive"))
    }

    func testAppOpenCachesTheNotificationPermissionState() throws {
        provider.hasSubscriber = false
        controller.notificationPermissionReader = { completion in completion(true) }
        try repository.replaceAllMessages([
            try autoCampaign(id: "notif",
                             audience: #"[{"field":"notification_enabled","op":"eq","value":["true"]}]"#)
        ])

        refreshAndProcess()

        XCTAssertTrue(IAMQueueManager.shared.queuedMessageIds.contains("notif"))
    }

    // MARK: - Deferral

    func testSubscriberBackedCampaignsAreDeferredBeforeAnyFetchRatherThanEvaluated() throws {
        provider.hasSubscriber = false
        try repository.replaceAllMessages([
            // Positive operator: would fail closed, hiding it from every new install.
            try autoCampaign(id: "defer-positive",
                             audience: #"[{"field":"segments","op":"includes","value":["qatest"]}]"#),
            // Negative operator: would PASS, showing it to everyone. This is the
            // direction deferral exists to prevent.
            try autoCampaign(id: "defer-negative",
                             audience: #"[{"field":"geo_country","op":"neq","value":["India"]}]"#),
            // Device-only audience is never deferred.
            try autoCampaign(id: "device-only",
                             audience: #"[{"field":"platform","op":"eq","value":["iOS"]}]"#)
        ])

        refreshAndProcess()

        let queued = IAMQueueManager.shared.queuedMessageIds
        XCTAssertFalse(queued.contains("defer-positive"))
        XCTAssertFalse(queued.contains("defer-negative"))
        XCTAssertTrue(queued.contains("device-only"))
    }

    func testADeferredCampaignShowsOnceTheStateArrives() throws {
        provider.hasSubscriber = false
        try repository.replaceAllMessages([
            try autoCampaign(id: "later",
                             audience: #"[{"field":"segments","op":"includes","value":["qatest"]}]"#)
        ])
        refreshAndProcess()
        XCTAssertFalse(IAMQueueManager.shared.queuedMessageIds.contains("later"))

        provider.hasSubscriber = true
        provider.payload = ["segments": ["qatest"]]
        refreshAndProcess()
        XCTAssertTrue(IAMQueueManager.shared.queuedMessageIds.contains("later"))
    }
}

/// Applying the snapshot: main-confined, and never observably half-written.
///
/// Audience evaluation is synchronous and main-confined, so an apply that runs on
/// the network callback's thread — or that clears the old values before writing
/// the new ones — lets an evaluation read `loaded == true` against an empty
/// snapshot. Positive conditions then fail and negative ones pass, which is the
/// fail-open the deferral exists to prevent.
final class IAMSubscriberStateApplyTests: XCTestCase {

    /// Reports every mutation as it lands, so a half-applied snapshot is
    /// observable from inside the apply rather than only inferable from a race.
    private final class ProbingDefaults: UserDefaults {
        var onMutate: (() -> Void)?

        override func set(_ value: Any?, forKey defaultName: String) {
            super.set(value, forKey: defaultName)
            onMutate?()
        }

        override func set(_ value: Bool, forKey defaultName: String) {
            super.set(value, forKey: defaultName)
            onMutate?()
        }

        override func removeObject(forKey defaultName: String) {
            super.removeObject(forKey: defaultName)
            onMutate?()
        }
    }

    private static let suiteName = "IAMSubscriberStateApplyTests"
    private var defaults: ProbingDefaults!
    private var properties: IAMDeviceProperties!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(ProbingDefaults(suiteName: Self.suiteName))
        defaults.removePersistentDomain(forName: Self.suiteName)
        properties = IAMDeviceProperties(userDefaults: defaults)
    }

    override func tearDown() {
        defaults.onMutate = nil
        defaults.removePersistentDomain(forName: Self.suiteName)
        defaults = nil
        properties = nil
        super.tearDown()
    }

    private func applyFirstSnapshot() {
        properties.applySubscriberState(segments: ["vip"],
                                        attributes: ["plan": "gold"],
                                        scalars: ["geo_country": "India"],
                                        identity: "hash-a")
    }

    func testNoIntermediateStateReportsLoadedWithAMissingAttribute() {
        applyFirstSnapshot()
        XCTAssertTrue(properties.hasSubscriberState)

        var violations: [String] = []
        defaults.onMutate = { [unowned self] in
            guard self.properties.hasSubscriberState else { return }
            if self.properties.userAttribute(for: "attr.plan") == nil {
                violations.append("attr.plan missing while state reads as loaded")
            }
            if self.properties.userAttribute(for: "geo_country") == nil {
                violations.append("geo_country missing while state reads as loaded")
            }
        }

        properties.applySubscriberState(segments: ["vip"],
                                        attributes: ["plan": "silver"],
                                        scalars: ["geo_country": "India"],
                                        identity: "hash-a")

        XCTAssertEqual(violations, [], "the snapshot must never be observably half-applied")
    }

    func testNoIntermediateStateReportsLoadedWithEmptySegments() {
        applyFirstSnapshot()

        var sawEmptySegments = false
        defaults.onMutate = { [unowned self] in
            if self.properties.hasSubscriberState, self.properties.segments.isEmpty {
                sawEmptySegments = true
            }
        }

        properties.applySubscriberState(segments: ["vip"],
                                        attributes: ["plan": "gold"],
                                        scalars: [:],
                                        identity: "hash-a")

        XCTAssertFalse(sawEmptySegments, "segments must never read empty while state reads as loaded")
    }

    func testApplyingFromABackgroundThreadMutatesOnTheMainThread() {
        var mutatedOffMain = false
        defaults.onMutate = {
            if !Thread.isMainThread { mutatedOffMain = true }
        }

        let applied = expectation(description: "snapshot applied")
        DispatchQueue.global().async { [unowned self] in
            self.properties.applySubscriberState(segments: ["vip"],
                                                 attributes: ["plan": "gold"],
                                                 scalars: [:],
                                                 identity: "hash-a")
            DispatchQueue.main.async { applied.fulfill() }
        }
        wait(for: [applied], timeout: 5)
        // The hop is async, so let the queued apply land before asserting.
        let drained = expectation(description: "main drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5)

        XCTAssertFalse(mutatedOffMain, "the snapshot must be written on the main thread")
        XCTAssertTrue(properties.hasSubscriberState)
        XCTAssertEqual(properties.userAttribute(for: "attr.plan"), "gold")
    }

    // MARK: - Identity

    func testASnapshotIsDiscardedWhenTheSubscriberIdentityChanges() {
        properties.applySubscriberState(segments: ["vip"],
                                        attributes: ["plan": "gold"],
                                        scalars: ["geo_country": "India"],
                                        identity: "hash-a")
        XCTAssertTrue(properties.hasSubscriberState)

        properties.invalidateSubscriberStateIfIdentityChanged("hash-b")

        // Everything the previous subscriber contributed has to go, and the state
        // must read as never-fetched so campaigns defer instead of matching them.
        XCTAssertFalse(properties.hasSubscriberState)
        XCTAssertTrue(properties.segments.isEmpty)
        XCTAssertNil(properties.userAttribute(for: "attr.plan"))
        XCTAssertNil(properties.userAttribute(for: "geo_country"))
    }

    func testASnapshotSurvivesWhenTheSubscriberIdentityIsUnchanged() {
        properties.applySubscriberState(segments: ["vip"],
                                        attributes: ["plan": "gold"],
                                        scalars: [:],
                                        identity: "hash-a")

        properties.invalidateSubscriberStateIfIdentityChanged("hash-a")

        XCTAssertTrue(properties.hasSubscriberState)
        XCTAssertEqual(properties.segments, ["vip"])
        XCTAssertEqual(properties.userAttribute(for: "attr.plan"), "gold")
    }

    func testLosingTheSubscriberDiscardsTheSnapshot() {
        // Unsubscribe clears the hash, so the snapshot it was captured under no
        // longer describes anybody.
        properties.applySubscriberState(segments: ["vip"],
                                        attributes: ["plan": "gold"],
                                        scalars: [:],
                                        identity: "hash-a")

        properties.invalidateSubscriberStateIfIdentityChanged("")

        XCTAssertFalse(properties.hasSubscriberState)
        XCTAssertNil(properties.userAttribute(for: "attr.plan"))
    }

    func testLocallySetAttributesSurviveAnIdentityChange() {
        // Only the `attr.` namespace comes from the subscriber record; attributes the
        // app set itself are its own state and are not ours to drop.
        properties.setUserAttribute("dark", for: "theme")
        properties.applySubscriberState(segments: ["vip"],
                                        attributes: ["plan": "gold"],
                                        scalars: [:],
                                        identity: "hash-a")

        properties.invalidateSubscriberStateIfIdentityChanged("hash-b")

        XCTAssertEqual(properties.userAttribute(for: "theme"), "dark")
        XCTAssertNil(properties.userAttribute(for: "attr.plan"))
    }

    func testAnOmittedAttributeIsStillClearedByTheNextSnapshot() {
        applyFirstSnapshot()
        XCTAssertEqual(properties.userAttribute(for: "attr.plan"), "gold")

        properties.applySubscriberState(segments: [], attributes: [:], scalars: [:], identity: "hash-a")

        XCTAssertNil(properties.userAttribute(for: "attr.plan"))
        XCTAssertNil(properties.userAttribute(for: "geo_country"))
        XCTAssertTrue(properties.segments.isEmpty)
    }
}

/// Scripted subscriber-state source: no network, and it records what was asked for.
private final class StubSubscriberStateProvider: IAMSubscriberStateProviding {
    var hasSubscriber = false
    var subscriberIdentity = "stub-subscriber"
    /// nil = the fetch fails.
    var payload: [String: Any]?
    var requestedFields: [String]?

    func fetchSubscriberFields(_ fields: [String], completion: @escaping ([String: Any]?) -> Void) {
        requestedFields = fields
        completion(payload)
    }
}
