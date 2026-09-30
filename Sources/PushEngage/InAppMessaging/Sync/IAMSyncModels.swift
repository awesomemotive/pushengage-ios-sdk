import Foundation

// MARK: - Network constants

/// IAM backend configuration (contract §2), mirroring Android's PEConstants.
enum IAMNetworkConstants {

    /// IAM API relative paths (appended to the discovered/base host, which
    /// already ends in /p/v1/). The metadata endpoint is fetched from the IAM
    /// base host; campaigns/analytics use the hosts the metadata advertises.
    static let metadataPath = "iam/campaigns/metadata"
    static let campaignsPath = "iam/campaigns"
    static let analyticsPath = "iam/campaigns/analytics"

    /// In-App Messaging base host (metadata + fallback for campaigns and
    /// analytics). Distinct from the notification CDN — IAM is served from its
    /// own host.
    static let stagingIAMBaseURL = "https://staging-dexter2.pushengage.com/p/v1/"
    static let productionIAMBaseURL = "https://clients-api.pushengage.com/p/v1/"

    static let activeStatus = "active"
}

// MARK: - Wire models (contract §2)

/// Standard PushEngage API envelope wrapping every IAM response:
/// `{ "error_code": 0, "data": { ... }, "error_message": "..." }`.
struct IAMEnvelope<T: Decodable>: Decodable {
    let errorCode: Int?
    let errorMessage: String?
    let data: T?

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case data
    }
}

/// Response of GET {base}/iam/campaigns/metadata?site_key=X (contract §2.1):
/// a cheap discovery + gate document — version drives whether campaigns are
/// re-fetched, iam_status gates display, and the api hosts tell the SDK where
/// to fetch campaigns / post analytics.
struct IAMMetadataResponse: Decodable {
    let version: String?
    let siteId: Int64?
    let iamStatus: String?
    let api: Api?

    enum CodingKeys: String, CodingKey {
        case version
        case siteId = "site_id"
        case iamStatus = "iam_status"
        case api
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `version` is opaque and read as a string, but the backend may send a
        // JSON number (live staging sends an epoch-ms number, contract §2.1) —
        // a plain String decode THREW on it and killed the whole sync before
        // the campaigns were ever fetched. Coerce numbers to their string form,
        // matching Android's Gson behavior.
        if let stringVersion = try? container.decode(String.self, forKey: .version) {
            version = stringVersion
        } else if let intVersion = try? container.decode(Int64.self, forKey: .version) {
            version = String(intVersion)
        } else if let doubleVersion = try? container.decode(Double.self, forKey: .version) {
            version = String(doubleVersion)
        } else {
            version = nil // absent or null
        }
        siteId = try container.decodeIfPresent(Int64.self, forKey: .siteId)
        iamStatus = try container.decodeIfPresent(String.self, forKey: .iamStatus)
        api = try container.decodeIfPresent(Api.self, forKey: .api)
    }

    struct Api: Decodable {
        let backend: String?
        let backendCdn: String?
        let iamAnalytics: String?
        let log: String?

        enum CodingKeys: String, CodingKey {
            case backend
            case backendCdn = "backend_cdn"
            case iamAnalytics = "iam_analytics"
            case log
        }
    }
}

/// Body of POST {iam_analytics}/iam/campaigns/analytics?site_key=X (§2.3).
/// One POST per event; impression and click are 0/1. btn_* only for clicks.
struct IAMAnalyticsPayload: Codable, Equatable {
    let campaignId: String
    let impression: Int
    let click: Int
    var btnId: String?
    var btnText: String?
    var btnType: String?

    enum CodingKeys: String, CodingKey {
        case campaignId = "campaign_id"
        case impression
        case click
        case btnId = "btn_id"
        case btnText = "btn_text"
        case btnType = "btn_type"
    }
}

/// Per-payload accounting for an analytics upload batch (§2.3).
struct IAMReportOutcome {

    /// Payload positions the caller may clear: delivered, or permanently rejected
    /// by the backend and so undeliverable.
    let syncedIndices: [Int]

    /// True when every payload in the batch is accounted for.
    let allSynced: Bool

    /// The error that stopped the batch early; nil when `allSynced` is true.
    let failure: Error?

    init(syncedIndices: [Int], allSynced: Bool, failure: Error? = nil) {
        self.syncedIndices = syncedIndices
        self.allSynced = allSynced
        self.failure = failure
    }
}

/// Outcome of a metadata-gated campaign sync (contract §1–§2).
struct IAMCampaignSyncResult {
    enum Status {
        /// New campaign set to full-replace locally, plus version and hosts to persist.
        case active
        /// IAM is off for the site; local campaigns should be purged.
        case inactive
        /// Metadata cache fresh or version unchanged; do nothing.
        case unchanged
    }

    let status: Status
    var version: String?
    var campaigns: [IAMMessageResponse] = []
    var campaignsHost: String?
    var analyticsHost: String?

    static func unchanged() -> IAMCampaignSyncResult { IAMCampaignSyncResult(status: .unchanged) }
    static func inactive() -> IAMCampaignSyncResult { IAMCampaignSyncResult(status: .inactive) }
}
