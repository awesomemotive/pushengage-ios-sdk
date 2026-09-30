import XCTest
@testable import PushEngage

/// Contract tests for the IAM wire format, per
/// docs/plans/2026-07-10-iam-sdk-flow-and-backend-contract.md (§3, §7.1).
/// One backend payload serves both platforms; Android guards the same
/// contract with IAMWireFormatTest.
final class IAMWireFormatTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try IAMWireCodec.decoder.decode(type, from: Data(json.utf8))
    }

    private func encodeToString<T: Encodable>(_ value: T) throws -> String {
        String(data: try IAMWireCodec.encoder.encode(value), encoding: .utf8) ?? ""
    }

    // MARK: - Raw JSON round trips

    /// Every top-level JSON shape survives `IAMRawJSON`, scalars included: a
    /// malformed campaign may send `"audience": "vip"`, and it has to reach the
    /// evaluator to be refused there rather than failing on the way into the store.
    func testRawJSONRoundTripsScalarsByteForByte() throws {
        for json in [#""vip""#, "42", "6.5", "true", "false", "null"] {
            let raw = try IAMRawJSON(data: Data(json.utf8))
            XCTAssertEqual(String(data: raw.data, encoding: .utf8), json,
                           "\(json) must round-trip unchanged")
        }
    }

    func testRawJSONRoundTripsContainersPreservingTheirValues() throws {
        // Key order is not preserved (JSON objects are unordered) — the values are.
        for json in [#"{"match":"any","groups":[]}"#,
                     #"[{"field":"platform","op":"eq","value":["iOS"]}]"#,
                     #"{"match":"any","groups":[{"conditions":[{"field":"attr.ltv","op":"gte","value":["500"]}]}]}"#] {
            let raw = try IAMRawJSON(data: Data(json.utf8))
            let original = try JSONSerialization.jsonObject(with: Data(json.utf8))
            let restored = try JSONSerialization.jsonObject(with: raw.data)
            XCTAssertEqual(original as? NSObject, restored as? NSObject,
                           "\(json) must round-trip with its values intact")
        }
    }

    func testRawJSONScalarsRemainReadableAsJSON() throws {
        // The bytes have to parse back with the reading side the evaluator uses.
        for json in [#""vip""#, "42", "true", "null"] {
            let raw = try IAMRawJSON(data: Data(json.utf8))
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: raw.data,
                                                             options: [.fragmentsAllowed]),
                             "\(json) must stay parseable")
        }
    }

    func testAScalarAudienceIsStoredRatherThanLostAndFailsClosedAtEvaluation() throws {
        // Losing it would store no audience at all, which reads as "everyone".
        let response = try decode(IAMMessageResponse.self, """
        {"id":"scalar-audience","position":"center","htmlContent":"<html></html>",
         "audience":"vip","trigger":{"type":"auto"}}
        """)
        let audience = try XCTUnwrap(response.audience)
        XCTAssertEqual(String(data: audience.data, encoding: .utf8), #""vip""#)
        XCTAssertFalse(IAMConditionEvaluator.matchesAudience(audience.data,
                                                            context: .triggerParameters([:]),
                                                            messageId: "scalar-audience"))
    }

    // MARK: - Action types (§3.8, §7.1)

    func testParsesWireFormatActionTypes() throws {
        let openURL = try decode(IAMAction.self, #"{"type": "open_url", "parameters": {"url": "https://x.com"}}"#)
        XCTAssertEqual(openURL.type, .openURL)

        let permission = try decode(IAMAction.self, #"{"type": "request_notification_permission"}"#)
        XCTAssertEqual(permission.type, .requestNotificationPermission)

        let dismiss = try decode(IAMAction.self, #"{"type": "dismiss"}"#)
        XCTAssertEqual(dismiss.type, .dismiss)

        let custom = try decode(IAMAction.self, #"{"type": "custom"}"#)
        XCTAssertEqual(custom.type, .custom)
    }

    func testLegacyIOSActionTypeSpellingsAreNoLongerAccepted() throws {
        // `dismiss_action` / `custom_action` were iOS's own older enum raw values,
        // never part of the backend contract (flow doc §7.1 lists the four
        // canonical lowercase values and asks for exactly this rename). Accepting
        // them only made the same payload behave differently per platform, since
        // Android's @SerializedName set never included them.
        //
        // Note these are still perfectly valid action *keys* — campaigns really do
        // use `"dismiss_action": { "type": "dismiss" }` and
        // `PEBridge.handleAction('dismiss_action')`. Only the `type` value is
        // constrained; keys stay arbitrary.
        let dismiss = try decode(IAMAction.self, #"{"type": "dismiss_action", "parameters": {}}"#)
        XCTAssertEqual(dismiss.type, .unrecognised)

        let custom = try decode(IAMAction.self, #"{"type": "custom_action", "parameters": {}}"#)
        XCTAssertEqual(custom.type, .unrecognised)
    }

    func testUnknownActionTypeGoesInertRatherThanBecomingCustom() throws {
        // Matches Android, where an unparseable type makes createActionFromJson
        // return null: the button does nothing, records no click, and leaves the
        // message up. Coercing to `.custom` invented an actionId the host app
        // never configured, so the app could not distinguish it from a real
        // custom action — and the same campaign behaved differently per platform.
        let action = try decode(IAMAction.self, #"{"type": "teleport", "parameters": {}}"#)
        XCTAssertEqual(action.type, .unrecognised)
        XCTAssertFalse(action.type.isSDKHandled)
    }

    func testUnknownActionTypeDoesNotBlankTheMessagesOtherButtons() throws {
        // Decoding must not throw: `IAMMessage.decodedActions` wraps the map
        // decode in `try?` and IAMMessageResponse decodes it inline, so a throw
        // here would blank every button or drop the campaign at sync — strictly
        // worse than Android, which nulls only the offending action.
        let actions = try decode(
            [String: IAMAction].self,
            #"{"a": {"type": "teleport"}, "b": {"type": "dismiss", "label": "Close"}}"#
        )
        XCTAssertEqual(actions["a"]?.type, .unrecognised)
        XCTAssertEqual(actions["b"]?.type, .dismiss)
        XCTAssertEqual(actions["b"]?.label, "Close")
    }

    func testActionLabelIsParsedForAnalyticsBtnText() throws {
        let action = try decode(IAMAction.self, #"{"type": "dismiss", "label": "Not Now"}"#)
        XCTAssertEqual(action.label, "Not Now")
    }

    func testActionLabelIsOptionalForPreLabelContent() throws {
        let action = try decode(IAMAction.self, #"{"type": "dismiss", "parameters": {}}"#)
        XCTAssertNil(action.label)
    }

    func testActionParametersAreOptional() throws {
        // §Appendix A.1: {"type": "dismiss", "label": "Not Now"} has no parameters.
        let action = try decode(IAMAction.self, #"{"type": "dismiss", "label": "Not Now"}"#)
        XCTAssertEqual(action.parameters, [:])
    }

    func testActionParametersToleratesNonStringScalarValues() throws {
        // Android models parameters as Map<String, Any>; a payload with
        // numeric/bool values must not drop the campaign on iOS.
        let action = try decode(
            IAMAction.self,
            #"{"type": "custom", "parameters": {"id": "onboarding", "step": 2, "final": true, "score": 1.5}}"#
        )
        XCTAssertEqual(action.parameters["id"], "onboarding")
        XCTAssertEqual(action.parameters["step"], "2")
        XCTAssertEqual(action.parameters["final"], "true")
        XCTAssertEqual(action.parameters["score"], "1.5")
    }

    func testSerializesContractActionWireValues() throws {
        let json = try encodeToString(IAMAction(type: .dismiss, parameters: [:]))
        XCTAssertTrue(json.contains(#""dismiss""#))
        XCTAssertFalse(json.contains("dismiss_action"))

        let customJson = try encodeToString(IAMAction(type: .custom, parameters: [:]))
        XCTAssertTrue(customJson.contains(#""custom""#))
        XCTAssertFalse(customJson.contains("custom_action"))
    }

    // MARK: - Metadata version (§2.1)

    func testMetadataVersionAcceptsJSONNumber() throws {
        // Live staging sends version as an epoch-ms NUMBER; a plain String
        // decode threw and killed the whole sync (caught on the simulator).
        let metadata = try decode(
            IAMMetadataResponse.self,
            #"{"version": 1784541032000, "site_id": 50510, "iam_status": "active"}"#
        )
        XCTAssertEqual(metadata.version, "1784541032000")
        XCTAssertEqual(metadata.iamStatus, "active")
    }

    func testMetadataVersionAcceptsString() throws {
        let metadata = try decode(
            IAMMetadataResponse.self,
            #"{"version": "2025-10-17T06:00:04.000Z", "iam_status": "active"}"#
        )
        XCTAssertEqual(metadata.version, "2025-10-17T06:00:04.000Z")
    }

    // MARK: - Campaign scalar defaults (§3.4)

    func testCampaignDecodesWithOmittedScalars() throws {
        // The live backend omits displayDuration (and may omit others); with
        // the synthesized decode one missing key failed the WHOLE campaigns
        // array. Defaults match Android: duration 0, no tap-dismiss, priority 1.
        let campaign = try decode(
            IAMMessageResponse.self,
            #"{"id": "c1", "position": "top", "htmlContent": "<html></html>", "trigger": {"type": "auto"}}"#
        )
        XCTAssertEqual(campaign.displayDuration, 0)
        XCTAssertFalse(campaign.shouldDismissOnTap)
        XCTAssertEqual(campaign.priority, 1)
        XCTAssertTrue(campaign.actions.isEmpty)
        XCTAssertNil(campaign.trigger.event)
    }

    // MARK: - Trigger (§3.5)

    func testParsesCustomTriggerWithEvent() throws {
        let trigger = try decode(
            IAMTriggerCondition.self,
            #"{"type": "custom", "event": "permission_prompt", "parameters": {"type": "permission"}}"#
        )
        XCTAssertEqual(trigger.type, "custom")
        XCTAssertEqual(trigger.event, "permission_prompt")
        XCTAssertEqual(trigger.parameters?["type"], "permission")
    }

    func testParsesEventlessAutoTrigger() throws {
        // Backend sends auto triggers with no `event` — display is keyed off
        // `type`, not an event match — so the campaign must still decode
        // (a required `event` would fail the whole campaigns response, §3.5).
        let trigger = try decode(IAMTriggerCondition.self, #"{"type": "auto"}"#)
        XCTAssertEqual(trigger.type, "auto")
        XCTAssertNil(trigger.event)
    }

    // MARK: - Frequency (§3.7, §7.1)

    func testParsesWireFormatFrequencyTypes() throws {
        XCTAssertEqual(try decode(IAMFrequency.self, #"{"type": "one_time"}"#).type, .oneTime)
        XCTAssertEqual(try decode(IAMFrequency.self, #"{"type": "capped", "count": 3, "interval": 86400}"#).type, .capped)
        XCTAssertEqual(try decode(IAMFrequency.self, #"{"type": "recurring", "interval": 0}"#).type, .recurring)
    }

    func testParsesLegacyHyphenatedOneTimeStoredByOlderBuilds() throws {
        XCTAssertEqual(try decode(IAMFrequency.self, #"{"type": "one-time"}"#).type, .oneTime)
    }

    func testUnknownFrequencyTypeIsForwardCompatible() throws {
        // §3.7: unknown type (valid JSON, unrecognized value) = no cap; must not throw.
        let frequency = try decode(IAMFrequency.self, #"{"type": "weekly", "count": 2, "interval": 60}"#)
        XCTAssertEqual(frequency.type, .unknown)
    }

    func testAnAbsentCountStaysDistinguishableFromAnExplicitZero() throws {
        // Inverted by C5: the old -1 default made a `capped` campaign with no count
        // unlimited. Absent must stay absent so the rules engine can fail it closed,
        // while an explicit value is honoured as given.
        XCTAssertNil(try decode(IAMFrequency.self, #"{"type": "capped", "interval": 60}"#).count)
        XCTAssertEqual(try decode(IAMFrequency.self, #"{"type": "capped", "count": 0}"#).count, 0)
    }

    func testAnAbsentIntervalStaysDistinguishableFromAnExplicitZero() throws {
        // An explicit `interval: 0` is a legitimate "no spacing"; absent means the
        // rule is unusable. Collapsing both to 0 is what made `recurring` with no
        // interval silently unlimited.
        XCTAssertNil(try decode(IAMFrequency.self, #"{"type": "recurring"}"#).interval)
        XCTAssertEqual(try decode(IAMFrequency.self, #"{"type": "recurring", "interval": 0}"#).interval, 0)
    }

    func testSerializesContractFrequencyWireValues() throws {
        let json = try encodeToString(IAMFrequency(type: .oneTime, count: 1, interval: 0))
        XCTAssertTrue(json.contains(#""one_time""#))
        XCTAssertFalse(json.contains("one-time"))
    }

    // MARK: - Audience shape (§3.5, §7.1)

    /// The audience JSON a campaign decode preserved, as a Foundation tree.
    private func decodedAudienceTree(_ campaignJSON: String) throws -> Any {
        let response = try decode(IAMMessageResponse.self, campaignJSON)
        let raw = try XCTUnwrap(response.audience)
        return try JSONSerialization.jsonObject(with: raw.data, options: [.fragmentsAllowed])
    }

    private func campaign(audience: String) -> String {
        """
        {"id":"c1","position":"center","htmlContent":"<html></html>",
         "trigger":{"type":"auto"},"audience":\(audience)}
        """
    }

    func testGroupedAudienceShapeRoundTripsVerbatim() throws {
        let tree = try decodedAudienceTree(campaign(audience: """
        {"match":"any","groups":[
          {"match":"all","conditions":[
            {"field":"segments","op":"includes","value":["qatest","vip"]},
            {"field":"attr.ltv","type":"number","op":"gte","value":["500"]}]}]}
        """)) as? [String: Any]

        XCTAssertEqual(tree?["match"] as? String, "any")
        let groups = try XCTUnwrap(tree?["groups"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 1)
        let conditions = try XCTUnwrap(groups[0]["conditions"] as? [[String: Any]])
        XCTAssertEqual(conditions.count, 2)
        XCTAssertEqual(conditions[0]["op"] as? String, "includes")
        XCTAssertEqual(conditions[1]["type"] as? String, "number")
        XCTAssertEqual(conditions[1]["value"] as? [String], ["500"])
    }

    func testGroupedAudienceNoLongerDropsTheCampaign() throws {
        // Before C1 the audience was typed as [IAMAudienceCondition], so the
        // grouped shape THREW and took the whole campaign with it — the reason iOS
        // was the critical path for this change.
        let response = try decode(IAMMessageResponse.self, campaign(audience: """
        {"match":"any","groups":[{"match":"all","conditions":[
          {"field":"platform","op":"eq","value":["iOS"]}]}]}
        """))
        XCTAssertEqual(response.id, "c1")
        XCTAssertNotNil(response.audience)
    }

    func testLegacyFlatAudienceArrayStillDecodes() throws {
        let tree = try decodedAudienceTree(campaign(audience: """
        [{"field":"plan","op":"in","value":["gold","platinum"]}]
        """)) as? [[String: Any]]
        XCTAssertEqual(tree?.count, 1)
        XCTAssertEqual(tree?[0]["value"] as? [String], ["gold", "platinum"])
    }

    func testScalarAudienceValueNoLongerDropsTheCampaign() throws {
        // A bare scalar used to throw on the strict [String] decode. It is now
        // carried through and normalised by the evaluator instead.
        let tree = try decodedAudienceTree(campaign(audience: """
        [{"field":"plan","op":"eq","value":"premium"}]
        """)) as? [[String: Any]]
        XCTAssertEqual(tree?[0]["value"] as? String, "premium")
    }

    func testNumericAudienceValuesSurviveWithoutGainingADecimalPoint() throws {
        // A whole number must not round-trip to "5.0", which would stop matching a
        // string comparison against "5".
        let tree = try decodedAudienceTree(campaign(audience: """
        [{"field":"visits","op":"gt","value":[5]}]
        """)) as? [[String: Any]]
        let values = try XCTUnwrap(tree?[0]["value"] as? [Any])
        XCTAssertEqual(IAMConditionEvaluator.string(from: values[0]), "5")
    }

    func testNullAudienceDecodesWithoutFailingTheCampaign() throws {
        let response = try decode(IAMMessageResponse.self, campaign(audience: "null"))
        XCTAssertEqual(response.id, "c1")
    }

    func testAbsentAudienceDecodesAsNil() throws {
        let response = try decode(IAMMessageResponse.self, """
        {"id":"c1","position":"center","htmlContent":"<html></html>","trigger":{"type":"auto"}}
        """)
        XCTAssertNil(response.audience)
    }

    // MARK: - Trigger shape (§3.5, C2/C6b)

    func testTriggerDelayIsParsedAsSeconds() throws {
        let trigger = try decode(IAMTriggerCondition.self, #"{"type":"auto","delay":5}"#)
        XCTAssertEqual(trigger.delay, 5)
    }

    func testAnAbsentTriggerDelayStaysNil() throws {
        // Nullable so "absent" stays distinguishable from an explicit 0.
        XCTAssertNil(try decode(IAMTriggerCondition.self, #"{"type":"auto"}"#).delay)
        XCTAssertEqual(try decode(IAMTriggerCondition.self, #"{"type":"auto","delay":0}"#).delay, 0)
    }

    func testTriggerDelaySurvivesTheRoundTripIntoStoredJSON() throws {
        // The campaign persists its trigger by re-encoding this model, so a field
        // the model does not carry is silently dropped and the delay never applies.
        let trigger = try decode(IAMTriggerCondition.self, #"{"type":"auto","delay":12}"#)
        let reencoded = try JSONEncoder().encode(trigger)
        let tree = try JSONSerialization.jsonObject(with: reencoded) as? [String: Any]
        XCTAssertEqual((tree?["delay"] as? NSNumber)?.doubleValue, 12)
        XCTAssertEqual(IAMTriggerDelay.remaining(triggerJSON: reencoded, appOpenAt: 100, now: 100), 12)
    }

    func testTriggerConditionsSurviveTheRoundTripIntoStoredJSON() throws {
        let trigger = try decode(IAMTriggerCondition.self, """
        {"type":"custom","event":"checkout","match":"any","conditions":[
          {"field":"cart_value","type":"number","op":"gte","value":["100"]}]}
        """)
        let reencoded = try JSONEncoder().encode(trigger)
        let tree = try JSONSerialization.jsonObject(with: reencoded) as? [String: Any]
        XCTAssertEqual(tree?["match"] as? String, "any")
        let conditions = try XCTUnwrap(tree?["conditions"] as? [[String: Any]])
        XCTAssertEqual(conditions[0]["field"] as? String, "cart_value")
        XCTAssertEqual(conditions[0]["value"] as? [String], ["100"])
    }

    // MARK: - Dates (§3.4, §7.1)

    func testDatesParseAsISO8601UTCAndAcceptMillis() throws {
        struct Dated: Codable { let startDate: Date }
        let plain = try decode(Dated.self, #"{"startDate": "2025-07-01T00:00:00Z"}"#)
        let millis = try decode(Dated.self, #"{"startDate": "2025-07-01T00:00:00.000Z"}"#)
        XCTAssertEqual(plain.startDate, millis.startDate)

        var components = DateComponents()
        components.year = 2025; components.month = 7; components.day = 1
        components.timeZone = TimeZone(identifier: "UTC")
        let expected = Calendar(identifier: .gregorian).date(from: components)
        XCTAssertEqual(plain.startDate, expected)
    }

    func testDatesSerializeAsISO8601UTC() throws {
        struct Dated: Codable { let startDate: Date }
        let json = try encodeToString(Dated(startDate: Date(timeIntervalSince1970: 1_751_328_000)))
        XCTAssertTrue(json.contains("2025-07-01T00:00:00Z"), "got: \(json)")
    }

    // MARK: - Full campaign payload (§3)

    func testParsesContractCampaignPayload() throws {
        let json = """
        {
          "id": "c9f1a2b3-4d5e-6f70-8123-abcdef012345",
          "position": "center",
          "htmlContent": "<!DOCTYPE html><html></html>",
          "displayDuration": 0,
          "shouldDismissOnTap": false,
          "priority": 1,
          "startDate": "2025-07-01T00:00:00Z",
          "endDate": "2025-08-01T00:00:00Z",
          "trigger":   { "type": "custom", "event": "permission_prompt", "parameters": { "type": "permission" } },
          "audience":  { "match": "any", "groups": [ { "match": "all", "conditions": [
                          { "field": "platform", "op": "in", "value": ["iOS"] } ] } ] },
          "frequency": { "type": "capped", "count": 3, "interval": 86400 },
          "actions": {
            "enable_notifications": { "type": "request_notification_permission", "label": "Enable", "parameters": {} },
            "dismiss_action":       { "type": "dismiss", "label": "Not Now" }
          }
        }
        """
        let campaign = try decode(IAMMessageResponse.self, json)

        XCTAssertEqual(campaign.id, "c9f1a2b3-4d5e-6f70-8123-abcdef012345")
        XCTAssertEqual(campaign.position, .center)
        XCTAssertEqual(campaign.displayDuration, 0)
        XCTAssertFalse(campaign.shouldDismissOnTap)
        XCTAssertEqual(campaign.priority, 1)
        XCTAssertNotNil(campaign.startDate)
        XCTAssertNotNil(campaign.endDate)
        XCTAssertEqual(campaign.trigger.type, "custom")
        XCTAssertEqual(campaign.trigger.event, "permission_prompt")
        XCTAssertEqual(campaign.trigger.parameters?["type"], "permission")
        let audienceTree = try JSONSerialization
            .jsonObject(with: try XCTUnwrap(campaign.audience).data) as? [String: Any]
        let audienceGroups = try XCTUnwrap(audienceTree?["groups"] as? [[String: Any]])
        let audienceConditions = try XCTUnwrap(audienceGroups[0]["conditions"] as? [[String: Any]])
        XCTAssertEqual(audienceConditions[0]["field"] as? String, "platform")
        XCTAssertEqual(audienceConditions[0]["value"] as? [String], ["iOS"])
        XCTAssertEqual(campaign.frequency?.type, .capped)
        XCTAssertEqual(campaign.frequency?.count, 3)
        XCTAssertEqual(campaign.frequency?.interval, 86400)
        XCTAssertEqual(campaign.actions["enable_notifications"]?.type, .requestNotificationPermission)
        XCTAssertEqual(campaign.actions["enable_notifications"]?.label, "Enable")
        XCTAssertEqual(campaign.actions["dismiss_action"]?.type, .dismiss)
        XCTAssertEqual(campaign.actions["dismiss_action"]?.label, "Not Now")
    }

    func testParsesReferenceMessageWithNullDatesAndNoAudience() throws {
        // §Appendix A.1 shape: no startDate/endDate/audience keys at all.
        let json = """
        {
          "id": "notification-permission-1",
          "position": "center",
          "htmlContent": "<html></html>",
          "displayDuration": 0,
          "shouldDismissOnTap": false,
          "priority": 1,
          "trigger":   { "type": "custom", "event": "notification_permission", "parameters": { "type": "permission" } },
          "frequency": { "type": "recurring", "interval": 0 },
          "actions": {
            "enable_notifications": { "type": "request_notification_permission", "label": "Enable" },
            "dismiss_action":       { "type": "dismiss", "label": "Not Now" }
          }
        }
        """
        let campaign = try decode(IAMMessageResponse.self, json)
        XCTAssertNil(campaign.startDate)
        XCTAssertNil(campaign.endDate)
        XCTAssertNil(campaign.audience)
        XCTAssertEqual(campaign.frequency?.type, .recurring)
        XCTAssertEqual(campaign.frequency?.interval, 0)
    }
}
