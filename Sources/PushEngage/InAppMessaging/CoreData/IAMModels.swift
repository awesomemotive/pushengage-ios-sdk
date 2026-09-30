import Foundation

// MARK: - Message Models

/// Represents the type of action that can be performed
/// Wire values per the cross-platform contract (flow doc §3.8/§7.1).
enum IAMActionType: String, Codable {
    // SDK-handled actions
    case openURL = "open_url"
    case requestNotificationPermission = "request_notification_permission"
    case dismiss = "dismiss"

    // Custom actions
    case custom = "custom"

    /// A wire value this build does not recognise — a dashboard typo, or an
    /// action type newer than the SDK. Deliberately NOT coerced to `.custom`:
    /// that invented an `actionId` the host app never configured, so the app
    /// could not tell it from a real custom action and "handling" it was
    /// likely to be wrong. Matches Android, where an unparseable type makes
    /// `createActionFromJson` return null and leaves the button inert.
    /// The raw value cannot collide with a real one.
    case unrecognised = "__pe_unrecognised__"

    /// Determines if the action is handled by the SDK
    var isSDKHandled: Bool {
        switch self {
        case .openURL, .requestNotificationPermission, .dismiss:
            return true
        case .custom, .unrecognised:
            return false
        }
    }
}

/// Represents an action that can be performed when interacting with an in-app message
struct IAMAction: Codable {
    let type: IAMActionType
    let parameters: [String: String]
    /// Human-readable button text; becomes `btn_text` in click analytics (§2.3).
    let label: String?

    enum CodingKeys: String, CodingKey {
        case type
        case parameters
        case label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)

        // Only the four canonical lowercase wire values are accepted, matching
        // Android's @SerializedName set. The former `dismiss_action` /
        // `custom_action` aliases were iOS's own older raw values, never backend
        // output (contract doc §7.1: "rename two raw values"), so accepting them
        // only made the same payload behave differently per platform.
        // Anything else decodes to `.unrecognised`
        // so THIS action goes inert while the message's other buttons still
        // work. Throwing here would take the whole map down: `decodedActions`
        // wraps the decode in `try?`, and `IAMMessageResponse` decodes the map
        // inline, so one bad action would blank every button or drop the
        // campaign at sync.
        self.type = IAMActionType(rawValue: typeString) ?? .unrecognised
        // Android models parameters as Map<String, Any> — tolerate scalar
        // non-string values (numbers, bools) by stringifying them.
        self.parameters = (try container.decodeIfPresent([String: IAMScalarString].self, forKey: .parameters))?
            .mapValues { $0.value } ?? [:]
        self.label = try container.decodeIfPresent(String.self, forKey: .label)
    }

    init(type: IAMActionType, parameters: [String: String], label: String? = nil) {
        self.type = type
        self.parameters = parameters
        self.label = label
    }
}

/// Decodes a JSON scalar (string, number, or bool) as its string form.
struct IAMScalarString: Codable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = String(double)
        } else if let bool = try? container.decode(Bool.self) {
            value = String(bool)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a scalar string/number/bool"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// Represents the type of frequency for message display
/// Wire values per the cross-platform contract (flow doc §3.7/§7.1).
enum IAMFrequencyType: String, Codable {
    /// Message shows exactly once, interval is ignored
    case oneTime = "one_time"
    /// Message shows repeatedly at fixed intervals, supports unlimited (-1)
    case recurring = "recurring"
    /// Message shows up to a maximum count with minimum interval between displays
    case capped = "capped"
    /// Unrecognized wire value — treated as no cap (forward-compatible, §3.7)
    case unknown = "unknown"

    /// Legacy wire values stored by older builds.
    static func fromWireValue(_ raw: String) -> IAMFrequencyType {
        if let standard = IAMFrequencyType(rawValue: raw) {
            return standard
        }
        switch raw {
        case "one-time", "ONE_TIME":
            return .oneTime
        case "RECURRING":
            return .recurring
        case "CAPPED":
            return .capped
        default:
            return .unknown
        }
    }
}

/// Represents the frequency settings for displaying a message.
///
/// `count` and `interval` are optional so **absent stays distinguishable from an
/// explicit `0`**: for `capped`, an absent `count` is malformed and fails closed,
/// while an explicit `interval: 0` is a legitimate "no spacing between displays".
/// Field applicability by type is `one_time` (neither), `recurring` (`interval`
/// only — it has no total cap), `capped` (`count` required, `interval` optional).
struct IAMFrequency: Codable {
    /// The type of frequency (one_time, recurring, or capped)
    let type: IAMFrequencyType
    /// Maximum number of displays. Required for `capped`; not read for `recurring`.
    let count: Int?
    /// Minimum seconds between displays. Required for `recurring`; optional for
    /// `capped`, where absent or non-positive means no spacing. Ignored for
    /// `one_time`.
    let interval: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case type
        case count
        case interval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        self.type = IAMFrequencyType.fromWireValue(typeString)
        self.count = try container.decodeIfPresent(Int.self, forKey: .count)
        self.interval = try container.decodeIfPresent(TimeInterval.self, forKey: .interval)
    }

    init(type: IAMFrequencyType, count: Int? = nil, interval: TimeInterval? = nil) {
        self.type = type
        self.count = count
        self.interval = interval
    }
}

/// Represents a trigger condition for displaying a message.
///
/// `event` is optional: `custom` triggers carry the event name the app passes
/// to `processTrigger`, but `auto` triggers are keyed off `type` alone and the
/// backend omits `event` for them (§3.5). A required `event` would fail the
/// whole campaigns decode when any auto campaign is present.
struct IAMTriggerCondition: Codable {
    let type: String
    let event: String?

    /// Legacy exact-equality parameter map, replaced by `match` + `conditions`.
    /// Still carried because campaigns stored by an earlier build remain in the
    /// store until the next sync full-replaces them.
    var parameters: [String: String]?

    /// `all` | `any` — how `conditions` combine. Only meaningful alongside them;
    /// defaults to `all`.
    let match: String?

    /// Conditions the trigger occurrence must satisfy, each
    /// `{field, type, op, value}` where `field` names a parameter the app passes
    /// to the trigger call. Held as raw JSON — `IAMConditionEvaluator` is the only
    /// thing that interprets it.
    ///
    /// The campaign states **requirements** and the app supplies the **data**:
    /// parameters no condition names are ignored, and absent or empty conditions
    /// match any occurrence of the event. `type` is always declared here — trigger
    /// parameter keys are developer-defined, so there is no catalogue to infer
    /// from — and absent means `string`.
    ///
    /// Flattened onto the trigger rather than nested, which would produce
    /// `conditions.conditions`; audience avoids that naturally because its two
    /// levels have distinct names (`groups` containing `conditions`).
    let conditions: IAMRawJSON?

    /// How long to wait after app open before showing the campaign, **in SECONDS**.
    /// Absent or `0` = show immediately.
    ///
    /// The unit is not in the field name — matching `frequency.interval` and
    /// `displayDuration`, which are also bare seconds — so treat this doc comment as
    /// the contract: **seconds, never milliseconds.** A millis regression would make
    /// every delay 1000× too short and look like "the delay does nothing".
    ///
    /// Honored for **`auto` (app open) triggers only**: the dashboard exposes the
    /// control solely under "App open", and the custom-trigger path ignores it even
    /// though the field lives on the shared trigger object.
    ///
    /// Nullable so "absent" stays distinguishable from an explicit `0`. It must be
    /// carried here even though only `IAMTriggerDelay` reads it, because the campaign
    /// persists its trigger by re-encoding this model — a field the model drops never
    /// reaches the stored JSON, and the delay would silently never apply.
    let delay: TimeInterval?

    init(type: String,
         event: String? = nil,
         parameters: [String: String]? = nil,
         match: String? = nil,
         conditions: IAMRawJSON? = nil,
         delay: TimeInterval? = nil) {
        self.type = type
        self.event = event
        self.parameters = parameters
        self.match = match
        self.conditions = conditions
        self.delay = delay
    }
}

// MARK: - Message Position

/// Represents the position where a message can be displayed
enum IAMPosition: String, Codable {
    case center
    case top
    case bottom
    case full
}

// MARK: - Analytics Event Type

/// Types of analytics event queued for upload.
///
/// Only the two the backend represents. A `close` type used to be recorded and
/// then dropped by the uploader, which read as a metric that existed when it did
/// not: `Closes` is derived by the backend from a click whose `btn_type` is
/// `dismiss`, so an explicit dismiss-button tap is a [click] like any other.
/// Non-button dismissals (tap-outside, swipe, back, auto-dismiss on
/// `displayDuration`) are deliberately not reported at all — `close` measures
/// explicit rejection, and folding in a timer expiry would change what it means.
///
/// The stored `eventType` column is retained even though only these two are
/// written, so adding a third needs no migration.
enum IAMAnalyticsEventType: String, Codable {
    /// When message is presented to the user
    case impression
    /// When a button is tapped in the in-app message webview
    case click
}

// MARK: - Trigger Type

/// Represents different types of triggers
enum IAMTriggerType: String, Codable {
    case auto
    case custom
}

// MARK: - Error Types

/// Represents errors that can occur in the In-App Messaging system
enum IAMError: Error {
    case invalidData
    case invalidMessageFormat
    case messageExpired
    case storageError
    case networkError
    case disabled
    
    var localizedDescription: String {
        switch self {
        case .invalidData:
            return "Invalid data format"
        case .invalidMessageFormat:
            return "Invalid message format"
        case .messageExpired:
            return "Message has expired"
        case .storageError:
            return "Storage operation failed"
        case .networkError:
            return "Network operation failed"
        case .disabled:
            return "In-App Messaging is disabled"
        }
    }
}

// MARK: - Message Response Model

/// Represents the response format for messages from the server
struct IAMMessageResponse: Codable {
    let id: String
    let position: IAMPosition
    let htmlContent: String
    let displayDuration: Int64
    let shouldDismissOnTap: Bool
    let actions: [String: IAMAction]
    let startDate: Date?
    let endDate: Date?
    let priority: Int16
    /// Held as raw JSON rather than a typed model — see `IAMRawJSON`. The shape is
    /// `{match, groups:[{match, conditions:[…]}]}`, with a bare condition array
    /// still accepted from older stored data. `IAMConditionEvaluator` is the only
    /// thing that interprets it.
    let audience: IAMRawJSON?
    let frequency: IAMFrequency?
    let trigger: IAMTriggerCondition

    enum CodingKeys: String, CodingKey {
        case id
        case position
        case htmlContent
        case displayDuration
        case shouldDismissOnTap
        case actions
        case startDate
        case endDate
        case priority
        case audience
        case frequency
        case trigger
    }

    /// Tolerant decode matching Android's defaults: the live backend omits
    /// `displayDuration` (and may omit other scalars), and with the synthesized
    /// Decodable a single missing key failed the WHOLE campaigns array
    /// (all-or-nothing decode) — no messages would ever sync. Required fields
    /// stay required: id, position, htmlContent, trigger.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        position = try container.decode(IAMPosition.self, forKey: .position)
        htmlContent = try container.decode(String.self, forKey: .htmlContent)
        displayDuration = try container.decodeIfPresent(Int64.self, forKey: .displayDuration) ?? 0
        shouldDismissOnTap = try container.decodeIfPresent(Bool.self, forKey: .shouldDismissOnTap) ?? false
        actions = try container.decodeIfPresent([String: IAMAction].self, forKey: .actions) ?? [:]
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        priority = try container.decodeIfPresent(Int16.self, forKey: .priority) ?? 1
        audience = try container.decodeIfPresent(IAMRawJSON.self, forKey: .audience)
        frequency = try container.decodeIfPresent(IAMFrequency.self, forKey: .frequency)
        trigger = try container.decode(IAMTriggerCondition.self, forKey: .trigger)
    }

    init(id: String,
         position: IAMPosition,
         htmlContent: String,
         displayDuration: Int64,
         shouldDismissOnTap: Bool,
         actions: [String: IAMAction],
         startDate: Date?,
         endDate: Date?,
         priority: Int16,
         audience: IAMRawJSON?,
         frequency: IAMFrequency?,
         trigger: IAMTriggerCondition) {
        self.id = id
        self.position = position
        self.htmlContent = htmlContent
        self.displayDuration = displayDuration
        self.shouldDismissOnTap = shouldDismissOnTap
        self.actions = actions
        self.startDate = startDate
        self.endDate = endDate
        self.priority = priority
        self.audience = audience
        self.frequency = frequency
        self.trigger = trigger
    }
} 
