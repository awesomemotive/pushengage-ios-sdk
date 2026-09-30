import Foundation
import UIKit

/// Values audience conditions resolve against: locally set attributes, the
/// device's own properties, and the cached subscriber-backed snapshot.
///
/// Mirrors Android's `IAMDevicePropertiesManager`. String comparison is exact
/// and case-sensitive with no normalisation, so every value here has to keep the
/// format the dashboard targets.
final class IAMDeviceProperties {

    private let defaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
    }

    // MARK: - Locally set attributes

    /// Value for `field`: a locally set attribute wins, otherwise the built-in
    /// device property is computed.
    func userAttribute(for field: String) -> String? {
        if let stored = defaults.string(forKey: StorageKey.attributePrefix + field) {
            return stored
        }
        return deviceProperty(for: field)
    }

    func setUserAttribute(_ value: String, for field: String) {
        defaults.set(value, forKey: StorageKey.attributePrefix + field)
    }

    func removeUserAttribute(for field: String) {
        defaults.removeObject(forKey: StorageKey.attributePrefix + field)
    }

    func clearUserAttributes() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(StorageKey.attributePrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Built-in device properties

    private func deviceProperty(for field: String) -> String? {
        switch field {
        case "platform":
            // Capitalised as the platform spells itself, matching Android's
            // "Android". Targeting is exact, so "ios" never matches.
            return "iOS"
        case "os_version":
            // Marketing version ("18", "8.1.0"), matching Android's
            // Build.VERSION.RELEASE so one audience vocabulary works across both.
            // Dotted, so it is compared component-wise and never as a number.
            return UIDevice.current.systemVersion
        case "language":
            // Language alone ("en"), not the full preferred-language tag
            // ("en-US"): Android sends Locale.getDefault().language, and the
            // dashboard's ISO language dropdown targets that form.
            return Locale.current.languageCode
        case "device_region":
            // Device locale region, deliberately NOT named `country`: the backend
            // also has an IP-derived country and the two genuinely disagree, so
            // `country` is left unresolvable rather than silently matching one.
            return Locale.current.regionCode
        case "timezone":
            return TimeZone.current.identifier
        case "app_version":
            return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        case "notification_enabled":
            // Authorization status is only available asynchronously, so it is
            // read during the app-open pass and cached for synchronous
            // evaluation. Unresolvable until then, which fails a positive
            // condition closed rather than guessing.
            return cachedNotificationPermission.map { String($0) }
        default:
            // Deliberately unresolvable, so a condition fails closed rather than
            // mis-targeting: `device_model` (opaque, OEM-dependent casing on
            // Android and marketing-name-free here) and bare `country`.
            return nil
        }
    }

    /// Last known notification-authorization state, or nil if never read.
    private var cachedNotificationPermission: Bool? {
        defaults.object(forKey: StorageKey.notificationEnabled) as? Bool
    }

    /// Records the notification-authorization state for audience evaluation.
    func cacheNotificationPermission(enabled: Bool) {
        defaults.set(enabled, forKey: StorageKey.notificationEnabled)
    }

    // MARK: - Subscriber-backed snapshot

    /// Replaces the cached subscriber-backed audience data with what the backend
    /// returned.
    ///
    /// Cached so it survives process death — the fetch runs once per app open,
    /// and evaluating against the previous snapshot beats evaluating against
    /// nothing.
    ///
    /// - Parameters:
    ///   - segments: the subscriber's segment names (set-valued)
    ///   - attributes: custom attributes, stored under the `attr.` namespace so a
    ///     marketer-defined key can never shadow a built-in field
    ///   - scalars: subscriber-backed scalars keyed by their audience field name
    ///     (`city`, `state`, `geo_country`, `has_unsubscribed`)
    ///   - identity: the subscriber this snapshot describes. Stored with it, so a
    ///     later identity change can tell that the snapshot describes someone else.
    func applySubscriberState(segments: Set<String>,
                              attributes: [String: String],
                              scalars: [String: String],
                              identity: String) {
        // Audience evaluation reads this snapshot synchronously on the main thread,
        // so it is written there too — the fetch completes on a network queue.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.applySubscriberState(segments: segments,
                                           attributes: attributes,
                                           scalars: scalars,
                                           identity: identity)
            }
            return
        }

        let namespacePrefix = StorageKey.attributePrefix + IAMConditionEvaluator.attributeNamespace

        // Scalars are stored under bare field names, so they cannot be found by
        // prefix. The keys written last time are remembered rather than
        // hard-coding a list here, which would duplicate the field catalogue in
        // IAMConditionEvaluator and be free to drift from it.
        let previousScalarFields = defaults.stringArray(forKey: StorageKey.scalarKeys) ?? []

        // New values land before any old one is cleared, so an evaluation
        // interleaved with this reads either snapshot but never a gap between them.
        var liveKeys: Set<String> = []
        for (key, value) in attributes {
            let storageKey = namespacePrefix + key
            defaults.set(value, forKey: storageKey)
            liveKeys.insert(storageKey)
        }
        for (field, value) in scalars {
            let storageKey = StorageKey.attributePrefix + field
            defaults.set(value, forKey: storageKey)
            liveKeys.insert(storageKey)
        }
        defaults.set(Array(segments), forKey: StorageKey.segments)
        defaults.set(Array(scalars.keys), forKey: StorageKey.scalarKeys)

        // Replace rather than merge: anything the new snapshot omits must
        // disappear, or a stale value outlives the data it came from — a
        // subscriber who moves keeps their old city, and a site that disables geo
        // keeps geo forever.
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(namespacePrefix) && !liveKeys.contains(key) {
            defaults.removeObject(forKey: key)
        }
        for field in previousScalarFields {
            let storageKey = StorageKey.attributePrefix + field
            if !liveKeys.contains(storageKey) {
                defaults.removeObject(forKey: storageKey)
            }
        }

        defaults.set(identity, forKey: StorageKey.subscriberIdentity)
        defaults.set(true, forKey: StorageKey.subscriberStateLoaded)

        PELogger.debug(
            className: String(describing: IAMDeviceProperties.self),
            message: "IAM subscriber state applied: \(segments.count) segment(s), "
                + "\(attributes.count) attribute(s), \(scalars.count) scalar(s)"
        )
    }

    /// Drops the cached snapshot when it belongs to a different subscriber.
    ///
    /// A re-subscribe issues a new hash, and unsubscribe clears it. The snapshot
    /// would otherwise keep answering with the previous subscriber's segments and
    /// attributes — and because the loaded flag stays set, deferral would not
    /// engage to stop it. Only the fetch refreshes it, so without this a failed or
    /// absent fetch leaves the wrong person's data in place indefinitely.
    func invalidateSubscriberStateIfIdentityChanged(_ identity: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.invalidateSubscriberStateIfIdentityChanged(identity)
            }
            return
        }

        let stored = defaults.string(forKey: StorageKey.subscriberIdentity) ?? ""
        guard stored != identity else { return }
        guard hasSubscriberState || !stored.isEmpty else {
            defaults.set(identity, forKey: StorageKey.subscriberIdentity)
            return
        }

        PELogger.debug(
            className: String(describing: IAMDeviceProperties.self),
            message: "IAM subscriber identity changed — discarding the cached snapshot"
        )
        clearSubscriberState()
        defaults.set(identity, forKey: StorageKey.subscriberIdentity)
    }

    /// Removes everything the subscriber fetch contributed, leaving the state
    /// reading as never-fetched so subscriber-backed conditions defer.
    ///
    /// Locally set attributes are untouched: they are the app's own state and live
    /// outside the `attr.` namespace.
    func clearSubscriberState() {
        let namespacePrefix = StorageKey.attributePrefix + IAMConditionEvaluator.attributeNamespace
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(namespacePrefix) {
            defaults.removeObject(forKey: key)
        }
        for field in defaults.stringArray(forKey: StorageKey.scalarKeys) ?? [] {
            defaults.removeObject(forKey: StorageKey.attributePrefix + field)
        }
        defaults.removeObject(forKey: StorageKey.scalarKeys)
        defaults.removeObject(forKey: StorageKey.segments)
        defaults.removeObject(forKey: StorageKey.subscriberStateLoaded)
        defaults.removeObject(forKey: StorageKey.subscriberIdentity)
    }

    /// Whether subscriber-backed data has ever been fetched successfully.
    ///
    /// Audience conditions on subscriber-backed fields are **deferred** rather
    /// than failed while this is false: failing closed would mean such a campaign
    /// never shows on a fresh install, and failing open on a negative operator
    /// would show it to everyone.
    var hasSubscriberState: Bool {
        defaults.bool(forKey: StorageKey.subscriberStateLoaded)
    }

    /// The subscriber's segments, empty when none are cached.
    var segments: Set<String> {
        Set(defaults.stringArray(forKey: StorageKey.segments) ?? [])
    }

    // MARK: - Keys

    /// Where this type persists things. Not private, so anything that needs to
    /// clear the namespace can name it rather than duplicate the literals.
    enum StorageKey {
        /// Unchanged from the pre-catalogue implementation, so attributes set by
        /// an earlier build keep resolving.
        static let attributePrefix = "pe_user_attribute_"
        static let segments = "pe_iam_segments"
        /// Field names written by the last `applySubscriberState`, so the next one
        /// can clear them.
        static let scalarKeys = "pe_iam_subscriber_scalar_keys"
        static let subscriberStateLoaded = "pe_iam_subscriber_state_loaded"
        /// Subscriber the cached snapshot describes, so a new identity discards it.
        static let subscriberIdentity = "pe_iam_subscriber_identity"
        static let notificationEnabled = "pe_iam_notification_enabled"
    }
}
