import XCTest
@testable import PushEngage

/// Unit tests for `Utility.sanitizeUaSegment`. Mirrors Android's
/// `PEUtilities.sanitizeUaSegment` semantics — replace every character outside
/// the RFC 7230 `tchar` allowlist (alphanumerics + ``!#$%&'*+-.^_`|~``) with
/// `_`, and fall back to a caller-supplied default when the input is nil/empty.
/// The allowlist makes the function defensible against arbitrary wrapper SDK
/// input rather than playing whack-a-mole with new denied characters.
final class SanitizeUaSegmentTests: XCTestCase {

    func test_nilInput_returnsEmptyStringWhenNoFallback() {
        XCTAssertEqual(Utility.sanitizeUaSegment(nil), "")
    }

    func test_nilInput_returnsFallbackWhenProvided() {
        XCTAssertEqual(Utility.sanitizeUaSegment(nil, default: "iOS"), "iOS")
    }

    func test_emptyInput_returnsFallbackWhenProvided() {
        XCTAssertEqual(Utility.sanitizeUaSegment("", default: "iOS"), "iOS")
    }

    func test_emptyInput_returnsEmptyWhenNoFallback() {
        XCTAssertEqual(Utility.sanitizeUaSegment(""), "")
    }

    func test_cleanInput_returnsUnchanged() {
        XCTAssertEqual(Utility.sanitizeUaSegment("FlutterIOS"), "FlutterIOS")
    }

    func test_slashReplaced() {
        // Slash is the UA segment delimiter — must never appear inside a segment.
        XCTAssertEqual(Utility.sanitizeUaSegment("Flutter/IOS"), "Flutter_IOS")
    }

    func test_spaceReplaced() {
        XCTAssertEqual(Utility.sanitizeUaSegment("My App"), "My_App")
    }

    func test_tabReplaced() {
        XCTAssertEqual(Utility.sanitizeUaSegment("a\tb"), "a_b")
    }

    func test_newlineReplaced() {
        XCTAssertEqual(Utility.sanitizeUaSegment("a\nb"), "a_b")
    }

    func test_carriageReturnReplaced() {
        XCTAssertEqual(Utility.sanitizeUaSegment("a\rb"), "a_b")
    }

    func test_controlCharsReplaced() {
        // U+0000 NULL, U+0007 BEL, U+001F UNIT SEPARATOR — all control chars.
        XCTAssertEqual(Utility.sanitizeUaSegment("a\u{0000}b\u{0007}c\u{001F}d"), "a_b_c_d")
    }

    func test_multipleUnsafeCharsInSequence() {
        XCTAssertEqual(Utility.sanitizeUaSegment("a / b"), "a___b")
    }

    func test_versionStringPassesThrough() {
        XCTAssertEqual(Utility.sanitizeUaSegment("2.3.0"), "2.3.0")
    }

    func test_bundleIdentifierPassesThrough() {
        XCTAssertEqual(Utility.sanitizeUaSegment("com.example.app"), "com.example.app")
    }

    func test_dashAndUnderscoreAndDigitsArePreserved() {
        XCTAssertEqual(Utility.sanitizeUaSegment("iPhone15-3"), "iPhone15-3")
    }

    // MARK: - Allowlist strictness (RFC 7230 tchar — defensible against any wrapper input)

    func test_commaReplaced_becauseNotInTchar() {
        // Comma is a header list delimiter — some proxies split on it.
        XCTAssertEqual(Utility.sanitizeUaSegment("iPhone15,3"), "iPhone15_3")
    }

    func test_semicolonReplaced_becauseNotInTchar() {
        // Semicolon is a header parameter delimiter (`type/sub; param=...`).
        XCTAssertEqual(Utility.sanitizeUaSegment("Flutter;2.3"), "Flutter_2.3")
    }

    func test_doubleQuoteReplaced_becauseNotInTchar() {
        XCTAssertEqual(Utility.sanitizeUaSegment("Flu\"ter"), "Flu_ter")
    }

    func test_parensReplaced_becauseNotInTchar() {
        // RFC 7230 (comment) syntax — must not appear inside a token.
        XCTAssertEqual(Utility.sanitizeUaSegment("Flutter(beta)"), "Flutter_beta_")
    }

    func test_colonReplaced_becauseNotInTchar() {
        XCTAssertEqual(Utility.sanitizeUaSegment("Flutter:beta"), "Flutter_beta")
    }

    func test_backslashReplaced_becauseNotInTchar() {
        XCTAssertEqual(Utility.sanitizeUaSegment("a\\b"), "a_b")
    }

    func test_atSignReplaced_becauseNotInTchar() {
        XCTAssertEqual(Utility.sanitizeUaSegment("a@b"), "a_b")
    }

    func test_nonAsciiReplaced_becauseAllowlistIsAsciiOnly() {
        // Non-ASCII passes through Android's denylist sanitizer; the iOS impl
        // uses an ASCII allowlist (RFC 7230 strict) so non-ASCII becomes `_`.
        // Deliberate, defensible difference — header tokens are ASCII per the RFC.
        XCTAssertEqual(Utility.sanitizeUaSegment("café"), "caf_")
    }

    func test_tcharMarksPassThrough() {
        // The full RFC 7230 mark set: ! # $ % & ' * + - . ^ _ ` | ~
        XCTAssertEqual(Utility.sanitizeUaSegment("!#$%&'*+-.^_`|~"), "!#$%&'*+-.^_`|~")
    }
}
