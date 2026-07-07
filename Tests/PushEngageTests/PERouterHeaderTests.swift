import XCTest
@testable import PushEngage
@testable import PushEngageExtension
/// Locks in the request-header shape emitted by `PERouter.asURLRequest()`.
/// In particular, asserts that the User-Agent has migrated from the old
/// inline dash-delimited format (`iOS-…/sdk-…/app-…`) to the new
/// slash-delimited Android-parity format built via `Utility.buildUserAgent`.
final class PERouterHeaderTests: XCTestCase {

    private var route: PERouter {
        return .checkSubscriberHash("test-hash")
    }

    private func makeHeaders() -> [String: String] {
        do {
            let request = try route.asURLRequest()
            return request.allHTTPHeaderFields ?? [:]
        } catch {
            XCTFail("PERouter.asURLRequest() threw: \(error)")
            return [:]
        }
    }

    func test_clientHeader_isIOS() {
        let headers = makeHeaders()
        XCTAssertEqual(headers["X-Pe-Client"], "iOS")
    }

    func test_sdkVersionHeader_matchesConstant() {
        let headers = makeHeaders()
        XCTAssertEqual(headers["X-Pe-Sdk-Version"], NetworkConstants.sdkVersion)
    }

    func test_contentTypeHeader_isApplicationJSON() {
        let headers = makeHeaders()
        XCTAssertEqual(headers["Content-Type"], "application/json")
    }

    func test_userAgentHeader_usesSlashDelimitedShape() {
        let headers = makeHeaders()
        let ua = headers["User-Agent"] ?? ""
        XCTAssertTrue(ua.hasPrefix("iOS/"),
                      "UA must use the new slash-delimited shape — got '\(ua)'")
        XCTAssertFalse(ua.hasPrefix("iOS-"),
                       "UA must no longer use the legacy 'iOS-…' inline format — got '\(ua)'")
    }

    func test_userAgentHeader_containsSDKLiteralAndVersion() {
        let headers = makeHeaders()
        let ua = headers["User-Agent"] ?? ""
        XCTAssertTrue(ua.contains("/SDK/\(NetworkConstants.sdkVersion)/"),
                      "UA must contain '/SDK/<sdkVersion>/' tail — got '\(ua)'")
    }

    func test_userAgentHeader_doesNotEmbedSiteKey() throws {
        // Site key now travels in the X-Pe-App-Id header only. This guards against
        // any regression that re-introduces the legacy `app-<siteKey>` segment.
        let userDefaults = DependencyInitialize.getUserDefaults()
        try XCTSkipUnless(
            (userDefaults.siteKey?.isEmpty == false),
            "Skipping siteKey-embedded UA check — no site key configured in the test runner's UserDefaults suite. " +
            "Add an explicit `setAppId` in setUp if you want this guard exercised in CI."
        )
        let siteKey = userDefaults.siteKey ?? ""
        let headers = makeHeaders()
        let ua = headers["User-Agent"] ?? ""
        XCTAssertFalse(ua.contains(siteKey),
                       "UA must not embed siteKey '\(siteKey)' — got '\(ua)'")
    }

    // MARK: - X-Pe-App-Id presence/absence
    //
    // PERouter.getHeader() must omit the X-Pe-App-Id header entirely (rather
    // than emit it with an empty value) when the configured site key is nil or
    // an empty string. An empty `X-Pe-App-Id: ` is a malformed header value
    // some backends will 400 on.

    func test_appIdHeader_isAbsentWhenSiteKeyUnset() throws {
        let userDefaults = DependencyInitialize.getUserDefaults()
        try XCTSkipUnless(
            userDefaults.siteKey?.isEmpty != false,
            "Skipping — test runner's UserDefaults already has a non-empty siteKey set."
        )
        let headers = makeHeaders()
        XCTAssertNil(headers["X-Pe-App-Id"],
                     "X-Pe-App-Id header must be absent when no siteKey configured — got '\(headers["X-Pe-App-Id"] ?? "nil")'")
    }

    // MARK: - Public getSdkVersion() accessor
    //
    // `PushEngage.getSdkVersion()` is the customer-facing accessor (parity with
    // Android's `PushEngage.getSdkVersion()`). It MUST return the same string
    // the SDK reports to the backend in `X-Pe-Sdk-Version`, the User-Agent's
    // `/SDK/<version>/` segment, and the `swv` payload field — otherwise
    // customers see one version in their about-screen / crash reports while
    // the backend's analytics tag a different version against the same
    // requests. This drift would only surface as a backend-vs-client
    // analytics mismatch, which is exactly the kind of bug nobody notices
    // until someone tries to correlate them.

    func test_getSdkVersion_matchesInternalConstant() {
        XCTAssertEqual(PushEngage.getSdkVersion(), NetworkConstants.sdkVersion,
                       "PushEngage.getSdkVersion() must mirror NetworkConstants.sdkVersion " +
                       "so customer-facing reads and backend-reported versions never drift apart")
    }

    func test_getSdkVersion_matchesValueInSdkVersionHeader() {
        let headers = makeHeaders()
        XCTAssertEqual(PushEngage.getSdkVersion(), headers["X-Pe-Sdk-Version"],
                       "The public accessor must return the exact same string the backend " +
                       "sees in the X-Pe-Sdk-Version request header")
    }

    // MARK: - Per-request timeout
    //
    // PERouter must not pin a shorter timeout than the session config — the
    // request-level value wins, so a 10s override silently shortened every
    // network call regardless of what `Router` configured.

    func test_urlRequestTimeout_matchesNetworkConstant() throws {
        let request = try route.asURLRequest()
        XCTAssertEqual(request.timeoutInterval, NetworkConstants.requestTimeout,
                       "Per-request timeoutInterval must honor NetworkConstants.requestTimeout " +
                       "so it does not override the session-level timeoutIntervalForRequest")
    }

    func test_getSdkVersion_isNonEmptySemverShape() {
        let version = PushEngage.getSdkVersion()
        XCTAssertFalse(version.isEmpty, "SDK version must never be the empty string")
        // Soft semver check: at least one dot, no whitespace, no v-prefix. We
        // don't enforce strict semver because the SDK historically used
        // 0.0.x-beta tags which the backend tolerates; this just guards
        // against obvious format regressions.
        XCTAssertTrue(version.contains("."),
                      "SDK version should look like a dotted semver string — got '\(version)'")
        XCTAssertFalse(version.hasPrefix("v"),
                       "SDK version must not include a 'v' prefix — got '\(version)'")
        XCTAssertFalse(version.rangeOfCharacter(from: .whitespaces) != nil,
                       "SDK version must not contain whitespace — got '\(version)'")
    }
}
