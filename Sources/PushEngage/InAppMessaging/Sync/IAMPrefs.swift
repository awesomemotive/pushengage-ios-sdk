import Foundation

/// Persisted IAM metadata state (contract §2.1) — discovered version, status,
/// analytics host, the local fetch timestamp for the 1h cache, and an optional
/// base-host override. Mirrors Android's PEPrefs IAM accessors.
final class IAMPrefs {

    static let shared = IAMPrefs()

    private let defaults: UserDefaults

    private enum Key {
        static let version = "com.pushengage.iam.version"
        static let status = "com.pushengage.iam.status"
        static let analyticsUrl = "com.pushengage.iam.analyticsUrl"
        static let metadataFetchedAt = "com.pushengage.iam.metadataFetchedAt"
        static let baseUrl = "com.pushengage.iam.baseUrl"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Campaign-set version from the last successful sync (§2.1). Opaque.
    var iamVersion: String {
        get { defaults.string(forKey: Key.version) ?? "" }
        set { defaults.set(newValue, forKey: Key.version) }
    }

    var iamStatus: String {
        get { defaults.string(forKey: Key.status) ?? "" }
        set { defaults.set(newValue, forKey: Key.status) }
    }

    /// Analytics host advertised by the metadata `api` block; empty = fall
    /// back to the IAM base host.
    var iamAnalyticsUrl: String {
        get { defaults.string(forKey: Key.analyticsUrl) ?? "" }
        set { defaults.set(newValue, forKey: Key.analyticsUrl) }
    }

    /// When the metadata document was last fetched (epoch seconds); drives the
    /// 1h freshness gate. 0 = never fetched.
    var iamMetadataFetchedAt: TimeInterval {
        get { defaults.double(forKey: Key.metadataFetchedAt) }
        set { defaults.set(newValue, forKey: Key.metadataFetchedAt) }
    }

    /// IAM base-host override (where metadata is fetched). Empty in production
    /// — the SDK then uses the per-environment IAM constant.
    var iamBaseUrl: String {
        get { defaults.string(forKey: Key.baseUrl) ?? "" }
        set { defaults.set(newValue, forKey: Key.baseUrl) }
    }
}

/// IAM runtime configuration pushed in by PEManager: the site key (App ID)
/// and environment. IAM needs only the App ID to fetch campaigns — not a push
/// subscription — so this is deliberately independent of the subscriber state.
final class IAMConfiguration {

    static let shared = IAMConfiguration()

    var siteKey: String?
    var environment: PEEnvironment = .production
}
