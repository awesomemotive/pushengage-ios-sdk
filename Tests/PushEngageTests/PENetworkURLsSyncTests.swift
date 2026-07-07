import XCTest
@testable import PushEngageExtension

/// A URL accessor read *before* the app writes `SyncAPIData` to the shared
/// suite must still pick up the server-configured endpoint once it lands.
final class PENetworkURLsSyncTests: XCTestCase {

    private func syncData(backendCdn: String) -> SyncAPIData {
        let json = "{\"api\":{\"backend_cdn\":\"\(backendCdn)\"}}".data(using: .utf8)!
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(SyncAPIData.self, from: json)
    }

    func test_backendCdnBaseURL_reflectsSyncDataWrittenAfterFirstRead() {
        let suite = makeSuite("pe-syncurl-cdn-\(UUID().uuidString)")
        let userDefaults = UserDefaultManager(userDefaults: suite)
        userDefaults.environment = .production

        // First read, before any sync data exists → hardcoded production fallback.
        XCTAssertEqual(PENetworkURLs.backendCdnBaseURL(userDefaults),
                       PENetworkURLs.productionBackendCdnURL)

        // Server sync lands the customer CDN endpoint AFTER that first read.
        userDefaults.save(object: syncData(backendCdn: "https://cdn.custom.test/p/v1/"),
                          for: UserDefaultConstant.pushEngageSyncApi)

        // Must now reflect it. A cached static-let snapshot would still return the fallback.
        XCTAssertEqual(PENetworkURLs.backendCdnBaseURL(userDefaults),
                       "https://cdn.custom.test/p/v1/")
    }
}
