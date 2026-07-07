import XCTest
@testable import PushEngage

/// In-app browser navigation allowlist: web schemes plus `about:` (iframe
/// bootstrap); executable/externally-handled schemes are blocked so a landing
/// page can't auto-trigger them.
final class WKWebViewControllerTests: XCTestCase {

    func test_isAllowedNavigationURL_allowsWebAndAboutSchemesOnly() {
        XCTAssertTrue(WKWebViewController.isAllowedNavigationURL(URL(string: "https://example.com/path")))
        XCTAssertTrue(WKWebViewController.isAllowedNavigationURL(URL(string: "http://example.com/path")))
        XCTAssertTrue(WKWebViewController.isAllowedNavigationURL(URL(string: "about:blank")))

        XCTAssertFalse(WKWebViewController.isAllowedNavigationURL(URL(string: "tel:1234567")))
        XCTAssertFalse(WKWebViewController.isAllowedNavigationURL(URL(string: "customscheme://host/path")))
        XCTAssertFalse(WKWebViewController.isAllowedNavigationURL(URL(string: "file:///etc/passwd")))
        XCTAssertFalse(WKWebViewController.isAllowedNavigationURL(nil))
    }
}
