import Foundation

/// Matches a trigger occurrence against a campaign's trigger conditions.
///
/// The campaign states **requirements**; the app supplies the **data**:
///
/// - parameters the app sends that no condition names are **ignored**
/// - **absent or empty `conditions` match any occurrence** of the event
/// - a condition naming a parameter the app did not send is treated as missing, so
///   positive operators fail and negative ones pass — same rule as audience
/// - the legacy `parameters` map is still honoured as exact string equality, since
///   campaigns stored by an earlier build remain in the store until the next sync
///
/// This reverses the previous direction, which required every parameter the app
/// sent to be declared on the campaign — a rule that cannot express
/// `cart_value > 100` at all.
enum IAMTriggerMatcher {

    /// Filters event-matched messages by their trigger conditions.
    ///
    /// Applied **always**, not only when the call carries parameters: a campaign
    /// with conditions must satisfy them even when nothing is passed.
    static func filter(messages: [IAMMessage], parameters: [String: Any]?) -> [IAMMessage] {
        messages.filter { matches(message: $0, parameters: parameters) }
    }

    /// Whether an occurrence carrying `parameters` satisfies `message`'s trigger
    /// conditions.
    static func matches(message: IAMMessage, parameters: [String: Any]?) -> Bool {
        guard let triggerData = message.trigger,
              let trigger = (try? JSONSerialization.jsonObject(with: triggerData)) as? [String: Any] else {
            // Unreadable trigger fails closed, consistent with audience.
            PELogger.error(
                className: String(describing: IAMTriggerMatcher.self),
                message: "Message \(message.id): trigger is unreadable — not matching"
            )
            return false
        }

        let supplied = parameters.map(stringified) ?? [:]
        let context = IAMConditionEvaluator.Context.triggerParameters(supplied)

        let rawConditions = trigger["conditions"]
        if rawConditions != nil, !(rawConditions is NSNull) {
            guard let conditions = rawConditions as? [Any] else {
                // Present but not an array: malformed, not absent. Falling through to
                // the legacy branch would match every occurrence of the event.
                PELogger.error(
                    className: String(describing: IAMTriggerMatcher.self),
                    message: "Message \(message.id): trigger conditions is not an array — not matching"
                )
                return false
            }

            if conditions.isEmpty { return true }  // no requirements

            guard let match = IAMConditionEvaluator.matchMode(in: trigger,
                                                             default: IAMConditionEvaluator.matchAll) else {
                PELogger.error(
                    className: String(describing: IAMTriggerMatcher.self),
                    message: "Message \(message.id): unknown trigger match mode — not matching"
                )
                return false
            }
            return IAMConditionEvaluator.matches(conditions: conditions, match: match, context: context)
        }

        // Legacy `parameters` map: exact string equality, and every key the
        // campaign declares must hold. Keys the campaign does not declare are
        // ignored, matching the new rule.
        guard let legacy = trigger["parameters"] as? [String: Any], !legacy.isEmpty else {
            return true
        }
        return legacy.allSatisfy { key, value in
            supplied[key] == IAMConditionEvaluator.string(from: value)
        }
    }

    /// Values are compared in string form: the trigger API takes `[String: Any]`
    /// and the wire carries condition values as strings.
    static func stringified(_ parameters: [String: Any]) -> [String: String] {
        parameters.compactMapValues { IAMConditionEvaluator.string(from: $0) }
    }
}
