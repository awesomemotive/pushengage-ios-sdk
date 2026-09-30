import Foundation
import UIKit
import WebKit

/// Manages the queue of in-app messages, handling priority, display timing, and state
class IAMQueueManager: NSObject, IAMViewControllerDelegate {
    
    // MARK: - Singleton
    
    /// Shared instance of the queue manager
    static let shared = IAMQueueManager()
    
    // MARK: - Properties
    
    /// Repository for data operations
    private let repository: IAMRepository
    
    /// Queue state manager for tracking message states
    private let stateManager: IAMQueueStateManager
    
    /// Queue of messages waiting to be displayed
    private var messageQueue: [IAMMessage] = []
    
    /// Currently active/displaying message
    private var activeMessage: IAMMessage?
    

    
    /// Flag indicating if the queue is currently processing
    private var isProcessing: Bool = false
    
    /// Flag indicating if the queue is paused
    private var isPaused: Bool = false
    
    /// Maximum number of messages allowed in the queue
    private let maxQueueSize: Int = 10
    
    /// Minimum delay between displaying messages (in seconds)
    private let minDelayBetweenMessages: TimeInterval = 2.0

    /// Consecutive presentation attempts that found no presentable window. Only the
    /// first is logged at error level: the retry is how IAM recovers once a window
    /// appears, and `PELogger.error` is not gated by the host's logging opt-in, so
    /// shouting every 2s would write to the unified log indefinitely.
    private var consecutivePresentationFailures = 0
    
    /// Window used for displaying messages
    private var messageWindow: UIWindow?

    /// The view controller currently presenting a message, so a programmatic dismissal
    /// (backgrounding, host teardown) can actually take it off screen. Weak: UIKit owns
    /// it while it is presented, and it must not be kept alive after it goes away.
    private weak var activeViewController: IAMViewController?
    
    // MARK: - Initialization
    
    /// Private initializer for singleton
    private init(repository: IAMRepository = IAMRepository(),
                stateManager: IAMQueueStateManager = .shared) {
        self.repository = repository
        self.stateManager = stateManager
        super.init()
        
        // Register for app lifecycle notifications after super.init
        registerForNotifications()
    }
    
    // MARK: - Queue Operations
    
    /// Adds a message to the queue
    /// - Parameter message: The message to add
    func addMessage(_ message: IAMMessage) {
        // Ensure we're on the main thread for UI operations
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.addMessage(message)
            }
            return
        }

        enqueue(message)

        // Process queue if not already processing
        processQueueIfNeeded()
    }

    /// Adds multiple messages to the queue.
    ///
    /// All messages are enqueued first and the queue is processed exactly once
    /// afterwards, so the highest-priority (lowest priority number) message
    /// across the whole batch is chosen for display — not merely the first one
    /// inserted. (Mirrors Android's IAMQueueManager.addMessages.)
    /// - Parameter messages: The messages to add
    func addMessages(_ messages: [IAMMessage]) {
        // Ensure we're on the main thread for UI operations
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.addMessages(messages)
            }
            return
        }

        for message in messages {
            enqueue(message)
        }
        processQueueIfNeeded()
    }

    /// Adds multiple messages to the queue.
    /// - Parameters:
    ///   - messages: The messages to add
    ///   - completion: Completion handler called when messages are added
    func addMessages(_ messages: [IAMMessage], completion: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.addMessages(messages)
            completion()
        }
    }

    /// Inserts a message into the priority-sorted queue without triggering
    /// processing (dedupe + overflow handling included). Callers decide when to
    /// process so batch adds keep priority order across the whole batch.
    private func enqueue(_ message: IAMMessage) {
        // A row deleted out from under a retained object — a sync full-replaces the
        // campaign set — reads its non-optional `id` back as "". Such an entry can
        // never be deduped, removed by id, or attributed in analytics, so it is
        // refused here rather than displayed as an empty message.
        guard message.managedObjectContext != nil, !message.isDeleted, !message.id.isEmpty else {
            PELogger.error(
                className: String(describing: IAMQueueManager.self),
                message: "IAM queue: refusing a message whose stored campaign is gone"
            )
            return
        }

        // Deduped before the overflow branch: otherwise a re-enqueue of an id already
        // queued evicts a different campaign to make room for a duplicate.
        guard !messageQueue.contains(where: { $0.id == message.id }) else {
            return
        }

        // Check if queue is full
        if messageQueue.count >= maxQueueSize {
            handleQueueOverflow(message)
            return
        }

        // Insert message with priority
        insertMessageWithPriority(message)
    }
    
    /// Removes a message from the queue
    /// - Parameter messageId: The ID of the message to remove
    func removeMessage(withId messageId: String) {
        if Thread.isMainThread {
            messageQueue.removeAll { $0.id == messageId }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.removeMessage(withId: messageId)
            }
        }
    }

    /// IDs of the currently queued messages, in display order. Main thread only.
    var queuedMessageIds: [String] {
        messageQueue.map { $0.id }
    }
    
    /// Clears all messages from the queue
    func clearQueue() {
        if Thread.isMainThread {
            messageQueue.removeAll()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.messageQueue.removeAll()
            }
        }
    }
    
    /// Clears all messages from the queue
    func clearQueue(completion: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.messageQueue.removeAll()
            completion()
        }
    }
    
    /// Pauses the queue processing
    func pauseQueue() {
        if Thread.isMainThread {
            isPaused = true
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.isPaused = true
            }
        }
    }
    
    /// Pauses the queue processing
    func pauseQueue(completion: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.isPaused = true
            completion()
        }
    }
    
    /// Resumes the queue processing
    func resumeQueue() {
        if Thread.isMainThread {
            isPaused = false
            processQueueIfNeeded()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.isPaused = false
                self?.processQueueIfNeeded()
            }
        }
    }
    
    /// Resumes the queue processing
    func resumeQueue(completion: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.isPaused = false
            self?.processQueueIfNeeded()
            completion()
        }
    }
    
    // MARK: - Queue Processing
    
    /// Processes the next message in the queue if conditions are met
    private func processQueueIfNeeded() {
        guard !isProcessing, !isPaused, activeMessage == nil else {
            return
        }
        
        processQueue()
    }
    
    /// Processes the queue to display the next eligible message
    private func processQueue() {
        guard !messageQueue.isEmpty else {
            return
        }
        
        // Ensure we're on the main thread for UI operations
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.processQueue()
            }
            return
        }
        
        // Find the next eligible message
        guard let nextMessage = getNextEligibleMessage() else {
            return
        }
        
        // Mark as processing
        isProcessing = true
        
        // Set as active message
        activeMessage = nextMessage
        
        // Remove from queue
        removeMessage(withId: nextMessage.id)
        
        // Display the message
        displayMessage(nextMessage)
    }
    
    /// Gets the next eligible message from the queue
    /// - Returns: The next eligible message, or nil if none are eligible
    private func getNextEligibleMessage() -> IAMMessage? {
        for message in messageQueue {
            if isEligibleForDisplay(message) {
                return message
            }
        }
        return nil
    }
    
    /// Checks if a message is eligible for display
    /// - Parameter message: The message to check
    /// - Returns: True if the message is eligible for display
    private func isEligibleForDisplay(_ message: IAMMessage) -> Bool {
        // Check if message is valid
        guard message.isValid else {
            return false
        }
        
        // Check frequency cap
        guard message.canDisplay() else {
            return false
        }
        
        // Additional eligibility checks can be added here
        
        return true
    }
    
    /// Handles queue overflow when the queue is full
    /// - Parameter message: The message that would overflow the queue
    private func handleQueueOverflow(_ message: IAMMessage) {
        // If the new message has higher priority than the lowest priority message in the queue,
        // replace the lowest priority message
        if let lowestPriorityIndex = findLowestPriorityMessageIndex(),
           let lowestPriorityMessage = messageQueue[safe: lowestPriorityIndex],
           message.priority < lowestPriorityMessage.priority {
            // Logged at error level because it is otherwise undiagnosable: an auto-trigger
            // campaign that leaves the queue is not re-evaluated until the next app open
            // (processAutoTriggers runs once per session), so the report is "it did not
            // show today". Reaching this at all needs maxQueueSize campaigns queued.
            PELogger.error(
                className: String(describing: IAMQueueManager.self),
                message: "IAM queue full (\(maxQueueSize)): evicted campaign "
                    + "\(lowestPriorityMessage.id) (priority \(lowestPriorityMessage.priority)) "
                    + "for \(message.id) (priority \(message.priority)). The evicted campaign "
                    + "will not display until something re-evaluates it."
            )
            messageQueue.remove(at: lowestPriorityIndex)
            insertMessageWithPriority(message)
            return
        }

        PELogger.error(
            className: String(describing: IAMQueueManager.self),
            message: "IAM queue full (\(maxQueueSize)): refused campaign \(message.id) "
                + "(priority \(message.priority)) — nothing queued ranks lower. It will not "
                + "display until something re-evaluates it."
        )
    }
    
    /// Finds the index of the lowest priority message in the queue
    /// - Returns: The index of the lowest priority message, or nil if the queue is empty
    private func findLowestPriorityMessageIndex() -> Int? {
        guard !messageQueue.isEmpty else {
            return nil
        }
        
        var lowestPriorityIndex = 0
        var lowestPriority = messageQueue[0].priority
        
        for (index, message) in messageQueue.enumerated() {
            if message.priority > lowestPriority {
                lowestPriority = message.priority
                lowestPriorityIndex = index
            }
        }
        
        return lowestPriorityIndex
    }
    
    /// Inserts a message into the queue based on its priority
    /// - Parameter message: The message to insert
    private func insertMessageWithPriority(_ message: IAMMessage) {
        // Lower priority value means higher priority
        let index = messageQueue.firstIndex { $0.priority > message.priority } ?? messageQueue.endIndex
        messageQueue.insert(message, at: index)
    }
    
    // MARK: - Message Display
    
    /// Displays a message
    /// - Parameter message: The message to display
    private func displayMessage(_ message: IAMMessage) {
        // Get the top view controller based on iOS version
        let topVC: UIViewController?
        
        topVC = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive })
            .flatMap { $0 as? UIWindowScene }
            .flatMap { $0.windows.first(where: { $0.isKeyWindow }) }?
            .rootViewController?
            .topMostViewController()
        
        guard let viewController = topVC else {
            consecutivePresentationFailures += 1
            let detail = "Could not find top view controller to present message "
                + "(attempt \(consecutivePresentationFailures))"
            if consecutivePresentationFailures == 1 {
                PELogger.error(className: String(describing: IAMQueueManager.self),
                               message: detail)
            } else {
                PELogger.debug(className: String(describing: IAMQueueManager.self),
                               message: detail)
            }
            // Reset processing state, put the message back, and try again later
            isProcessing = false
            activeMessage = nil
            enqueue(message)
            DispatchQueue.main.asyncAfter(deadline: .now() + minDelayBetweenMessages) { [weak self] in
                self?.processQueueIfNeeded()
            }
            return
        }
        
        consecutivePresentationFailures = 0

        // Set active message
        activeMessage = message
        
        // Create and configure view controller
        let messageVC = IAMViewController(message: message)
        messageVC.delegate = self
        activeViewController = messageVC
        
        // Post will display notification before presenting
        NotificationCenter.default.post(
            name: .iamMessageWillDisplay,
            object: nil,
            userInfo: ["messageId": message.id]
        )
        
        // Present the view controller
        DispatchQueue.main.async {
            viewController.present(messageVC, animated: true) {
                // Track impression when message is presented
                IAMAnalyticsManager.shared.trackImpression(messageId: message.id)

                // The display record is written HERE, at display time, not on dismissal
                // — matching Android, where `IAMAnalyticsManager.recordImpression`
                // calls `recordMessageDisplay` as the message goes up. Recording on
                // dismissal instead meant any display that never reached a dismissal
                // was never counted: the app killed while a message was on screen left
                // the frequency cap unaware of it, so a `one_time` campaign showed
                // again. Frequency caps read these records, so "shown" has to mean
                // "recorded".
                do {
                    try self.repository.recordDisplay(for: message)
                } catch {
                    PELogger.error(
                        className: String(describing: IAMQueueManager.self),
                        message: "Failed to record message display: \(error.localizedDescription)"
                    )
                }
                
                // Post did display notification after presentation
                NotificationCenter.default.post(
                    name: .iamMessageDidDisplay,
                    object: nil,
                    userInfo: ["messageId": message.id]
                )
            }
        }
    }
    
    /// Records an error that occurred during message display
    /// - Parameters:
    ///   - message: The message that failed to display
    ///   - error: The error that occurred
    private func recordMessageDisplayError(message: IAMMessage, error: Error) {
        // Reset processing state
        isProcessing = false
        activeMessage = nil
        
        // Log error for debugging
        PELogger.error(
            className: String(describing: IAMQueueManager.self),
            message: "Message display error: \(error.localizedDescription)"
        )
        
        // Process next message after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + minDelayBetweenMessages) { [weak self] in
            self?.processQueueIfNeeded()
        }
    }
    
    /// Updates the message window with the current scene
    private func updateMessageWindow() {
        // Prefer the key window's scene, then any foreground-active scene.
        if let windowScene = Utility.keyWindow?.windowScene {
            createWindowWithScene(windowScene)
        } else if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            createWindowWithScene(windowScene)
        } else {
            // No scene to attach to yet — a scene-less window still needs a frame.
            createLegacyWindow()
        }
    }
    
    /// Creates a window attached to the given scene
    private func createWindowWithScene(_ windowScene: UIWindowScene) {
        messageWindow = UIWindow(windowScene: windowScene)
        messageWindow?.windowLevel = .alert + 1
        messageWindow?.backgroundColor = .clear
        messageWindow?.isHidden = true
    }
    
    /// Frame-based window, used only when no window scene is available to attach to.
    private func createLegacyWindow() {
        messageWindow = UIWindow(frame: UIScreen.main.bounds)
        messageWindow?.windowLevel = .alert + 1
        messageWindow?.backgroundColor = .clear
        messageWindow?.isHidden = true
    }
    
    /// Prepares the window for displaying messages
    private func prepareMessageWindow() {
        // Ensure window is created/updated
        if messageWindow == nil {
            updateMessageWindow()
        }
        
        guard let window = messageWindow else { return }
        
        if window.isHidden {
            // Re-attach to a scene if this window has none.
            if window.windowScene == nil {
                updateMessageWindow()
            }
            window.isHidden = false
            window.makeKeyAndVisible()
        }
    }
    
    /// Handles message dismissal
    private func handleMessageDismissed() {
        // Clear active message and view
        activeMessage = nil
        
        // Reset processing flag
        isProcessing = false
        
        // Hide window if no more messages
        if messageQueue.isEmpty {
            messageWindow?.isHidden = true
        }
        
        // Process next message after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + minDelayBetweenMessages) { [weak self] in
            self?.processQueueIfNeeded()
        }
    }
    
    // MARK: - App Lifecycle
    
    /// Registers for app lifecycle notifications
    private func registerForNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSceneDidActivate),
            name: UIScene.didActivateNotification,
            object: nil
        )
    }
    
    /// Handles app entering background
    @objc private func handleAppDidEnterBackground() {
        // Dismiss any active message
        dismissActiveMessage()
    }
    
    /// Handles app entering foreground
    @objc private func handleAppWillEnterForeground() {
        // Resume queue when app comes to foreground
        resumeQueue()
    }
    
    @objc private func handleSceneDidActivate(_ notification: Notification) {
        if let scene = notification.object as? UIWindowScene {
            createWindowWithScene(scene)
        }
    }
    
    // MARK: - Deinitializer
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// Dismisses the currently active message if any.
    ///
    /// Routes through `messageDidDismiss()` rather than clearing state directly. The
    /// previous version nil'd `activeMessage` and `isProcessing` and tore down
    /// `messageWindow` — but the message is presented as a modal view controller, not
    /// into that window, so nothing actually left the screen and three things broke at
    /// once: the message stayed visible, the queue believed nothing was showing (so the
    /// next trigger could present on top of it), and the eventual real dismissal hit
    /// `messageDidDismiss`'s `activeMessage` guard and returned early — losing the
    /// display record, so the campaign's frequency cap never counted that display.
    /// Reproduced on device: background and return with a message up, dismiss it, and
    /// `iam_display_records` did not grow.
    func dismissActiveMessage() {
        // Ensure we're on the main thread for UI operations
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.dismissActiveMessage()
            }
            return
        }

        guard activeMessage != nil else { return }

        takeMessageOffScreen()

        // Record the display, update state and advance the queue exactly as a normal
        // dismissal does. This clears activeMessage, so a later delegate callback from
        // the same view controller is a no-op and cannot double-record.
        messageDidDismiss()
    }

    /// Dismisses the currently active message if any
    func dismissActiveMessage(completion: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.activeMessage != nil else {
                completion()
                return
            }

            self.takeMessageOffScreen()
            self.messageDidDismiss()
            completion()
        }
    }

    /// Removes the message from the screen without touching queue bookkeeping.
    /// Main-queue only.
    private func takeMessageOffScreen() {
        if let controller = activeViewController {
            // This path does not go through the controller's own dismissMessage(), so the
            // bridge has to be released here or the controller and its WKWebView leak.
            controller.detachBridge()
            if controller.presentingViewController != nil {
                controller.dismiss(animated: false)
            }
        }
        activeViewController = nil
        messageWindow?.isHidden = true
        messageWindow = nil
    }
    
    // MARK: - IAMViewControllerDelegate
    
    func messageDidDismiss() {
        guard let message = activeMessage else { return }
        

        
        PELogger.info(
            className: String(describing: IAMQueueManager.self),
            message: "Message \(message.id) dismissed"
        )
        
        // The display record is NOT written here. It is written when the message goes up
        // (see `displayMessage`), matching Android. Writing it again on dismissal would
        // double-count every display and halve every frequency cap.

        // Update state
        stateManager.updateState(for: message.id, to: .dismissed)

        // Deliberately not reported. `close` counts explicit rejection — a
        // dismiss-BUTTON tap, which the view controller reports as a click carrying
        // btn_type `dismiss`. This path also covers tap-outside, swipe, back and
        // auto-dismiss on displayDuration, and a timer expiry is not a user action
        // at all; counting it would turn a rejection metric into a mix of rejection
        // and expiry. Consequence to accept: Impressions − Clicks − Closes does not
        // reconcile.


        // Post notification
        NotificationCenter.default.post(
            name: .iamMessageDidDismiss,
            object: nil,
            userInfo: ["messageId": message.id]
        )
        
        // Handle cleanup and process next message
        handleMessageDismissed()
        
        PELogger.debug(
            className: String(describing: IAMQueueManager.self),
            message: "Message dismissed successfully: \(message.id)"
        )
    }
    
    func handleCustomAction(actionId: String, parameters: [String: String]) {
        guard let message = activeMessage else { return }

        // NOTE: no click tracking here — IAMViewController.handleAction already
        // tracks the button click for every non-dismiss action before delegating.
        // Tracking again here double-counted every custom click.
        //
        // NOTE: no URL handling here either — custom parameters are forwarded
        // VERBATIM to the host app (contract §3.8); opening parameters["url"]
        // automatically was open_url's job leaking into custom, and diverged
        // from Android (which forwards without side effects).

        // Forward custom action to the custom action handler if available
        if let peManager = PushEngage.manager as? PEManager, let customActionHandler = peManager.customActionHandler {
            customActionHandler(actionId, parameters)
        } else {
            PELogger.error(
                className: String(describing: IAMQueueManager.self),
                message: "No custom action handler set — register via PushEngage.setIAMCustomActionHandler"
            )
        }

        PELogger.debug(
            className: String(describing: IAMQueueManager.self),
            message: "Custom action handled for message \(message.id): \(actionId)"
        )
    }
    
    // MARK: - Selector Methods
    
    /// Adds a message to the queue using selector (for pre-iOS 13 compatibility)
    /// - Parameter message: The message to add
    @objc func addMessageFromSelector(_ message: IAMMessage) {
        addMessage(message)
    }
}

// MARK: - Notification Names

private extension Notification.Name {
    static let iamMessageWillDisplay = Notification.Name("com.pushengage.iam.messageWillDisplay")
    static let iamMessageDidDisplay = Notification.Name("com.pushengage.iam.messageDidDisplay")
    static let iamMessageWillDismiss = Notification.Name("com.pushengage.iam.messageWillDismiss")
    static let iamMessageDidDismiss = Notification.Name("com.pushengage.iam.messageDidDismiss")
}

// MARK: - Array Extension

private extension Array {
    /// Safe subscript that returns nil if index is out of bounds
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - UIViewController Extension

private extension UIViewController {
    /// Returns the topmost view controller in the hierarchy
    func topMostViewController() -> UIViewController {
        // If this view controller is presenting another controller
        if let presentedViewController = presentedViewController {
            return presentedViewController.topMostViewController()
        }
        
        // If this is a navigation controller, return visible view controller
        if let navigationController = self as? UINavigationController {
            return navigationController.visibleViewController?.topMostViewController() ?? self
        }
        
        // If this is a tab bar controller, return selected view controller
        if let tabBarController = self as? UITabBarController {
            return tabBarController.selectedViewController?.topMostViewController() ?? self
        }
        
        // If none of the above, return self
        return self
    }
} 

