import Foundation

/// Maps a subscriber-details payload onto the audience field vocabulary.
enum IAMSubscriberStateMapper {

    /// Exactly the fields audience targeting needs.
    ///
    /// **The `fields` parameter must never be omitted.** The backend validator
    /// defaults an absent parameter to *every* field — including `email`,
    /// `first_name`, `last_name` and `date_of_birth` — so this list is hard-coded
    /// to keep PII off the device and out of debug logs.
    static let requestedFields = [
        "segments", "attributes", "city", "state", "country", "has_unsubscribed"
    ]

    /// The subscriber-backed audience data, split the way it is stored: segments
    /// are set-valued, attributes are namespaced under `attr.`, and scalars are
    /// keyed by their audience field name.
    struct State {
        let segments: Set<String>
        let attributes: [String: String]
        let scalars: [String: String]
    }

    static func state(from rawFields: [String: Any]) -> State {
        var segments: Set<String> = []
        if let rawSegments = rawFields["segments"] as? [Any] {
            for segment in rawSegments {
                if let name = IAMConditionEvaluator.string(from: segment) {
                    segments.insert(name)
                }
            }
        }

        var attributes: [String: String] = [:]
        if let rawAttributes = rawFields["attributes"] as? [String: Any] {
            for (key, value) in rawAttributes {
                if let text = IAMConditionEvaluator.string(from: value) {
                    attributes[key] = text
                }
            }
        }

        var scalars: [String: String] = [:]
        put(&scalars, "city", rawFields["city"])
        put(&scalars, "state", rawFields["state"])
        // The backend calls the IP-derived value `country`; the audience field is
        // `geo_country`, deliberately distinct from the locale's `device_region`
        // because the two genuinely disagree (US locale on an Indian IP).
        put(&scalars, "geo_country", rawFields["country"])

        // Numeric 0/1 on the wire; the audience field is a boolean. A value that is
        // neither is dropped, so the condition fails closed rather than coercing.
        switch rawFields["has_unsubscribed"] {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                scalars["has_unsubscribed"] = String(number.boolValue)
            } else {
                scalars["has_unsubscribed"] = String(number.intValue != 0)
            }
        default:
            break
        }

        return State(segments: segments, attributes: attributes, scalars: scalars)
    }

    private static func put(_ target: inout [String: String], _ field: String, _ value: Any?) {
        guard let value = value,
              let text = IAMConditionEvaluator.string(from: value),
              !text.isEmpty else {
            return
        }
        target[field] = text
    }
}

/// Supplies the subscriber-backed audience data.
///
/// A protocol so the app-open path can be exercised without the network, and so
/// the IAM layer reaches the subscriber stack only through its public API.
protocol IAMSubscriberStateProviding {

    /// Whether a subscriber exists yet.
    ///
    /// The hash *is* the subscriber identity, so this stays false until
    /// `subscriber/add` has completed — which needs push configured at all. An
    /// IAM-only integration therefore never resolves the subscriber-backed fields.
    var hasSubscriber: Bool { get }

    /// Identifies the current subscriber, empty when there is none. A cached
    /// snapshot is discarded when this no longer matches the one it was taken
    /// under, so a re-subscribe cannot inherit the previous subscriber's targeting.
    var subscriberIdentity: String { get }

    /// Fetches `fields` for the current subscriber; nil on any failure.
    func fetchSubscriberFields(_ fields: [String], completion: @escaping ([String: Any]?) -> Void)
}

/// Production source: the public `PushEngage.getSubscriberDetails` API.
struct IAMSubscriberStateProvider: IAMSubscriberStateProviding {

    var hasSubscriber: Bool {
        !subscriberIdentity.isEmpty
    }

    var subscriberIdentity: String {
        UserDefaultManager().subscriberHash
    }

    func fetchSubscriberFields(_ fields: [String], completion: @escaping ([String: Any]?) -> Void) {
        PushEngage.getSubscriberDetails(for: fields) { response, error in
            if let error = error {
                PELogger.error(
                    className: String(describing: IAMSubscriberStateProvider.self),
                    message: "IAM subscriber-state fetch failed: \(error.localizedDescription)"
                )
                completion(nil)
                return
            }
            completion(response?.rawFields)
        }
    }
}
