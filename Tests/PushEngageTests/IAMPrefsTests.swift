import XCTest
@testable import PushEngage

/// IAM metadata persistence (contract §2.1): default values for a fresh
/// install, set/get round-trips, and persistence across IAMPrefs instances
/// backed by the same defaults suite.
final class IAMPrefsTests: XCTestCase {

    private static let suiteName = "IAMPrefsTests"

    private var defaults: UserDefaults!
    private var prefs: IAMPrefs!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        defaults.removePersistentDomain(forName: Self.suiteName)
        prefs = IAMPrefs(defaults: defaults)
    }

    override func tearDown() {
        UserDefaults(suiteName: Self.suiteName)?.removePersistentDomain(forName: Self.suiteName)
        super.tearDown()
    }

    // MARK: - Fresh-install defaults

    func testFreshInstallDefaults() {
        XCTAssertEqual(prefs.iamVersion, "")
        XCTAssertEqual(prefs.iamStatus, "")
        XCTAssertEqual(prefs.iamAnalyticsUrl, "")
        XCTAssertEqual(prefs.iamMetadataFetchedAt, 0)
        XCTAssertEqual(prefs.iamBaseUrl, "")
    }

    // MARK: - Round trips

    func testVersionRoundTrips() {
        prefs.iamVersion = "42"
        XCTAssertEqual(prefs.iamVersion, "42")
    }

    func testStatusRoundTrips() {
        prefs.iamStatus = "active"
        XCTAssertEqual(prefs.iamStatus, "active")
    }

    func testAnalyticsUrlRoundTrips() {
        prefs.iamAnalyticsUrl = "https://analytics.example.com"
        XCTAssertEqual(prefs.iamAnalyticsUrl, "https://analytics.example.com")
    }

    func testMetadataFetchedAtRoundTrips() {
        let now = Date().timeIntervalSince1970
        prefs.iamMetadataFetchedAt = now
        XCTAssertEqual(prefs.iamMetadataFetchedAt, now, accuracy: 0.001)
    }

    func testBaseUrlRoundTrips() {
        prefs.iamBaseUrl = "https://staging.example.com"
        XCTAssertEqual(prefs.iamBaseUrl, "https://staging.example.com")
    }

    // MARK: - Persistence across instances

    func testValuesPersistAcrossInstancesSharingTheSameDefaults() {
        prefs.iamVersion = "7"
        prefs.iamStatus = "inactive"

        let second = IAMPrefs(defaults: defaults)
        XCTAssertEqual(second.iamVersion, "7")
        XCTAssertEqual(second.iamStatus, "inactive")
    }

    // MARK: - Runtime configuration

    func testConfigurationDefaultsToProductionWithNoSiteKey() {
        let configuration = IAMConfiguration()
        XCTAssertNil(configuration.siteKey)
        XCTAssertEqual(configuration.environment, .production)
    }
}
