import XCTest
@testable import PushEngage
@testable import PushEngageExtension
/// Unit tests for `Utility.buildUserAgent` — the slash-delimited SDK User-Agent
/// composition. Shape must mirror the Android counterpart for cross-platform
/// parsing parity:
///
///     iOS/<osVer>/<deviceModel>/<bundleId>/<appVer>/SDK/<sdkVer>/<flavor>[/<wrapperVer>]
final class UserAgentBuilderTests: XCTestCase {

    private var userDefaults: MockUserDefaultsService!

    override func setUp() {
        super.setUp()
        userDefaults = MockUserDefaultsService()
    }

    override func tearDown() {
        userDefaults = nil
        super.tearDown()
    }

    // MARK: - Shape

    func test_ua_startsWith_iOS_literal() {
        let ua = Utility.buildUserAgent(userDefaults: userDefaults)
        XCTAssertTrue(ua.hasPrefix("iOS/"), "UA must start with 'iOS/' literal — got \(ua)")
    }

    func test_ua_containsSDKLiteralAndVersion() {
        let ua = Utility.buildUserAgent(userDefaults: userDefaults)
        XCTAssertTrue(ua.contains("/SDK/\(NetworkConstants.sdkVersion)/"),
                      "UA must contain '/SDK/<sdkVersion>/' tail — got \(ua)")
    }

    func test_ua_endsWithDefaultFlavor_whenPlatformNotSet() {
        userDefaults.platform = nil
        userDefaults.wrapperVersion = nil
        let ua = Utility.buildUserAgent(userDefaults: userDefaults)
        XCTAssertTrue(ua.hasSuffix("/\(PEPlatform.iOS)"),
                      "UA must end with default '/iOS' flavor when prefs empty — got \(ua)")
    }

    func test_ua_endsWithCustomFlavor_whenPlatformSet() {
        userDefaults.platform = PEPlatform.flutterIOS
        userDefaults.wrapperVersion = nil
        let ua = Utility.buildUserAgent(userDefaults: userDefaults)
        XCTAssertTrue(ua.hasSuffix("/\(PEPlatform.flutterIOS)"),
                      "UA must end with set flavor when no wrapper version — got \(ua)")
    }

    func test_ua_appendsWrapperVersion_whenSet() {
        userDefaults.platform = PEPlatform.reactNativeIOS
        userDefaults.wrapperVersion = "2.3.0"
        let ua = Utility.buildUserAgent(userDefaults: userDefaults)
        XCTAssertTrue(ua.hasSuffix("/\(PEPlatform.reactNativeIOS)/2.3.0"),
                      "UA must end with '/<flavor>/<wrapperVer>' when both set — got \(ua)")
    }

    func test_ua_omitsWrapperVersionSlot_whenWrapperVersionEmpty() {
        userDefaults.platform = PEPlatform.flutterIOS
        userDefaults.wrapperVersion = ""
        let ua = Utility.buildUserAgent(userDefaults: userDefaults)
        XCTAssertFalse(ua.hasSuffix("/"),
                       "UA must not have a trailing empty wrapper-version slot — got \(ua)")
        XCTAssertTrue(ua.hasSuffix("/\(PEPlatform.flutterIOS)"),
                      "UA must end with the flavor segment when wrapper version is empty — got \(ua)")
    }

    func test_ua_doesNotContainSiteKey() {
        // Site key now travels in the X-Pe-App-Id header (PERouter), not in the UA.
        // Older UA format had "/app-<siteKey>" — this test locks in the removal.
        userDefaults.siteKey = "ABCDEFGHIJ"
        let ua = Utility.buildUserAgent(userDefaults: userDefaults)
        XCTAssertFalse(ua.contains("ABCDEFGHIJ"),
                       "UA must not embed the site key — that data belongs in X-Pe-App-Id header. Got \(ua)")
    }

    // MARK: - Segment count parity

    func test_ua_has8Segments_whenNoWrapperVersion() {
        // iOS / osVer / deviceModel / bundleId / appVer / SDK / sdkVer / flavor → 8 segments
        userDefaults.platform = PEPlatform.iOS
        userDefaults.wrapperVersion = nil
        let ua = Utility.buildUserAgent(userDefaults: userDefaults)
        let segments = ua.split(separator: "/", omittingEmptySubsequences: false)
        XCTAssertEqual(segments.count, 8,
                       "Native UA must have exactly 8 slash-separated segments — got \(segments.count): \(ua)")
    }

    func test_ua_has9Segments_whenWrapperVersionSet() {
        userDefaults.platform = PEPlatform.flutterIOS
        userDefaults.wrapperVersion = "2.3.0"
        let ua = Utility.buildUserAgent(userDefaults: userDefaults)
        let segments = ua.split(separator: "/", omittingEmptySubsequences: false)
        XCTAssertEqual(segments.count, 9,
                       "Wrapped UA must have exactly 9 slash-separated segments — got \(segments.count): \(ua)")
    }

    // MARK: - Sanitization wired in

    func test_ua_sanitizesSlashInPlatform() {
        userDefaults.platform = "Bad/Flavor"
        let ua = Utility.buildUserAgent(userDefaults: userDefaults)
        XCTAssertTrue(ua.contains("Bad_Flavor"),
                      "Slash inside the platform string must be sanitized to '_' before composition — got \(ua)")
        // And the segment count must still be 8 (the bad slash didn't create a phantom segment).
        let segments = ua.split(separator: "/", omittingEmptySubsequences: false)
        XCTAssertEqual(segments.count, 8)
    }

    func test_ua_sanitizesWhitespaceInWrapperVersion() {
        userDefaults.platform = PEPlatform.flutterIOS
        userDefaults.wrapperVersion = "2.3 beta"
        let ua = Utility.buildUserAgent(userDefaults: userDefaults)
        XCTAssertTrue(ua.hasSuffix("/2.3_beta"),
                      "Whitespace in wrapper version must be sanitized to '_' — got \(ua)")
    }

    // MARK: - Literal shape with controlled inputs
    //
    // The other tests in this file infer correctness from prefix/suffix/segment
    // count. Under SwiftPM `Bundle.main.bundleIdentifier` and `CFBundleShortVersionString`
    // are both nil/empty, which masks any structural mistake that happens to
    // cancel out across empty segments. This test feeds a controlled
    // `UserDefaultsType` and asserts the precise tail of the UA — the parts
    // we can pin without depending on the host bundle.

    func test_ua_literalShape_tailMatches_whenPlatformAndWrapperVersionSet() {
        userDefaults.platform = PEPlatform.flutterIOS
        userDefaults.wrapperVersion = "2.3.0"
        let ua = Utility.buildUserAgent(userDefaults: userDefaults)
        // The trailing four segments are determined entirely by buildUserAgent's
        // own logic — they don't depend on Bundle.main, so we can pin them.
        XCTAssertTrue(
            ua.hasSuffix("/SDK/\(NetworkConstants.sdkVersion)/FlutterIOS/2.3.0"),
            "UA tail must be '/SDK/<sdkVer>/<flavor>/<wrapperVer>' literally — got '\(ua)'"
        )
    }

    func test_ua_literalShape_tailMatches_native() {
        userDefaults.platform = nil
        userDefaults.wrapperVersion = nil
        let ua = Utility.buildUserAgent(userDefaults: userDefaults)
        XCTAssertTrue(
            ua.hasSuffix("/SDK/\(NetworkConstants.sdkVersion)/iOS"),
            "Native UA tail must be '/SDK/<sdkVer>/iOS' literally — got '\(ua)'"
        )
    }

    func test_ua_segmentOrder_isStable() {
        // Lock the slot order. Splitting by '/' and indexing keeps backend parsers
        // from accidentally re-ordering when something else in the file changes.
        userDefaults.platform = "TestFlavor"
        userDefaults.wrapperVersion = "9.9.9"
        let ua = Utility.buildUserAgent(userDefaults: userDefaults)
        let segments = ua.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(segments.count, 9)
        XCTAssertEqual(segments[0], "iOS",          "slot 0: client literal")
        // segments[1] osVer       — depends on UIDevice; not asserted
        // segments[2] deviceModel — depends on hardware/sim; not asserted
        // segments[3] bundleId    — empty under SwiftPM test bundle
        // segments[4] appVer      — empty under SwiftPM test bundle
        XCTAssertEqual(segments[5], "SDK",          "slot 5: 'SDK' literal")
        XCTAssertEqual(segments[6], NetworkConstants.sdkVersion, "slot 6: sdk version")
        XCTAssertEqual(segments[7], "TestFlavor",   "slot 7: platform flavor")
        XCTAssertEqual(segments[8], "9.9.9",        "slot 8: wrapper version")
    }
}
