import XCTest
@testable import PushEngage

/// PEBridge polyfill + HTML preparation tests mirroring Android's
/// IAMWebViewUtilTest, per the backend contract §4 (HTML authoring) and
/// §7.2 (unified bridge). The polyfill implementations differ per platform
/// (WebKit message handler here, JavascriptInterface on Android) but the
/// PEBridge API surface and preparation behavior must be identical.
final class IAMWebViewUtilTests: XCTestCase {

    private let fullDocument = """
    <!DOCTYPE html>
    <html>
    <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>.modal { color: red; }</style>
    </head>
    <body>
        <div class="modal" onclick="PEBridge.handleAction('dismiss_action')">Hi</div>
    </body>
    </html>
    """

    // MARK: - prepareHtmlContent structure

    func testEmptyInputReturnsTheFallbackDocument() {
        let prepared = IAMWebViewUtil.prepareHtmlContent("")
        XCTAssertEqual(prepared, "<!DOCTYPE html><html><body><p>No content available</p></body></html>")
    }

    func testFullDocumentGetsPEBridgePolyfillInjectedInsideHeadBeforeBody() throws {
        let prepared = IAMWebViewUtil.prepareHtmlContent(fullDocument)
        let polyfillIndex = try XCTUnwrap(prepared.range(of: "window.PEBridge = {")).lowerBound
        let headCloseIndex = try XCTUnwrap(prepared.range(of: "</head>")).lowerBound
        let bodyOpenIndex = try XCTUnwrap(prepared.range(of: "<body>")).lowerBound
        XCTAssertLessThan(polyfillIndex, headCloseIndex)
        XCTAssertLessThan(headCloseIndex, bodyOpenIndex)
    }

    func testFullDocumentKeepsOriginalContentAndGetsOnlyTheMinimalCSS() {
        let prepared = IAMWebViewUtil.prepareHtmlContent(fullDocument)
        XCTAssertTrue(prepared.contains("PEBridge.handleAction('dismiss_action')"))
        XCTAssertTrue(prepared.contains(".modal { color: red; }"))
        XCTAssertTrue(prepared.contains("background-color: transparent;"))
        XCTAssertTrue(prepared.contains("img { max-width: 100%; }"))
    }

    func testSDKDoesNotRestyleAuthoredHTML() {
        // Contract §4: authored HTML is rendered faithfully. The SDK must not
        // inject resets or element restyling — forcing overflow/heights broke
        // valid content (e.g. object-fit images painting over siblings).
        let prepared = IAMWebViewUtil.prepareHtmlContent(fullDocument)
        XCTAssertFalse(prepared.contains("box-sizing: border-box"))
        XCTAssertFalse(prepared.contains("overflow: visible"))
        XCTAssertFalse(prepared.contains("height: auto !important"))
        XCTAssertFalse(prepared.contains(".container, .banner"))
        XCTAssertFalse(prepared.contains("button {"))
        XCTAssertFalse(prepared.contains("p, h1"))
    }

    func testPolyfillIsInjectedBeforeTheMinimalCSS() throws {
        let prepared = IAMWebViewUtil.prepareHtmlContent(fullDocument)
        let polyfillIndex = try XCTUnwrap(prepared.range(of: "window.PEBridge = {")).lowerBound
        let cssIndex = try XCTUnwrap(prepared.range(of: "background-color: transparent;")).lowerBound
        XCTAssertLessThan(polyfillIndex, cssIndex)
    }

    func testHeightMeasurementScriptIsInjectedBeforeTheClosingBodyTag() throws {
        let prepared = IAMWebViewUtil.prepareHtmlContent(fullDocument)
        let fallbackIndex = try XCTUnwrap(prepared.range(of: "window.onload = function()")).lowerBound
        let bodyCloseIndex = try XCTUnwrap(prepared.range(of: "</body>")).lowerBound
        XCTAssertLessThan(fallbackIndex, bodyCloseIndex)
    }

    // MARK: - Polyfill semantics (§7.2)

    func testPolyfillMapsPEBridgeOntoTheWebKitMessageHandler() {
        let polyfill = IAMWebViewUtil.bridgePolyfill
        XCTAssertTrue(polyfill.contains("window.PEBridge = {"))
        XCTAssertTrue(polyfill.contains("handleAction: function(id)"))
        XCTAssertTrue(polyfill.contains("reportHeight: function(height)"))
        XCTAssertTrue(polyfill.contains("window.webkit.messageHandlers.pushengageHandler.postMessage"))
        // Argument coercion identical to Android's polyfill
        XCTAssertTrue(polyfill.contains("String(id)"))
        XCTAssertTrue(polyfill.contains("Math.ceil(Number(height) || 0)"))
        // Message shapes match the native handler contract
        XCTAssertTrue(polyfill.contains("{ action: String(id) }"))
        XCTAssertTrue(polyfill.contains("{ id: 'contentHeight', height: Math.ceil(Number(height) || 0) }"))
    }

    func testPolyfillCarriesTheDoubleInjectionGuard() {
        XCTAssertTrue(IAMWebViewUtil.bridgePolyfill.contains("if (window.PEBridge) return;"))
    }

    func testHeightMeasurementScriptsAreSelectorFree() {
        // The legacy probe hardcoded .modal/.banner/.sheet and broke on
        // arbitrary dashboard-authored content.
        for script in [IAMWebViewUtil.heightMeasurementScript,
                       IAMWebViewUtil.heightFallbackScript,
                       IAMWebViewUtil.heightRemeasurementScript] {
            XCTAssertFalse(script.contains("querySelector"))
            XCTAssertTrue(script.contains("getBoundingClientRect"))
        }
    }

    func testHeightMeasurementsAvoidViewportDerivedValues() {
        // documentElement.clientHeight (& friends) reflect the WebView's
        // current — initially tall — viewport, so measuring with them locks
        // the message at its starting size (blank space below the content).
        for script in [IAMWebViewUtil.heightMeasurementScript,
                       IAMWebViewUtil.heightFallbackScript,
                       IAMWebViewUtil.heightRemeasurementScript] {
            XCTAssertFalse(script.contains("clientHeight"))
            XCTAssertFalse(script.contains("documentElement.scrollHeight"))
        }
    }

    func testExplicitHeightReportWinsOverFallbacks() {
        // The polyfill marks that a height was reported…
        XCTAssertTrue(IAMWebViewUtil.bridgePolyfill.contains("window.__peHeightReported = true;"))
        // …and both automatic measurers stand down once it is set.
        XCTAssertTrue(IAMWebViewUtil.heightFallbackScript.contains("if (window.__peHeightReported) return;"))
        XCTAssertTrue(IAMWebViewUtil.heightMeasurementScript.contains("if (window.__peHeightReported) return;"))
        // Rotation re-measurement is unconditional — a previously reported
        // height is stale after a layout change.
        XCTAssertFalse(IAMWebViewUtil.heightRemeasurementScript.contains("__peHeightReported"))
    }

    // MARK: - Structural variants

    func testBodyWithoutHeadGetsAHeadCreatedAroundTheInjections() {
        let prepared = IAMWebViewUtil.prepareHtmlContent("<html><body><p>Hello</p></body></html>")
        XCTAssertTrue(prepared.contains("<head>"))
        XCTAssertTrue(prepared.contains("window.PEBridge = {"))
        XCTAssertTrue(prepared.contains("<p>Hello</p>"))
        // No duplicated body tag
        XCTAssertEqual(prepared.components(separatedBy: "<body").count - 1, 1)
    }

    func testBareFragmentIsWrappedIntoAFullDocumentWithInjectionsInHead() throws {
        let prepared = IAMWebViewUtil.prepareHtmlContent("<p>Just a fragment</p>")
        XCTAssertTrue(prepared.contains("<!DOCTYPE html>"))
        XCTAssertTrue(prepared.contains("<p>Just a fragment</p>"))
        let polyfillIndex = try XCTUnwrap(prepared.range(of: "window.PEBridge = {")).lowerBound
        let fragmentIndex = try XCTUnwrap(prepared.range(of: "<p>Just a fragment</p>")).lowerBound
        XCTAssertLessThan(polyfillIndex, fragmentIndex)
    }

    func testStructurelessFragmentThatDodgesViewportWrappingGetsInjectionsPrependedAndDoctypeAdded() {
        // Content with an existing viewport meta but no head/body structure
        let fragment = "<meta name=\"viewport\" content=\"width=device-width\"><p>hi</p>"
        let prepared = IAMWebViewUtil.prepareHtmlContent(fragment)
        XCTAssertTrue(prepared.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(prepared.contains("window.PEBridge = {"))
        XCTAssertTrue(prepared.contains("<p>hi</p>"))
    }

    // MARK: - Viewport meta

    func testExistingViewportMetaIsNotDuplicated() {
        let prepared = IAMWebViewUtil.prepareHtmlContent(fullDocument)
        XCTAssertEqual(prepared.components(separatedBy: "name=\"viewport\"").count - 1, 1)
    }

    func testMissingViewportMetaIsAddedExactlyOnceInsideHead() throws {
        let html = "<html><head><title>t</title></head><body><p>x</p></body></html>"
        let prepared = IAMWebViewUtil.prepareHtmlContent(html)
        XCTAssertEqual(prepared.components(separatedBy: "name=\"viewport\"").count - 1, 1)
        let viewportIndex = try XCTUnwrap(prepared.range(of: "name=\"viewport\"")).lowerBound
        let headCloseIndex = try XCTUnwrap(prepared.range(of: "</head>")).lowerBound
        XCTAssertLessThan(viewportIndex, headCloseIndex)
    }

    func testEnsureViewportMetaLeavesContentWithExistingViewportUntouched() {
        XCTAssertEqual(IAMWebViewUtil.ensureViewportMeta(fullDocument), fullDocument)
    }

    func testEnsureViewportMetaOnEmptyInputReturnsEmpty() {
        XCTAssertEqual(IAMWebViewUtil.ensureViewportMeta(""), "")
    }

    func testEnsureViewportMetaAddsViewportWhenOnlyACharsetMetaExists() {
        // A bare <meta charset> plus the literal word "viewport" in body text
        // must not false-match as an existing viewport tag.
        let html = "<html><head><meta charset=\"utf-8\"></head><body>viewport talk</body></html>"
        let result = IAMWebViewUtil.ensureViewportMeta(html)
        XCTAssertTrue(result.contains("name=\"viewport\""))
    }

    func testHtmlTagWithoutHeadGetsASingleHeadWithoutDuplicatingTheBody() {
        let html = "<html><body><p>x</p></body></html>"
        let result = IAMWebViewUtil.ensureViewportMeta(html)
        XCTAssertTrue(result.contains("name=\"viewport\""))
        XCTAssertEqual(result.components(separatedBy: "<body").count - 1, 1)
    }

    func testHeadInjectionIsNotDuplicatedWhenContentHasAStrayClosingHeadToken() {
        // A stray </head> in body text: injection must happen at the FIRST
        // occurrence only.
        let html = "<html><head></head><body><p>text with </head> inside</p></body></html>"
        let prepared = IAMWebViewUtil.prepareHtmlContent(html)
        XCTAssertEqual(prepared.components(separatedBy: "window.PEBridge = {").count - 1, 1)
    }

    func testFullScreenPreparationKeepsViewportFillingHeight() {
        // Full-screen content sizes itself with 100vh (§3.2/§Appendix A.5);
        // WKWebView locks vh to a stale viewport, so full-screen (only) pins
        // html/body to 100%. Standard positions get no height rule at all.
        let full = IAMWebViewUtil.prepareHtmlContent(fullDocument, fillsViewport: true)
        XCTAssertTrue(full.contains("height: 100% !important;"))

        let standard = IAMWebViewUtil.prepareHtmlContent(fullDocument)
        XCTAssertFalse(standard.contains("height: 100% !important;"))
        XCTAssertFalse(standard.contains("height: auto !important;"))
    }

    func testFullScreenPreparationStretchesBodyChildren() {
        // Pinning html/body alone is not enough. Authored full-screen content is
        // typically ONE content-height div, so the page filled the screen while
        // the div did not — and because preparation also injects a transparent
        // page background, the host app showed through below the content: a
        // takeover that covered only its own content. Android forces the same
        // stretch in IAMWebViewContainer's FULL branch, so both platforms agree.
        let full = IAMWebViewUtil.prepareHtmlContent(fullDocument, fillsViewport: true)
        XCTAssertTrue(full.contains("body > * { min-height: 100% !important; }"))
        // Zeroed alongside it: WebKit's default body margin would otherwise leave
        // a transparent gutter around a "full screen" message on iOS only.
        XCTAssertTrue(full.contains("margin: 0 !important;"))

        // Standard positions are content-sized on purpose — stretching their
        // children would inflate every banner and modal to the full screen.
        let standard = IAMWebViewUtil.prepareHtmlContent(fullDocument)
        XCTAssertFalse(standard.contains("min-height: 100% !important;"))
        XCTAssertFalse(standard.contains("margin: 0 !important;"))
    }

    func testPreparedOutputSurvivesASecondPassWithoutDoubleInjection() {
        // The double-injection guard string survives preparation, so even if
        // content is prepared twice the bridge is defined once at runtime.
        let once = IAMWebViewUtil.prepareHtmlContent(fullDocument)
        XCTAssertTrue(once.contains("if (window.PEBridge) return;"))
    }
}
