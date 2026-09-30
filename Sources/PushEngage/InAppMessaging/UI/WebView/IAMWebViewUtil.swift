import Foundation

/// Utility for preparing in-app message HTML for WebView display.
///
/// Mirrors Android's `IAMWebViewUtil` step-for-step so that one
/// `htmlContent` payload renders and behaves identically on both platforms
/// (backend contract §4/§7.2). Authored HTML talks to the platform-neutral
/// `PEBridge` global; this file polyfills it onto the WebKit message handler.
enum IAMWebViewUtil {

    // MARK: - PEBridge polyfill (§7.2)

    /// Platform-neutral bridge: authored HTML calls `PEBridge.handleAction` /
    /// `PEBridge.reportHeight` and each platform maps it onto its native
    /// bridge. Injected into <head> so it exists before any inline content
    /// scripts run. The legacy `pushengageHandler` postMessage keeps working.
    static let bridgePolyfill = """
        <script>
        (function() {
            if (window.PEBridge) return;
            function post(payload) {
                if (window.webkit && window.webkit.messageHandlers &&
                    window.webkit.messageHandlers.pushengageHandler) {
                    window.webkit.messageHandlers.pushengageHandler.postMessage(payload);
                }
            }
            window.PEBridge = {
                handleAction: function(id) {
                    post({ action: String(id) });
                },
                reportHeight: function(height) {
                    window.__peHeightReported = true;
                    post({ id: 'contentHeight', height: Math.ceil(Number(height) || 0) });
                }
            };
        })();
        </script>
        """

    // MARK: - Minimal CSS

    /// MINIMAL injection only — the SDK renders authored HTML faithfully and
    /// must not restyle it (contract §4; mirrors Android). Stylesheet-level
    /// rules, so any author style (inline or more specific) wins:
    ///  - transparent page background: required so the message draws its own
    ///    card/banner surface over the app (contract §4 #3)
    ///  - img max-width safety cap: an image can never exceed the container
    ///    width, whatever the author forgot
    ///  - full-screen only: html/body pinned to 100% because WKWebView locks
    ///    vh to a stale viewport measured before layout (platform quirk,
    ///    contract §3.2), and body's direct children stretched to match.
    ///    Pinning the page alone is not enough: authored content is a single
    ///    content-height div, so the page filled but the div did not, and the
    ///    injected transparent background left the host app showing through
    ///    below it — a "full screen" takeover that covered only its content.
    ///    Mirrors what Android forces in IAMWebViewContainer's FULL branch.
    /// Nothing else: no resets, no container/button/text restyling, no
    /// overflow or height overrides — forcing those broke valid content
    /// (e.g. object-fit images painting over siblings).
    static func cssFixesForDisplay(fillsViewport: Bool) -> String {
        let fullScreenRule = fillsViewport
            ? "\n        html, body { height: 100% !important; margin: 0 !important; }"
              + "\n        body > * { min-height: 100% !important; }"
            : ""
        return """
        <style>
        html, body { background-color: transparent; }
        img { max-width: 100%; }\(fullScreenRule)
        </style>
        """
    }

    // MARK: - Height measurement

    /// Content-based height expression: the bottom edge of the lowest child
    /// of <body>. Deliberately avoids viewport-derived values
    /// (documentElement.clientHeight & friends) — the WebView starts tall, so
    /// those can never measure smaller than the current container and the
    /// message keeps its initial blank space forever.
    private static let contentHeightExpression = """
        (function() {
            var children = document.body.children;
            var bottom = 0;
            for (var i = 0; i < children.length; i++) {
                var rect = children[i].getBoundingClientRect();
                if (rect.bottom > bottom) { bottom = rect.bottom; }
            }
            return Math.ceil(bottom || document.body.offsetHeight);
        })()
        """

    /// Fallback measurement injected before </body>: reports the content
    /// height on load for content that does not call `PEBridge.reportHeight`
    /// explicitly. An explicit report wins — the fallback then does nothing.
    static let heightFallbackScript = """
        <script>
        window.onload = function() {
            if (window.__peHeightReported) return;
            if (window.PEBridge && typeof window.PEBridge.reportHeight === 'function') {
                window.PEBridge.reportHeight(\(contentHeightExpression));
            }
        };
        </script>
        """

    /// Safety measurement evaluated natively after the page load finishes:
    /// only acts when neither the content nor the onload fallback has
    /// reported a height yet.
    static let heightMeasurementScript = """
        (function() {
            if (window.__peHeightReported) return;
            window.__peHeightReported = true;
            var height = \(contentHeightExpression);
            if (window.webkit && window.webkit.messageHandlers &&
                window.webkit.messageHandlers.pushengageHandler) {
                window.webkit.messageHandlers.pushengageHandler.postMessage({
                    id: 'contentHeight',
                    height: height
                });
            }
        })();
        """

    /// Unconditional re-measurement for layout changes (e.g. rotation) where
    /// any previously reported height is stale. Selector-free — the legacy
    /// probe hardcoded `.modal`/`.banner`/`.sheet` CSS classes and broke on
    /// arbitrary authored content.
    static let heightRemeasurementScript = """
        (function() {
            var height = \(contentHeightExpression);
            if (window.webkit && window.webkit.messageHandlers &&
                window.webkit.messageHandlers.pushengageHandler) {
                window.webkit.messageHandlers.pushengageHandler.postMessage({
                    id: 'contentHeight',
                    height: height
                });
            }
        })();
        """

    // MARK: - HTML preparation

    /// Prepares HTML content for WebView display: viewport meta, PEBridge
    /// polyfill + CSS reset in <head>, height fallback before </body>, and a
    /// DOCTYPE. Insertion rules mirror Android's `prepareHtmlContent`.
    /// - Parameter fillsViewport: true for full-screen messages, whose
    ///   content sizes itself against the viewport (100vh).
    static func prepareHtmlContent(_ htmlContent: String, fillsViewport: Bool = false) -> String {
        if htmlContent.isEmpty {
            PELogger.debug(
                className: String(describing: IAMWebViewUtil.self),
                message: "prepareHtmlContent: No content provided, returning default HTML"
            )
            return "<!DOCTYPE html><html><body><p>No content available</p></body></html>"
        }

        var prepared = ensureViewportMeta(htmlContent)

        let headInjection = "\(bridgePolyfill)\n\(cssFixesForDisplay(fillsViewport: fillsViewport))"

        // Insert the bridge polyfill + CSS fixes. First occurrence only, so a
        // stray </head> or <body> token elsewhere in the content can't cause
        // the injection to be duplicated.
        if let headClose = prepared.range(of: "</head>") {
            prepared = prepared.replacingCharacters(in: headClose, with: "\(headInjection)\n</head>")
        } else if let bodyOpen = prepared.range(of: "<body") {
            prepared = prepared.replacingCharacters(in: bodyOpen, with: "<head>\(headInjection)</head><body")
        } else {
            prepared = "\(headInjection)\n\(prepared)"
        }

        // Insert the height fallback (first </body> occurrence only)
        if let bodyClose = prepared.range(of: "</body>") {
            prepared = prepared.replacingCharacters(in: bodyClose, with: "\(heightFallbackScript)\n</body>")
        } else {
            prepared = "\(prepared)\n\(heightFallbackScript)"
        }

        // Ensure we have a DOCTYPE and basic HTML structure
        if !prepared.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("<!doctype") {
            prepared = "<!DOCTYPE html>\n\(prepared)"
        }

        return prepared
    }

    /// Adds a meta viewport tag to HTML content if missing. Matching and
    /// insertion rules mirror Android's `ensureViewportMeta`.
    static func ensureViewportMeta(_ htmlContent: String) -> String {
        if htmlContent.isEmpty {
            return htmlContent
        }

        // Already has a viewport meta tag? Match a real <meta name="viewport">
        // tag rather than the words "<meta" and "viewport" appearing anywhere
        // independently.
        if firstMatch(of: Self.viewportMeta, in: htmlContent) != nil {
            return htmlContent
        }

        let metaTag = "<meta name=\"viewport\" content=\"width=device-width, "
            + "initial-scale=1.0, maximum-scale=1.0, user-scalable=no\">"

        if let head = firstMatch(of: Self.headOpen, in: htmlContent) {
            // Existing <head ...> — insert the meta as its first child.
            return insert("\n    \(metaTag)", into: htmlContent, after: head)
        }
        if let body = firstMatch(of: Self.bodyOpen, in: htmlContent) {
            // No head but a <body ...> — wrap a head just before it.
            return insert("<head>\n    \(metaTag)\n</head>\n", into: htmlContent, before: body)
        }
        if let html = firstMatch(of: Self.htmlOpen, in: htmlContent) {
            // Opening <html ...> only — insert a head right after it.
            return insert("\n<head>\n    \(metaTag)\n</head>", into: htmlContent, after: html)
        }
        // Bare fragment — wrap into a full document.
        return "<!DOCTYPE html>\n<html>\n<head>\n    \(metaTag)\n</head>\n<body>\n\(htmlContent)\n</body>\n</html>"
    }

    // MARK: - Regex helpers

    private static let viewportMeta = regex(#"<meta[^>]*name\s*=\s*["']viewport["']"#)
    private static let headOpen = regex("<head[^>]*>")
    private static let bodyOpen = regex("<body")
    private static let htmlOpen = regex("<html[^>]*>")

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants; a failure is a programmer error.
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func firstMatch(of regex: NSRegularExpression, in html: String) -> NSRange? {
        let range = NSRange(html.startIndex..., in: html)
        return regex.firstMatch(in: html, options: [], range: range)?.range
    }

    private static func insert(_ text: String, into html: String, after match: NSRange) -> String {
        guard let range = Range(match, in: html) else { return html }
        var result = html
        result.insert(contentsOf: text, at: range.upperBound)
        return result
    }

    private static func insert(_ text: String, into html: String, before match: NSRange) -> String {
        guard let range = Range(match, in: html) else { return html }
        var result = html
        result.insert(contentsOf: text, at: range.lowerBound)
        return result
    }
}
