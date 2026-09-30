import Foundation

/// Value types a condition can compare under.
enum IAMFieldType: String {
    case string
    case number
    case boolean
    case version
}

/// Evaluates `{field, type, op, value}` conditions, the `any`/`all` folds that
/// combine them, and the two-level audience shape.
///
/// One evaluator serves both audience groups and trigger conditions. The
/// alternative duplicates 4 types × 11 operators × missing-value semantics ×
/// coercion rules across two evaluators on three platforms — and the `capped` /
/// `recurring` frequency split is what that failure mode looks like in practice.
enum IAMConditionEvaluator {

    // MARK: - Vocabulary

    /// Wire values for `audience.match`, `audience.groups[].match` and
    /// `trigger.match`.
    static let matchAny = "any"
    static let matchAll = "all"

    /// Set-valued field — takes `includes`/`excludes`, not scalar operators.
    static let segmentsField = "segments"

    /// Namespace for subscriber attributes. Audience conditions target them as
    /// `attr.<key>`, so a marketer-defined key such as `language` cannot shadow
    /// a built-in field.
    static let attributeNamespace = "attr."

    /// Fields whose values come from the backend subscriber record rather than
    /// the device. A condition on any of these (or on any `attr.` attribute) is
    /// **deferred** until the subscriber fetch has succeeded at least once.
    static let subscriberBackedFields: Set<String> = [
        segmentsField, "city", "state", "geo_country", "has_unsubscribed"
    ]

    /// Types of the built-in audience fields. Authoritative — a declared `type`
    /// on a condition targeting one of these is ignored, so a payload cannot
    /// contradict what the SDK knows about its own data.
    ///
    /// `os_version` and `app_version` are versions rather than numbers: values
    /// are dotted (`"18.1.0"`, `"1.0.0-beta"`) and would not parse as a number.
    static let builtInFieldTypes: [String: IAMFieldType] = [
        "platform": .string,
        "language": .string,
        "device_region": .string,
        "timezone": .string,
        "os_version": .version,
        "app_version": .version,
        "notification_enabled": .boolean,
        // Subscriber-backed, but their types are equally known to us.
        "city": .string,
        "state": .string,
        "geo_country": .string,
        "has_unsubscribed": .boolean
    ]

    // MARK: - Resolution context

    /// Where a condition's `field` is looked up.
    ///
    /// The audience path reads subscriber and device data; the trigger path
    /// reads the event payload. The two never fall through to each other — the
    /// trigger asks "did this happen, with this data?", the audience asks "is
    /// this the right person?".
    struct Context {
        let value: (String) -> String?
        let segments: () -> Set<String>

        /// Whether `segments` means anything here. False makes a `segments`
        /// condition fail rather than be answered against an empty set, where
        /// `excludes` would otherwise hold vacuously.
        let resolvesSegments: Bool

        static func audience(_ properties: IAMDeviceProperties) -> Context {
            Context(value: { properties.userAttribute(for: $0) },
                    segments: { properties.segments },
                    resolvesSegments: true)
        }

        /// Trigger occurrences carry no segments, so a `segments` condition in a
        /// trigger never holds — in either direction.
        static func triggerParameters(_ parameters: [String: String]) -> Context {
            Context(value: { parameters[$0] }, segments: { [] }, resolvesSegments: false)
        }
    }

    // MARK: - Audience

    /// Whether `audienceJSON` targets this subscriber.
    ///
    /// Handles both shapes: the grouped `{match, groups}` object, and the legacy
    /// flat condition array, which is still accepted because rows persisted by a
    /// previous build stay in the store until the next sync full-replaces them.
    static func matchesAudience(_ audienceJSON: Data, context: Context, messageId: String) -> Bool {
        guard !audienceJSON.isEmpty else { return true }

        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: audienceJSON, options: [.fragmentsAllowed])
        } catch {
            // Malformed audience fails closed — don't risk mis-targeting.
            PELogger.error(
                className: String(describing: IAMConditionEvaluator.self),
                message: "Message \(messageId): audience is not valid JSON — not eligible"
            )
            return false
        }

        // Absent criteria: eligible for everyone.
        if parsed is NSNull { return true }

        if let legacy = parsed as? [Any] {
            if legacy.isEmpty { return true }
            return matches(conditions: legacy, match: matchAll, context: context)
        }

        guard let audience = parsed as? [String: Any] else {
            PELogger.error(
                className: String(describing: IAMConditionEvaluator.self),
                message: "Message \(messageId): audience is neither an object nor an array — not eligible"
            )
            return false
        }

        let rawGroups = audience["groups"]
        if rawGroups == nil || rawGroups is NSNull {
            // No criteria — eligible for everyone.
            return true
        }

        guard let groups = rawGroups as? [Any] else {
            PELogger.error(
                className: String(describing: IAMConditionEvaluator.self),
                message: "Message \(messageId): audience groups is not an array — not eligible"
            )
            return false
        }

        if groups.isEmpty { return true }

        guard let topMatch = matchMode(in: audience, default: matchAny) else {
            PELogger.error(
                className: String(describing: IAMConditionEvaluator.self),
                message: "Message \(messageId): unknown audience match mode — not eligible"
            )
            return false
        }

        var groupsEvaluated = 0
        var anyMatched = false
        var allMatched = true

        for (index, element) in groups.enumerated() {
            guard let group = element as? [String: Any] else {
                PELogger.error(
                    className: String(describing: IAMConditionEvaluator.self),
                    message: "Message \(messageId): audience group \(index) is malformed — not eligible"
                )
                return false
            }

            // An empty AND-group is vacuously true, which would let one stray
            // empty group open the campaign to everybody. Skip it instead —
            // fail-open is the wrong direction for targeting.
            guard let conditions = group["conditions"] as? [Any], !conditions.isEmpty else {
                PELogger.debug(
                    className: String(describing: IAMConditionEvaluator.self),
                    message: "Message \(messageId): skipping audience group \(index) with no conditions"
                )
                continue
            }

            guard let groupMatch = matchMode(in: group, default: matchAll) else {
                PELogger.error(
                    className: String(describing: IAMConditionEvaluator.self),
                    message: "Message \(messageId): unknown group match mode — not eligible"
                )
                return false
            }

            groupsEvaluated += 1
            if matches(conditions: conditions, match: groupMatch, context: context) {
                anyMatched = true
                if topMatch == matchAny { return true }  // short-circuit OR
            } else {
                allMatched = false
                if topMatch == matchAll { return false } // short-circuit AND
            }
        }

        // Criteria were present but none usable (every group empty) — fail closed
        // rather than treating it as "no criteria".
        guard groupsEvaluated > 0 else {
            PELogger.debug(
                className: String(describing: IAMConditionEvaluator.self),
                message: "Message \(messageId): audience had groups but none evaluable — not eligible"
            )
            return false
        }

        return topMatch == matchAny ? anyMatched : allMatched
    }

    /// Every `field` named anywhere in the audience, both shapes, or nil when the
    /// JSON cannot be read.
    static func audienceFields(_ audienceJSON: Data?) -> Set<String>? {
        guard let audienceJSON = audienceJSON, !audienceJSON.isEmpty else { return [] }
        guard let parsed = try? JSONSerialization.jsonObject(with: audienceJSON,
                                                            options: [.fragmentsAllowed]) else {
            return nil
        }

        func fields(in conditions: [Any]) -> Set<String> {
            Set(conditions.compactMap { ($0 as? [String: Any]).flatMap { requiredString($0["field"]) } })
        }

        if let legacy = parsed as? [Any] {
            return fields(in: legacy)
        }

        guard let object = parsed as? [String: Any] else { return [] }

        let rawGroups = object["groups"]
        if rawGroups == nil || rawGroups is NSNull { return [] }
        guard let groups = rawGroups as? [Any] else { return nil }

        return groups.reduce(into: Set<String>()) { result, element in
            if let conditions = (element as? [String: Any])?["conditions"] as? [Any] {
                result.formUnion(fields(in: conditions))
            }
        }
    }

    static func isSubscriberBacked(_ field: String) -> Bool {
        field.hasPrefix(attributeNamespace) || subscriberBackedFields.contains(field)
    }

    // MARK: - Condition folding

    /// Folds `conditions` with `match` semantics: `all` fails on the first
    /// condition that does not hold, `any` passes on the first that does.
    static func matches(conditions: [Any], match: String, context: Context) -> Bool {
        for element in conditions {
            guard let condition = element as? [String: Any] else {
                return false  // malformed → fail closed
            }
            let holds = matches(condition: condition, context: context)
            if match == matchAny {
                if holds { return true }
            } else if !holds {
                return false
            }
        }
        // `all` reached the end with no failure; `any` found no match.
        return match == matchAll
    }

    /// Evaluates one `{field, type, op, value}` condition.
    static func matches(condition: [String: Any], context: Context) -> Bool {
        guard let field = requiredString(condition["field"]),
              let op = requiredString(condition["op"]),
              let rawValue = condition["value"] else {
            return false
        }

        // `segments` is set-valued rather than scalar: the subscriber has many,
        // so it takes intersection operators instead of equality.
        if field == segmentsField {
            guard context.resolvesSegments else { return false }
            return matchesSegments(op: op, value: rawValue, subscriberSegments: context.segments())
        }

        guard let userValue = context.value(field) else {
            // A missing value can't satisfy a positive match, but it does satisfy
            // the negative operators — an absent value is trivially not equal to,
            // and not in, the target set.
            return op == "neq" || op == "nin"
        }

        // Built-in fields carry their own type; custom attributes declare one,
        // and nil here means an attribute with no declared type.
        let type = fieldType(for: field, declared: condition["type"] as? String)
        let equalityType = type ?? .string

        switch op {
        case "eq":
            return compare(userValue, scalar(of: rawValue), as: equalityType) == 0
        case "neq":
            // Coercion failure fails the condition whichever way it points: if the
            // pair can't be compared under `type`, we can't claim they differ.
            guard let result = compare(userValue, scalar(of: rawValue), as: equalityType) else {
                return false
            }
            return result != 0
        case "gt":
            guard let result = orderedCompare(userValue, rawValue, as: type) else { return false }
            return result > 0
        case "lt":
            guard let result = orderedCompare(userValue, rawValue, as: type) else { return false }
            return result < 0
        case "gte":
            guard let result = orderedCompare(userValue, rawValue, as: type) else { return false }
            return result >= 0
        case "lte":
            guard let result = orderedCompare(userValue, rawValue, as: type) else { return false }
            return result <= 0
        case "in":
            return contains(rawValue, userValue, as: equalityType)
        case "nin":
            guard rawValue is [Any] else { return false }
            return !contains(rawValue, userValue, as: equalityType)
        case "contains":
            // Substring is meaningless for versions, numbers and booleans — and
            // `contains "1"` on a version matches 1/10/11/12/13/14/21.
            guard equalityType == .string, let target = scalar(of: rawValue) else { return false }
            // Every string contains the empty string. Spelled out because Swift's
            // `contains("")` answers false where Java's answers true, and one
            // payload serves both platforms.
            return target.isEmpty || userValue.contains(target)
        default:
            return false  // Unknown operator — fail closed
        }
    }

    // MARK: - Segments

    /// `segments` intersection. Deliberately not `in`/`nin`: those ask whether
    /// the subscriber's single value appears in a list, whereas these compare two
    /// lists. Any other operator fails, so `segments eq …` cannot be mistaken
    /// for membership.
    private static func matchesSegments(op: String,
                                        value: Any,
                                        subscriberSegments: Set<String>) -> Bool {
        guard let targets = value as? [Any] else { return false }

        // Segment names are matched exactly.
        let intersects = targets.contains { element in
            string(from: element).map { subscriberSegments.contains($0) } ?? false
        }

        switch op {
        case "includes": return intersects
        case "excludes": return !intersects
        default: return false
        }
    }

    // MARK: - Typed comparison

    /// Ordering comparison, restricted to types where it means something.
    ///
    /// A **declared** string or boolean fails: `gt` on those is an authoring
    /// mistake, and falling back to lexical order would silently answer a
    /// different question (`"9" > "10"` is true as text).
    ///
    /// An **undeclared** custom attribute infers an ordering instead of failing —
    /// numeric first, then version. Reaching for `gt` states the intent to order,
    /// and both of those are well-defined; lexical order never is.
    private static func orderedCompare(_ userValue: String, _ value: Any, as type: IAMFieldType?) -> Int? {
        guard let target = scalar(of: value) else { return nil }
        switch type {
        case .number, .version:
            return compare(userValue, target, as: type!)
        case .none:
            return compare(userValue, target, as: .number) ?? compare(userValue, target, as: .version)
        case .string, .boolean:
            return nil
        }
    }

    /// Three-way comparison under `type`, or nil when the pair cannot be
    /// compared — an unparseable number, a version codename such as
    /// `"VanillaIceCream"`, or a boolean that is not `true`/`false`.
    static func compare(_ userValue: String, _ target: String?, as type: IAMFieldType) -> Int? {
        guard let target = target else { return nil }
        switch type {
        case .string:
            if userValue == target { return 0 }
            return userValue < target ? -1 : 1
        case .number:
            // `Double("nan")` parses, and NaN answers false to every comparison —
            // which would read as "greater than". It has no ordering, so refuse it.
            guard let left = Double(userValue.trimmed), let right = Double(target.trimmed),
                  !left.isNaN, !right.isNaN else {
                return nil
            }
            if left == right { return 0 }
            return left < right ? -1 : 1
        case .boolean:
            guard let left = strictBoolean(userValue), let right = strictBoolean(target) else {
                return nil
            }
            if left == right { return 0 }
            return left ? 1 : -1
        case .version:
            return compareVersions(userValue, target)
        }
    }

    /// Strict `true`/`false` only — `"1"`/`"yes"` are not booleans.
    /// `String(describing: Bool)` produces exactly these two spellings.
    private static func strictBoolean(_ raw: String) -> Bool? {
        switch raw.trimmed.lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    /// Component-wise version comparison, so `14 > 8.1.0`. Missing components
    /// count as zero (`8.1` equals `8.1.0`). A pre-release or build suffix is
    /// dropped, and a non-numeric component makes the pair incomparable rather
    /// than throwing.
    private static func compareVersions(_ left: String, _ right: String) -> Int? {
        guard let leftParts = versionComponents(left),
              let rightParts = versionComponents(right) else {
            return nil
        }

        for index in 0..<max(leftParts.count, rightParts.count) {
            let leftPart = index < leftParts.count ? leftParts[index] : 0
            let rightPart = index < rightParts.count ? rightParts[index] : 0
            if leftPart != rightPart {
                return leftPart < rightPart ? -1 : 1
            }
        }
        return 0
    }

    private static func versionComponents(_ raw: String) -> [Int64]? {
        // "1.0.0-beta" / "1.0.0+build" compare on their numeric core.
        let core = raw.trimmed.prefix { $0 != "-" && $0 != "+" }
        guard !core.isEmpty else { return nil }

        var components: [Int64] = []
        for part in core.split(separator: ".", omittingEmptySubsequences: false) {
            guard let value = Int64(part) else { return nil }
            components.append(value)
        }
        return components
    }

    /// Membership using `type` semantics, so `in ["8.1.0"]` matches `"8.1"`.
    private static func contains(_ value: Any, _ userValue: String, as type: IAMFieldType) -> Bool {
        guard let list = value as? [Any] else { return false }
        return list.contains { compare(userValue, string(from: $0), as: type) == 0 }
    }

    // MARK: - Reading the payload

    /// Type for `field`, or nil for a custom attribute with no declared type.
    ///
    /// Built-ins are authoritative from the catalogue, so a payload cannot claim
    /// `os_version` is a string and turn `>` into lexical comparison. For custom
    /// attributes the declared type is the only source of truth — the backend
    /// stores whatever the app sent, so there is nothing else to consult.
    static func fieldType(for field: String, declared: String?) -> IAMFieldType? {
        if let builtIn = builtInFieldTypes[field] { return builtIn }
        guard let declared = declared else { return nil }
        return IAMFieldType(rawValue: declared.trimmed.lowercased())
    }

    /// `any`/`all` normalised, or nil when the value is not a recognised mode.
    static func matchMode(_ raw: String?) -> String? {
        switch raw?.trimmed.lowercased() {
        case matchAny: return matchAny
        case matchAll: return matchAll
        default: return nil
        }
    }

    /// Reads a `match` field, falling back to `fallback` when it is absent, JSON
    /// `null`, or blank. Only a genuinely unrecognised value returns nil (fail
    /// closed) — emitting explicit nulls for absent optional fields is common
    /// serializer behaviour and must not kill the campaign.
    static func matchMode(in json: [String: Any], default fallback: String) -> String? {
        guard let raw = json["match"], !(raw is NSNull) else { return fallback }
        guard let text = raw as? String else { return nil }
        return text.trimmed.isEmpty ? fallback : matchMode(text)
    }

    /// A required string field, or nil when absent, JSON `null`, or blank.
    static func requiredString(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Scalar view of a condition value for the single-value operators. The
    /// contract sends these as a one-element array
    /// (`{"op":"eq","value":["gold"]}`); a bare scalar is also accepted, for
    /// data stored by an older build.
    static func scalar(of value: Any) -> String? {
        if let list = value as? [Any] {
            return list.first.flatMap { string(from: $0) }
        }
        return string(from: value)
    }

    /// A JSON scalar as its string form. Booleans must be told apart from
    /// numbers explicitly — `Int`, `Double` and `Bool` all bridge to `NSNumber`,
    /// and a bool read as a number stringifies to `"1"` rather than `"true"`.
    static func string(from value: Any) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return String(number.boolValue)
            }
            return number.stringValue
        default:
            return nil  // null, or a nested object/array
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
