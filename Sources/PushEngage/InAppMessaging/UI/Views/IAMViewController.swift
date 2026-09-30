import UIKit
import WebKit

protocol IAMViewControllerDelegate: AnyObject {
    func messageDidDismiss()
    func handleCustomAction(actionId: String, parameters: [String: String])
}

class IAMViewController: UIViewController, IAMMessageDisplaying {
    // MARK: - Properties
    
    private let message: IAMMessage
    private var webView: WKWebView!
    weak var delegate: IAMViewControllerDelegate?
    private var containerView: UIView!
    private var containerHeightConstraint: NSLayoutConstraint?

    /// Position constraints (container ↔ safe area / view). Tracked so rotation
    /// re-layout can DEACTIVATE them: they are installed on the superview, so
    /// `deactivate(containerView.constraints)` never touched them — every
    /// rotation piled a new set on top of the old (conflicting constants →
    /// AutoLayout breaks an arbitrary constraint → undefined layout).
    private var positionConstraints: [NSLayoutConstraint] = []
    private var initialLoad = true
    private var dismissTimer: Timer?
    private var analyticsManager = IAMAnalyticsManager.shared

    /// Opacity of the black scrim behind the message, for every position.
    ///
    /// Deliberately light: the scrim covers the whole screen even for a `top` or
    /// `bottom` banner, so a heavy value made a banner read as a modal takeover and
    /// looked nothing like Android's floating card over an untouched screen. It stays
    /// non-zero because the scrim is still what receives the outside tap that
    /// `shouldDismissOnTap` acts on.
    static let backdropAlpha: CGFloat = 0.1

    // MARK: - Helper Methods
    
    /// Whether the interface the message is showing in is landscape.
    ///
    /// Read from **this message's own window**, not from `UIApplication.shared.windows.first`.
    /// The SDK presents into its own window above the host, so `windows.first` is not
    /// reliably the window the message occupies — the caps below (`center` at 60 % height
    /// and 70 % width in landscape) could be computed from a different window's
    /// orientation. `view.window` cannot be the wrong one.
    ///
    /// Falls back to the device orientation only before the view is in a window, where
    /// there is no interface orientation to read yet.
    private func isInterfaceLandscape() -> Bool {
        if let sceneOrientation = view.window?.windowScene?.interfaceOrientation {
            return sceneOrientation.isLandscape
        }
        return UIDevice.current.orientation.isLandscape
    }
    
    init(message: IAMMessage) {
        self.message = message
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        PELogger.debug(
            className: String(describing: IAMViewController.self),
            message: "viewDidLoad"
        )
        setupViews()
        setupConstraints()
        setupTapGesture()
        loadContent()
        setupDismissTimer()
        
        // Add notification observer for orientation changes
        NotificationCenter.default.addObserver(self, 
                                              selector: #selector(orientationDidChange), 
                                              name: UIDevice.orientationDidChangeNotification, 
                                              object: nil)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        PELogger.debug(
            className: String(describing: IAMViewController.self),
            message: "View appeared"
        )
        messageDidDisplay()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        PELogger.debug(
            className: String(describing: IAMViewController.self),
            message: "View will disappear"
        )
        messageWillDismiss()
        dismissTimer?.invalidate()
        dismissTimer = nil
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate { [weak self] _ in
            // Update layout during rotation
            self?.view.setNeedsLayout()
            self?.view.layoutIfNeeded()
        } completion: { [weak self] _ in
            guard let self = self else { return }
            // Rebuild here too: the interface orientation the position constraints
            // branch on is only settled once the transition has finished.
            self.setupConstraints()
            self.view.layoutIfNeeded()
            self.recalculateContentHeight()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Orientation Handling
    
    @objc private func orientationDidChange() {
        // Adjust layout for the new orientation
        updateLayoutForCurrentOrientation()
    }
    
    private func updateLayoutForCurrentOrientation() {
        // Update constraints based on current orientation
        setupConstraints()
        
        // Force layout update
        view.setNeedsLayout()
        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
        } completion: { _ in
            // Recalculate content height after layout updates
            self.recalculateContentHeight()
        }
    }
    
    private func recalculateContentHeight() {
        // Skip for full screen messages
        let position = IAMPosition(rawValue: message.position) ?? .center
        if position == .full { return }
        
        // Re-evaluate JavaScript to get accurate content height in new orientation
        webView.evaluateJavaScript(IAMWebViewUtil.heightRemeasurementScript) { _, error in
            if let error = error {
                PELogger.error(
                    className: String(describing: IAMViewController.self),
                    message: "Height recalculation error: \(error.localizedDescription)"
                )
            }
        }
    }
    
    // MARK: - IAMMessageDisplaying
    
    func messageWillDisplay() {
        PELogger.debug(
            className: String(describing: IAMViewController.self),
            message: "messageWillDisplay"
        )
    }
    
    func messageDidDisplay() {
        PELogger.debug(
            className: String(describing: IAMViewController.self),
            message: "messageDidDisplay"
        )
    }
    
    func messageWillDismiss() {
        PELogger.debug(
            className: String(describing: IAMViewController.self),
            message: "messageWillDismiss"
        )
    }
    
    func messageDidDismiss() {
        PELogger.debug(
            className: String(describing: IAMViewController.self),
            message: "messageDidDismiss"
        )
        delegate?.messageDidDismiss()
    }
    
    private func setupViews() {
        // Configure WebView with message handler
        let config = WKWebViewConfiguration()
        let userController = WKUserContentController()
        // Page world, not a WKContentWorld: authored campaign HTML must reach PEBridge.
        userController.add(self, name: "pushengageHandler")
        config.userContentController = userController
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.suppressesIncrementalRendering = false
        
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        
        // Add these lines for dynamic sizing
        webView.sizeToFit()
        webView.setContentCompressionResistancePriority(.required, for: .vertical)
        webView.setContentHuggingPriority(.required, for: .vertical)
        
        // Configure container view. TRANSPARENT for every position: the authored
        // HTML draws its own card/banner surface (background, corner radius,
        // shadow) — that is the contract with the dashboard. A native white
        // background + 14pt radius here re-decorated the message: white wedges
        // peeked out wherever the authored card's own corner radius differed,
        // and showed through any transparent region. Matches Android, whose
        // container has no background of its own.
        containerView = UIView()
        containerView.backgroundColor = .clear
        containerView.layer.cornerRadius = 0
        containerView.clipsToBounds = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        // No native close control: the authored HTML draws the whole message,
        // dismiss button included — the same contract as the card surface above, and
        // the same as Android. The previous one looked its image up in the host app's
        // bundle, where the SDK ships none, leaving an invisible tappable patch over
        // every message's top-right corner.
        view.backgroundColor = UIColor.black.withAlphaComponent(Self.backdropAlpha)
        view.addSubview(containerView)
        containerView.addSubview(webView)
    }
    
    private func setupConstraints() {
        // Remove existing constraints before setting up new ones
        if containerHeightConstraint?.isActive == true {
            containerHeightConstraint?.isActive = false
            containerHeightConstraint = nil
        }
        NSLayoutConstraint.deactivate(containerView.constraints)
        // Clear the previous position constraints (owned by the superview —
        // the deactivate above cannot reach them).
        NSLayoutConstraint.deactivate(positionConstraints)
        positionConstraints.removeAll()
        
        // Set constraints based on message position
        let position = IAMPosition(rawValue: message.position) ?? .center
        let safeArea = view.safeAreaLayoutGuide
        
        // Basic constraints for all positions
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: containerView.topAnchor),
            webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        // Position-specific constraints
        // Use interface orientation rather than device orientation for more reliable results
        let isLandscape = isInterfaceLandscape()
        let standardMargin: CGFloat = 16
        
        switch position {
        case .top:
            positionConstraints = Self.bannerConstraints(container: containerView,
                                                         host: view,
                                                         safeArea: safeArea,
                                                         pinnedToTop: true,
                                                         standardMargin: standardMargin)

        case .bottom:
            positionConstraints = Self.bannerConstraints(container: containerView,
                                                         host: view,
                                                         safeArea: safeArea,
                                                         pinnedToTop: false,
                                                         standardMargin: standardMargin)

        case .center:
            // Center in the screen
            positionConstraints = Self.centerConstraints(container: containerView,
                                                         host: view,
                                                         safeArea: safeArea,
                                                         isLandscape: isLandscape,
                                                         standardMargin: standardMargin)

        case .full:
            // Full screen with safe area insets
            positionConstraints = [
                containerView.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: standardMargin),
                containerView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: standardMargin),
                containerView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -standardMargin),
                containerView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -standardMargin)
            ]
        }
        NSLayoutConstraint.activate(positionConstraints)
        
        // Create height constraint with initial height (unless it's full screen)
        if position != .full {
            containerHeightConstraint = containerView.heightAnchor.constraint(equalToConstant: min(350, maxContentHeight()))
            containerHeightConstraint?.isActive = true
        }
    }

    /// Fraction of the CURRENT interface width a `center` card may occupy in
    /// landscape (§3.2). Matches Android's `createCenterLayoutParams`.
    static let centerLandscapeWidthFactor: CGFloat = 0.7

    /// Widest a `top`/`bottom` banner card may be, so it does not stretch edge to
    /// edge on a tablet. Matches Android's `bannerWidthPx` cap of 560 dp.
    static let bannerMaxWidth: CGFloat = 560

    /// Constraints for a `top`/`bottom` banner: pinned to that safe-area edge with
    /// `standardMargin`, filling the safe area's width less a margin each side.
    static func bannerConstraints(container: UIView,
                                  host: UIView,
                                  safeArea: UILayoutGuide,
                                  pinnedToTop: Bool,
                                  standardMargin: CGFloat) -> [NSLayoutConstraint] {
        let edge = pinnedToTop
            ? container.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: standardMargin)
            : container.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -standardMargin)

        // Preferred width: fill the safe area. Yields to the cap, which is required.
        let fill = container.widthAnchor.constraint(equalTo: safeArea.widthAnchor,
                                                    constant: -2 * standardMargin)
        fill.priority = .defaultHigh

        return [
            edge,
            container.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            container.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor,
                                               constant: standardMargin),
            container.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor,
                                                constant: -standardMargin),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: bannerMaxWidth),
            fill
        ]
    }

    /// Constraints for a `center` card: centred, never closer than
    /// `standardMargin` to a safe-area edge, and in landscape no wider than
    /// `centerLandscapeWidthFactor` of the host. The width is a multiplier on the
    /// host rather than a computed constant so it resolves at layout time.
    static func centerConstraints(container: UIView,
                                  host: UIView,
                                  safeArea: UILayoutGuide,
                                  isLandscape: Bool,
                                  standardMargin: CGFloat) -> [NSLayoutConstraint] {
        var constraints = [
            container.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            container.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor,
                                               constant: standardMargin),
            container.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor,
                                                constant: -standardMargin)
        ]

        if isLandscape {
            constraints.append(container.centerXAnchor.constraint(equalTo: host.centerXAnchor))
            let widthCap = container.widthAnchor.constraint(equalTo: host.widthAnchor,
                                                            multiplier: centerLandscapeWidthFactor)
            widthCap.priority = .defaultHigh
            constraints.append(widthCap)
        } else {
            constraints.append(container.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor,
                                                                  constant: standardMargin))
            constraints.append(container.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor,
                                                                   constant: -standardMargin))
        }

        return constraints
    }

    /// Usable height for the message card: the CURRENT screen's safe-area height
    /// minus the standard 16pt margin on both ends — so every position keeps a
    /// symmetric gap to the screen edges (matches Android's framing). CENTER
    /// additionally keeps the contract cap (50% portrait / 60% landscape,
    /// §3.2) of the current screen height. The previous computation used
    /// max(width, height) — the LONG side even in landscape — producing a "cap"
    /// taller than the screen, which clipped content unreachably.
    private func maxContentHeight() -> CGFloat {
        let standardMargin: CGFloat = 16
        let safeFrameHeight = view.safeAreaLayoutGuide.layoutFrame.height
        let safeHeight = safeFrameHeight > 0 ? safeFrameHeight : UIScreen.main.bounds.height
        let available = max(0, safeHeight - standardMargin * 2)
        let position = IAMPosition(rawValue: message.position) ?? .center
        if position == .center {
            let factor: CGFloat = isInterfaceLandscape() ? 0.6 : 0.5
            return min(available, UIScreen.main.bounds.height * factor)
        }
        return available
    }
    
    private func setupTapGesture() {
        if message.shouldDismissOnTap {
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
            tapGesture.delegate = self
            view.addGestureRecognizer(tapGesture)
        }
    }
    
    private func loadContent() {
        PELogger.debug(
            className: String(describing: IAMViewController.self),
            message: "Loading HTML content"
        )
        containerView.alpha = 0
        
        guard let htmlContent = message.htmlContent else {
            PELogger.error(
                className: String(describing: IAMViewController.self),
                message: "Failed to load message: HTML content is nil"
            )
            dismissMessage()
            return
        }
        
        let isFullScreen = IAMPosition(rawValue: message.position) == .full
        webView.loadHTMLString(
            IAMWebViewUtil.prepareHtmlContent(htmlContent, fillsViewport: isFullScreen),
            baseURL: nil
        )
    }
    
    private func setupDismissTimer() {
        // Only set up timer if duration is greater than 0
        if message.displayDuration > 0 {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(message.displayDuration), repeats: false) { [weak self] _ in
                self?.dismissMessage()
            }
        }
    }
    
    @objc private func dismissMessage() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        detachBridge()
        messageDidDismiss()
        dismiss(animated: true)
    }

    /// Releases the WebKit bridge. `WKUserContentController` retains its script message
    /// handler strongly and is shared with `webView.configuration`, so until this runs
    /// the controller, its `WKWebView` and its orientation observer stay alive. Every
    /// teardown path must call it; calling it more than once is a no-op.
    func detachBridge() {
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "pushengageHandler")
    }
    
    @objc private func handleBackgroundTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        if !containerView.frame.contains(location) {
            dismissMessage()
        }
    }
    
    // MARK: - Action Handling
    
    private func handleAction(actionName: String) {
        PELogger.debug(
            className: String(describing: IAMViewController.self),
            message: "Handling action \(actionName)"
        )
        
        // Get the action from the message's decoded actions
        guard let actions = message.decodedActions,
              let action = actions[actionName] else {
            PELogger.error(
                className: String(describing: IAMViewController.self),
                message: "No action named \(actionName) in campaign \(message.id); button is inert"
            )
            return
        }
        
        // An action type this build does not recognise goes fully inert: no click
        // analytics, no dispatch, and the message stays up. Matches Android,
        // where a null parsed action skips the whole branch — an unrecognised
        // type is an authoring bug, and dismissing on it would hide it from
        // whoever authored the campaign.
        guard action.type != .unrecognised else {
            PELogger.debug(
                className: String(describing: IAMViewController.self),
                message: "Ignoring action \(actionName): unrecognised action type"
            )
            return
        }

        // Every button tap is reported, dismiss buttons included — the backend
        // derives Closes from a click whose btn_type is `dismiss`, so excluding
        // them left that metric permanently empty.
        analyticsManager.recordActionTap(
            messageId: message.id,
            actionId: actionName,
            action: action
        )


        // Handle different action types
        switch action.type {
        case .openURL:
            openExternally(action.parameters["url"])
            
        case .dismiss:
            // Already reported above as a click carrying btn_type `dismiss`, which
            // is what the backend counts as a close.
            dismissMessage()
            
        case .requestNotificationPermission:
            PushEngage.requestNotificationPermission { _, _ in }
            dismissMessage()
            
        case .custom:
            if let delegate = delegate as? IAMCustomActionDelegate {
                delegate.handleCustomAction(actionId: actionName, parameters: action.parameters)
            } else {
                // Forward to delegate using the existing method for backward compatibility
                let _ = action.parameters.merging(["action": actionName]) { (_, new) in new }
                delegate?.handleCustomAction(actionId: actionName, parameters: action.parameters)
            }

        case .unrecognised:
            // Unreachable: the guard above returns before dispatch. Listed
            // explicitly rather than via `default` so adding a future action
            // type still fails the build here instead of silently no-opping.
            break
        }
        
        // Dismiss after action if needed (unless it's already a dismiss action)
        if action.type != .dismiss {
            dismissMessage()
        }
    }
}

// MARK: - Outbound URLs

extension IAMViewController {

    /// Opens a campaign-supplied URL, mirroring Android's `IAMActionHandler.openUrl`:
    /// empty is refused, a scheme-less string defaults to **https**, and anything that is
    /// not http(s) is refused. Without this the SDK handed any parseable string —
    /// `mailto:`, `javascript:`, `file:` — straight to `UIApplication.shared.open`, and a
    /// scheme-less `pushengage.com` failed silently instead of opening.
    ///
    /// - Returns: whether the URL was accepted for opening. The caller dismisses either
    ///   way: a recognised action that fails to execute must still take the message down,
    ///   or a one-button campaign with no close block becomes unclosable (Android
    ///   finding 12).
    @discardableResult
    func openExternally(_ urlString: String?) -> Bool {
        guard let urlString = urlString, !urlString.isEmpty else {
            PELogger.error(
                className: String(describing: IAMViewController.self),
                message: "Empty URL provided"
            )
            return false
        }

        guard let candidate = URL(string: urlString) else {
            PELogger.error(
                className: String(describing: IAMViewController.self),
                message: "Unparseable URL: \(urlString)"
            )
            return false
        }

        let resolved: URL
        if let scheme = candidate.scheme {
            guard Self.isExternallyOpenableScheme(scheme) else {
                PELogger.error(
                    className: String(describing: IAMViewController.self),
                    message: "Invalid URL scheme: \(scheme)"
                )
                return false
            }
            resolved = candidate
        } else {
            // No scheme: default to https, as Android does.
            guard let httpsURL = URL(string: "https://" + urlString) else {
                PELogger.error(
                    className: String(describing: IAMViewController.self),
                    message: "Unparseable URL after defaulting to https: \(urlString)"
                )
                return false
            }
            resolved = httpsURL
        }

        UIApplication.shared.open(resolved, options: [:], completionHandler: nil)
        return true
    }

    /// http(s) only. Case-insensitive, because a scheme is case-insensitive per RFC 3986
    /// and campaign HTML is hand-authored.
    static func isExternallyOpenableScheme(_ scheme: String) -> Bool {
        let lowered = scheme.lowercased()
        return lowered == "http" || lowered == "https"
    }
}

// MARK: - WKNavigationDelegate
extension IAMViewController: WKNavigationDelegate {

    /// Blocks **all** in-place navigation, matching Android's `shouldOverrideUrlLoading`,
    /// which returns `true` for every URL and routes real links to the external browser.
    ///
    /// Before this the IAM WebView had no navigation policy at all: an `<a href>` tap or a
    /// JS redirect replaced the message content in place, and http(s) links loaded inside
    /// the message rather than in the browser. The message is rendered with no address bar,
    /// so in-place navigation lets authored HTML take the user somewhere arbitrary while
    /// they still believe they are looking at the app — which is why Android blocks the
    /// whole class rather than filtering by scheme.
    ///
    /// The initial `loadHTMLString` is allowed: it is the message itself, and it arrives as
    /// `.other` with no http(s) URL to open.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url

        // The message's own content load — not a navigation away from it.
        if navigationAction.navigationType == .other,
           url == nil || url?.absoluteString == "about:blank" {
            decisionHandler(.allow)
            return
        }

        decisionHandler(.cancel)

        guard let url = url else { return }

        // A relative href resolves against the nil baseURL and cannot be opened; treat it
        // as blocked rather than sending the user to a dead address. (Android does the same
        // for hrefs resolved against its dummy base host.)
        guard let scheme = url.scheme, Self.isExternallyOpenableScheme(scheme) else {
            PELogger.debug(
                className: String(describing: IAMViewController.self),
                message: "WebView: blocked in-place navigation to \(url.absoluteString)"
            )
            return
        }

        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        PELogger.debug(
            className: String(describing: IAMViewController.self),
            message: "WebView: opened link in external browser: \(url.absoluteString)"
        )
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Height arrives via PEBridge.reportHeight (explicit, §4.4) or the
        // injected window.onload fallback; a safety re-measure here covers
        // content whose load event fired before the fallback was evaluated.
        webView.evaluateJavaScript(IAMWebViewUtil.heightMeasurementScript) { _, error in
            if let error = error {
                PELogger.error(
                    className: String(describing: IAMViewController.self),
                    message: "Height calculation error: \(error.localizedDescription)"
                )
            }
        }
    }
}

// MARK: - WKScriptMessageHandler
extension IAMViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        PELogger.debug(
            className: String(describing: IAMViewController.self),
            message: "Bridge message \(message.name): \(message.body)"
        )
        guard let body = message.body as? [String: Any] else { return }
        
        if message.name == "pushengageHandler" {
            // Determine the type of message based on its contents
            
            // Height calculation message (has 'id' == 'contentHeight')
            if let id = body["id"] as? String, id == "contentHeight" {
                if let height = body["height"] as? CGFloat {
                    // Cap to the space actually available on the CURRENT screen
                    // (safe area minus symmetric margins; center keeps its §3.2 cap).
                    let maxHeight = maxContentHeight()
                    let finalHeight = min(height, maxHeight)

                    containerHeightConstraint?.constant = finalHeight
                    view.layoutIfNeeded()

                    // Content taller than the card must stay reachable: enable
                    // scrolling ONLY when clipped. Authored HTML commonly sets
                    // `html,body { overflow: hidden }` assuming the container
                    // always matches the content height — when the screen is
                    // shorter, that leaves buttons unreachable. Content that
                    // fits keeps the author's exact styling. (Matches Android's
                    // ensureScrollableIfClipped.)
                    let clipped = height > finalHeight + 4
                    webView.scrollView.isScrollEnabled = clipped
                    if clipped {
                        // Percentage heights are self-referential inside a
                        // content-sized WebView (100% = the clipped viewport,
                        // not the content), so an authored card div with
                        // height:100% gets pinned shorter than its own text —
                        // which then paints past the card background onto the
                        // transparent page (over the app). Same degenerate case
                        // as the 100vh workaround: convert to min-height so the
                        // card can grow with its content.
                        webView.evaluateJavaScript(
                            "(function(){"
                                + "document.documentElement.style.overflowY='auto';"
                                + "document.body.style.overflowY='auto';"
                                + "var kids=document.body.children;"
                                + "for(var i=0;i<kids.length;i++){"
                                + "  if(kids[i].style && kids[i].style.height==='100%'){"
                                + "    kids[i].style.minHeight='100%';"
                                + "    kids[i].style.height='auto';"
                                + "  }"
                                + "}})();"
                        ) { _, error in
                            if let error = error {
                                PELogger.error(
                                    className: String(describing: IAMViewController.self),
                                    message: "clipped-mode JS failed: \(error.localizedDescription)"
                                )
                            }
                        }
                    }

                    UIView.animate(withDuration: 0.2) {
                        self.containerView.alpha = 1
                    }
                }
                return
            }
            
            // Button action message (has 'action')
            if let actionName = body["action"] as? String {
                PELogger.debug(
                    className: String(describing: IAMViewController.self),
                    message: "Button action received: \(actionName)"
                )
                handleAction(actionName: actionName)
                return
            }
        }
    }
}

// MARK: - UIGestureRecognizerDelegate
extension IAMViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let location = touch.location(in: view)
        return !containerView.frame.contains(location)
    }
}
