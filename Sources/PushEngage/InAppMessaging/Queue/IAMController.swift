import Foundation
import UIKit
import UserNotifications

/// Main controller for the In-App Messaging system
@objc final class IAMController: NSObject {
    
    // MARK: - Singleton
    
    /// Shared instance of the controller
    static let shared = IAMController()

    // MARK: - Properties
    
    /// Queue manager for handling message queue
    private let queueManager: IAMQueueManager
    
    /// Display rules engine for evaluating message eligibility
    private let rulesEngine: IAMDisplayRulesEngine
    
    /// Queue state manager for tracking message states
    private let stateManager: IAMQueueStateManager
    
    /// Repository for data operations
    private let repository: IAMRepository
    
    /// Network state manager for monitoring connectivity
    private let networkStateManager: IAMNetworkStateManager
    
    /// Sync manager for handling data synchronization
    private lazy var syncManager: IAMSyncManager = {
        return IAMSyncManager.shared
    }()
    
    /// Flag indicating if the IAM system is enabled
    private var isEnabled: Bool = true

    /// App-open auto-triggers fire once per app session (this singleton lives for
    /// the process). Set on the first `didBecomeActive`; never re-fires within the
    /// session, so auto messages show when the app opens — not on every foreground.
    private var appOpenHandled = false

    /// Monotonic time of the app-open instant. `trigger.delay` counts from here,
    /// not from when the sync finished, so a slow sync eats into the delay rather
    /// than being added on top of it. nil = app open not seen yet.
    private var appOpenAt: TimeInterval?

    /// Holds back app-open campaigns inside their delay window; pauses on
    /// backgrounding so background time never counts toward the delay. Injectable
    /// so tests can drive a countdown without sleeping.
    lazy var triggerDelayScheduler = IAMController.productionDelayScheduler(for: self)

    /// The scheduler the SDK runs with. Tests that swap in hand-fired timers restore
    /// this, since the controller is a process-wide singleton.
    static func productionDelayScheduler(for controller: IAMController) -> IAMTriggerDelayScheduler {
        IAMTriggerDelayScheduler { [weak controller] messageId in
            controller?.releaseDelayedMessage(id: messageId)
        }
    }

    /// Enqueues a campaign whose `trigger.delay` has been served.
    ///
    /// The campaign is re-read rather than carried through the countdown: a sync
    /// full-replaces the campaign set, so the row may have been deleted — and its
    /// eligibility may have lapsed — while the delay ran.
    func releaseDelayedMessage(id messageId: String) {
        guard Thread.isMainThread else {
            runOnMain { [weak self] in self?.releaseDelayedMessage(id: messageId) }
            return
        }

        do {
            guard let message = try repository.fetchMessage(withId: messageId) else {
                PELogger.debug(
                    className: String(describing: IAMController.self),
                    message: "IAM delay: message \(messageId) no longer exists — not queueing"
                )
                return
            }

            guard message.isValid,
                  !isDeferred(message),
                  rulesEngine.isEligibleForDisplay(message),
                  message.canDisplay() else {
                PELogger.debug(
                    className: String(describing: IAMController.self),
                    message: "IAM delay: message \(messageId) no longer eligible — not queueing"
                )
                return
            }

            queueManager.addMessage(message)
        } catch {
            PELogger.error(
                className: String(describing: IAMController.self),
                message: "IAM delay: could not re-read message \(messageId): \(error.localizedDescription)"
            )
        }
    }

    /// Supplies the subscriber-backed audience data. Swappable so the app-open
    /// path can be exercised without the network.
    var subscriberStateProvider: IAMSubscriberStateProviding = IAMSubscriberStateProvider()

    /// Reads the notification-authorization state. Audience evaluation is
    /// synchronous but the status is not, so it is read here and cached.
    var notificationPermissionReader: (@escaping (Bool) -> Void) -> Void =
        IAMController.systemNotificationPermissionReader

    /// The real authorization-status read. Provisional and ephemeral count as
    /// enabled — notifications can be delivered in both.
    static let systemNotificationPermissionReader: (@escaping (Bool) -> Void) -> Void = { completion in
        UNUserNotificationCenter.current().peGetAuthorizationStatus { status in
            switch status {
            case .authorized, .provisional, .ephemeral:
                completion(true)
            default:
                completion(false)
            }
        }
    }

    // MARK: - Initialization
    
    /// Private initializer for singleton
    private init(
        queueManager: IAMQueueManager = .shared,
        rulesEngine: IAMDisplayRulesEngine = .shared,
        stateManager: IAMQueueStateManager = .shared,
        repository: IAMRepository = IAMRepository(),
        networkStateManager: IAMNetworkStateManager = .shared
    ) {
        self.queueManager = queueManager
        self.rulesEngine = rulesEngine
        self.stateManager = stateManager
        self.repository = repository
        self.networkStateManager = networkStateManager
        
        // Call super.init before using self
        super.init()

        // Set up app lifecycle observers
        setupAppLifecycleObservers()
    }
    
    // MARK: - Public API
    
    /// Enables the IAM system
    func enable() {
        isEnabled = true
        queueManager.resumeQueue()
    }
    
    /// Enables the IAM system
    func enable(completion: @escaping () -> Void) {
        isEnabled = true
        queueManager.resumeQueue(completion: completion)
    }
    
    /// Disables the IAM system
    func disable() {
        isEnabled = false
        queueManager.pauseQueue()
    }
    
    /// Disables the IAM system
    func disable(completion: @escaping () -> Void) {
        isEnabled = false
        queueManager.pauseQueue(completion: completion)
    }
    
    /// Processes messages for a trigger event
    /// - Parameter triggerName: Name of the trigger event
    func processTrigger(_ triggerName: String) {
        processTrigger(triggerName, parameters: nil)
    }
    
    /// Processes messages for a trigger event
    /// - Parameters:
    ///   - triggerName: Name of the trigger event
    ///   - completion: Completion handler called when processing is done
    func processTrigger(_ triggerName: String, completion: @escaping () -> Void) {
        guard isEnabled else {
            completion()
            return
        }

        runOnMain { [weak self] in
            guard let self = self else {
                completion()
                return
            }
            do {
                // Fetch messages for the trigger
                let messages = try self.repository.fetchMessages(forTrigger: triggerName)

                // Trigger conditions apply even with no parameters: a campaign that
                // declares them must satisfy them.
                let matchingMessages = IAMTriggerMatcher.filter(messages: messages, parameters: nil)

                // Filter eligible messages
                let eligibleMessages = matchingMessages.filter {
                    !self.isDeferred($0) && self.rulesEngine.isEligibleForDisplay($0)
                }

                // Add to queue
                self.queueManager.addMessages(eligibleMessages, completion: completion)
            } catch {
                PELogger.error(
                    className: String(describing: IAMController.self),
                    message: "Error processing trigger: \(error.localizedDescription)"
                )
                completion()
            }
        }
    }

    /// Whether `message` should be skipped this pass because its audience targets
    /// subscriber data that has not been fetched yet.
    ///
    /// Defer, don't decide: evaluating would be wrong in both directions — a
    /// positive operator fails, hiding the campaign from every fresh install, and a
    /// negative one passes, which with OR groups shows it to *everyone*.
    private func isDeferred(_ message: IAMMessage) -> Bool {
        guard rulesEngine.requiresUnavailableSubscriberState(message) else { return false }
        PELogger.debug(
            className: String(describing: IAMController.self),
            message: "Deferring message \(message.id): audience needs subscriber data "
                + "that has not been fetched yet"
        )
        return true
    }

    /// Registers the background-refresh launch handler.
    ///
    /// Must be called from `didFinishLaunching`, synchronously: `BGTaskScheduler` raises
    /// if a launch handler is registered after it returns. Deliberately not in `init` —
    /// `setAppId` also builds this singleton, and wrappers call that after the app is
    /// already active. Safe to call more than once.
    func registerBackgroundRefresh() {
        IAMBackgroundRefresh.shared.registerIfPermitted()
    }

    /// Runs work on the main queue, inline when already there. Store reads go
    /// through the main-queue-confined view context, so every read path is
    /// funnelled here.
    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
    
    /// Human-readable snapshot of the on-device In-App Messaging store —
    /// campaign counts and, per campaign, its trigger, position, frequency
    /// display count, actions, and HTML content. Intended for debugging/QA
    /// (mirrors Android's IAMRepository.getDatabaseSummary). Internal — the
    /// former public `PushEngage.getIAMDatabaseState()` was removed, so nothing
    /// outside the SDK reaches this.
    func getDatabaseSummary() -> String {
        guard Thread.isMainThread else {
            return DispatchQueue.main.sync { getDatabaseSummary() }
        }
        var summary = ""
        do {
            let messages = try repository.fetchAllMessages()
            summary += "Total Campaigns: \(messages.count)\n"
            summary += "Unsynced Analytics Events: \(try repository.unsyncedAnalyticsEventCount())\n"

            if !messages.isEmpty {
                summary += "\nCampaigns:\n"
                for message in messages {
                    let displayCount = (message.displayRecords as? Set<IAMDisplayRecord>)?.count ?? 0
                    let triggerJSON = message.trigger.flatMap { String(data: $0, encoding: .utf8) } ?? "-"
                    let actionsJSON = message.actions.flatMap { String(data: $0, encoding: .utf8) } ?? "-"
                    let frequencyJSON = message.frequency.flatMap { String(data: $0, encoding: .utf8) } ?? "-"
                    summary += "• ID: \(message.id)\n"
                    summary += "    Position: \(message.position)\n"
                    summary += "    Trigger: \(triggerJSON)\n"
                    summary += "    Frequency: \(frequencyJSON) (displayed \(displayCount)x)\n"
                    summary += "    Actions: \(actionsJSON)\n"
                    summary += "    HTML:\n\(message.htmlContent ?? "-")\n"
                }
            }
        } catch {
            summary += "Failed to read IAM store: \(error.localizedDescription)\n"
        }
        return summary
    }

    /// Dismisses the currently displaying message
    func dismissCurrentMessage() {
        queueManager.dismissActiveMessage()
    }
    
    /// Dismisses the currently displaying message
    func dismissCurrentMessage(completion: @escaping () -> Void) {
        queueManager.dismissActiveMessage(completion: completion)
    }
    
    /// Clears all messages from the queue
    func clearQueue() {
        queueManager.clearQueue()
    }
    
    /// Clears all messages from the queue
    func clearQueue(completion: @escaping () -> Void) {
        queueManager.clearQueue(completion: completion)
    }
    
    /// Syncs messages with the server
    /// - Parameter completion: Completion handler called when sync is complete
    func syncMessages(completion: @escaping (Error?) -> Void) {
        guard isEnabled else {
            completion(nil)
            return
        }
        
        // No pre-flight connectivity gate (reachability reports offline for
        // the first moments after launch): let the request fail naturally —
        // IAMSyncManager retries when the network state changes.

        // Clear out expired campaigns before syncing new ones
        do {
            try repository.deleteExpiredMessages()
        } catch {
            completion(error)
            return
        }

        IAMSyncManager.shared.syncMessages { error in
            DispatchQueue.main.async {
                completion(error)
            }
        }
    }
    
    /// One trigger condition for the bundled offline content, so that content
    /// exercises the current `conditions` shape rather than only the legacy
    /// `parameters` branch.
    private static func triggerCondition(field: String,
                                         op: String = "eq",
                                         value: String,
                                         type: String = "string") -> IAMRawJSON? {
        let json = """
        [{"field":"\(field)","type":"\(type)","op":"\(op)","value":["\(value)"]}]
        """
        return try? IAMRawJSON(data: Data(json.utf8))
    }

    /// Bundled reference campaigns (§Appendix A). Kept only as offline/test
    /// content for IAMNetworkServiceMock — campaigns come from the backend in
    /// production, so this content never reaches the store unless the mock
    /// service is injected explicitly.
    /// - Returns: Array of mock IAMMessageResponse objects
    static func mockMessages() -> [IAMMessageResponse] {
        // Create date formatter for start/end dates
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        // Current date for setting validity periods
        let now = Date()
        let calendar = Calendar.current
        let futureDate = calendar.date(byAdding: .day, value: 30, to: now)!
        
        // Create sample messages for different positions
        return [
            // Notification Permission Message
            IAMMessageResponse(
                id: "notification-permission-1",
                position: .center,
                htmlContent: """
                <!DOCTYPE html>
                <html>
                <head>
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <style>
                        /* Reset defaults and ensure content fits properly */
                        * { margin: 0; padding: 0; box-sizing: border-box; }
                        
                        html, body {
                            width: 100%;
                            height: auto !important;
                            overflow: hidden;
                            background: transparent;
                            margin: 0;
                            padding: 0;
                        }
                        
                        .modal {
                            background-color: white;
                            padding: 20px;
                            border-radius: 12px;
                            box-shadow: 0 4px 8px rgba(0,0,0,0.1);
                            font-family: -apple-system, system-ui, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
                            max-width: 100%;
                            display: table;
                            width: 100%;
                        }
                        
                        .title {
                            font-weight: bold;
                            font-size: 18px;
                            margin-bottom: 10px;
                            color: #333;
                        }
                        
                        .content {
                            font-size: 14px;
                            color: #666;
                            margin-bottom: 15px;
                        }
                        
                        .footer {
                            display: flex;
                            justify-content: space-between;
                        }
                        
                        .primary-button {
                            background-color: #2196F3;
                            color: white;
                            padding: 10px 15px;
                            border-radius: 6px;
                            text-align: center;
                            font-weight: bold;
                            flex: 1;
                            margin-right: 10px;
                            cursor: pointer;
                        }
                        
                        .secondary-button {
                            background-color: #f1f1f1;
                            color: #333;
                            padding: 10px 15px;
                            border-radius: 6px;
                            text-align: center;
                            font-weight: bold;
                            flex: 1;
                            cursor: pointer;
                        }
                    </style>
                    <script>
                        document.addEventListener('DOMContentLoaded', function() {
                            const modalHeight = document.querySelector('.modal').offsetHeight;
                            PEBridge.reportHeight(modalHeight);
                        });
                    </script>
                </head>
                <body>
                    <div class="modal">
                        <div class="title">Stay Updated</div>
                        <div class="title">Always first</div>
                        <div class="content">Enable notifications to receive important updates and offers.</div>
                        <div class="footer">
                            <div class="primary-button" onclick="PEBridge.handleAction('enable_notifications')">Enable</div>
                            <div class="secondary-button" onclick="PEBridge.handleAction('dismiss_action')">Not Now</div>
                        </div>
                    </div>
                </body>
                </html>
                """,
                displayDuration: 0,
                shouldDismissOnTap: false,
                actions: [
                    "enable_notifications": IAMAction(
                        type: .requestNotificationPermission,
                        parameters: [:]
                    ),
                    "dismiss_action": IAMAction(
                        type: .dismiss,
                        parameters: [:]
                    )
                ],
                startDate: now,
                endDate: futureDate,
                priority: 1,
                audience: nil,
                frequency: IAMFrequency(type: .recurring, interval: 0),
                trigger: IAMTriggerCondition(type: "custom", event: "notification_permission",
                                             conditions: triggerCondition(field: "type", value: "permission"))
            ),
            
            // Banner (Top) Message
            IAMMessageResponse(
                id: "banner-message-1",
                position: .top,
                htmlContent: """
                <!DOCTYPE html>
                <html>
                <head>
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <style>
                        /* Reset defaults and ensure content fits properly */
                        * { margin: 0; padding: 0; box-sizing: border-box; }
                        
                        html, body {
                            width: 100%;
                            height: auto !important;
                            overflow: hidden;
                            background: transparent;
                            margin: 0;
                            padding: 0;
                        }
                        
                        .banner {
                            background-color: #4CAF50;
                            color: white;
                            padding: 12px;
                            border-radius: 8px;
                            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                            font-family: -apple-system, system-ui, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
                            max-width: 100%;
                            display: table; /* Force fit to content */
                            width: 100%;
                        }
                        
                        .title {
                            font-weight: bold;
                            margin-bottom: 5px;
                            font-size: 16px;
                        }
                        
                        .content {
                            font-size: 14px;
                            margin-bottom: 8px;
                        }
                        
                        .button {
                            background-color: white;
                            color: #4CAF50;
                            padding: 8px 12px;
                            border-radius: 4px;
                            text-align: center;
                            font-weight: bold;
                            display: inline-block;
                            cursor: pointer;
                            font-size: 14px;
                        }
                    </style>
                    <script>
                        document.addEventListener('DOMContentLoaded', function() {
                            // This immediately reports the exact content height
                            // using the most reliable method
                            const bannerHeight = document.querySelector('.banner').offsetHeight;
                            PEBridge.reportHeight(bannerHeight);
                        });
                    </script>
                </head>
                <body>
                    <div class="banner">
                        <div class="title">Banner Notification</div>
                        <div class="content">This is a sample banner notification from the top.</div>
                        <div class="button" onclick="PEBridge.handleAction('banner_action')">Learn More</div>
                    </div>
                </body>
                </html>
                """,
                displayDuration: 5,
                shouldDismissOnTap: true,
                actions: [
                    "banner_action": IAMAction(
                        type: .openURL,
                        parameters: ["url": "https://pushengage.com/features"]
                    ),
                    "close_button": IAMAction(
                        type: .dismiss,
                        parameters: [:]
                    )
                ],
                startDate: now,
                endDate: futureDate,
                priority: 2,
                audience: nil,
                frequency: IAMFrequency(type: .recurring, interval: 0),
                trigger: IAMTriggerCondition(type: "custom", event: "banner_message",
                                             conditions: triggerCondition(field: "type", value: "banner"))
            ),
            
            // Center Modal Message
            IAMMessageResponse(
                id: "center-message-1",
                position: .center,
                htmlContent: """
                <!DOCTYPE html>
                <html>
                <head>
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <style>
                        /* Reset defaults and ensure content fits properly */
                        * { margin: 0; padding: 0; box-sizing: border-box; }
                        
                        html, body {
                            width: 100%;
                            height: auto !important;
                            overflow: hidden;
                            background: transparent;
                            margin: 0;
                            padding: 0;
                        }
                        
                        .modal {
                            background-color: white;
                            padding: 20px;
                            border-radius: 12px;
                            box-shadow: 0 4px 8px rgba(0,0,0,0.1);
                            font-family: -apple-system, system-ui, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
                            max-width: 100%;
                            display: table; /* Force fit to content */
                            width: 100%;
                        }
                        
                        .title {
                            font-weight: bold;
                            font-size: 18px;
                            margin-bottom: 10px;
                            color: #333;
                        }
                        
                        .content {
                            font-size: 14px;
                            color: #666;
                            margin-bottom: 15px;
                        }
                        
                        .footer {
                            display: flex;
                            justify-content: space-between;
                        }
                        
                        .primary-button {
                            background-color: #2196F3;
                            color: white;
                            padding: 10px 15px;
                            border-radius: 6px;
                            text-align: center;
                            font-weight: bold;
                            flex: 1;
                            margin-right: 10px;
                            cursor: pointer;
                        }
                        
                        .secondary-button {
                            background-color: #f1f1f1;
                            color: #333;
                            padding: 10px 15px;
                            border-radius: 6px;
                            text-align: center;
                            font-weight: bold;
                            flex: 1;
                            cursor: pointer;
                        }
                    </style>
                    <script>
                        document.addEventListener('DOMContentLoaded', function() {
                            // Immediately reports the exact content height
                            const modalHeight = document.querySelector('.modal').offsetHeight;
                            PEBridge.reportHeight(modalHeight);
                        });
                    </script>
                </head>
                <body>
                    <div class="modal">
                        <div class="title">Important Update</div>
                        <div class="content">This is a sample center modal message with important information.</div>
                        <div class="footer">
                            <div class="primary-button" onclick="PEBridge.handleAction('accept_action')">Accept</div>
                            <div class="secondary-button" onclick="PEBridge.handleAction('dismiss_action')">Dismiss</div>
                        </div>
                    </div>
                </body>
                </html>
                """,
                displayDuration: 0, // 0 means display until user interaction
                shouldDismissOnTap: false,
                actions: [
                    "accept_action": IAMAction(
                        type: .custom,
                        parameters: ["id": "accept", "action": "accept", "data": "custom_data"]
                    ),
                    "dismiss_action": IAMAction(
                        type: .dismiss,
                        parameters: [:]
                    )
                ],
                startDate: now,
                endDate: futureDate,
                priority: 3,
                audience: nil,
                frequency: IAMFrequency(type: .recurring, interval: 0),
                trigger: IAMTriggerCondition(type: "custom", event: "center_message",
                                             conditions: triggerCondition(field: "type", value: "center"))
            ),
            
            // Bottom Sheet Message
            IAMMessageResponse(
                id: "bottom-sheet-1",
                position: .bottom,
                htmlContent: """
                <!DOCTYPE html>
                <html>
                <head>
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <style>
                        /* Reset defaults and ensure content fits properly */
                        * { margin: 0; padding: 0; box-sizing: border-box; }
                        
                        html, body {
                            width: 100%;
                            height: auto !important;
                            overflow: hidden;
                            background: transparent;
                            margin: 0;
                            padding: 0;
                        }
                        
                        .sheet {
                            background-color: white;
                            padding: 20px;
                            border-top-left-radius: 16px;
                            border-top-right-radius: 16px;
                            box-shadow: 0 -2px 10px rgba(0,0,0,0.1);
                            font-family: -apple-system, system-ui, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
                            width: 100%;
                            display: table; /* Force fit to content */
                        }
                        
                        .handle {
                            width: 40px;
                            height: 4px;
                            background-color: #ddd;
                            border-radius: 2px;
                            margin: 0 auto 15px auto;
                        }
                        
                        .title {
                            font-weight: bold;
                            font-size: 18px;
                            margin-bottom: 10px;
                            color: #333;
                        }
                        
                        .content {
                            font-size: 14px;
                            color: #666;
                            margin-bottom: 15px;
                        }
                        
                        .button {
                            background-color: #FF5722;
                            color: white;
                            padding: 12px;
                            border-radius: 6px;
                            text-align: center;
                            font-weight: bold;
                            cursor: pointer;
                            display: block;
                            width: 100%;
                        }
                    </style>
                    <script>
                        document.addEventListener('DOMContentLoaded', function() {
                            // Immediately reports the exact content height
                            const sheetHeight = document.querySelector('.sheet').offsetHeight;
                            PEBridge.reportHeight(sheetHeight);
                        });
                    </script>
                </head>
                <body>
                    <div class="sheet">
                        <div class="handle"></div>
                        <div class="title">Special Offer</div>
                        <div class="content">This is a sample bottom sheet message with a special offer.</div>
                        <div class="button" onclick="PEBridge.handleAction('offer_action')">Get Offer</div>
                    </div>
                </body>
                </html>
                """,
                displayDuration: 0,
                shouldDismissOnTap: true,
                actions: [
                    "offer_action": IAMAction(
                        type: .openURL,
                        parameters: ["url": "https://pushengage.com/offers"]
                    ),
                    "close_button": IAMAction(
                        type: .dismiss,
                        parameters: [:]
                    )
                ],
                startDate: now,
                endDate: futureDate,
                priority: 2,
                audience: nil,
                frequency: IAMFrequency(type: .recurring, interval: 10),
                trigger: IAMTriggerCondition(type: "custom", event: "bottom_sheet",
                                             conditions: triggerCondition(field: "type", value: "bottom_sheet"))
            ),
            
            // Full Screen Message
            IAMMessageResponse(
                id: "full-screen-1",
                position: .full,
                htmlContent: """
                <!DOCTYPE html>
                <html>
                <head>
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <style>
                        body { margin: 0; padding: 0; font-family: -apple-system, sans-serif; height: 100vh; display: flex; flex-direction: column; }
                        .container { flex: 1; display: flex; flex-direction: column; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; }
                        .close { position: absolute; top: 20px; right: 20px; width: 30px; height: 30px; background-color: rgba(255,255,255,0.2); border-radius: 15px; display: flex; justify-content: center; align-items: center; font-size: 18px; }
                        .content { flex: 1; display: flex; flex-direction: column; justify-content: center; align-items: center; padding: 40px; text-align: center; }
                        .title { font-weight: bold; font-size: 24px; margin-bottom: 20px; }
                        .description { font-size: 16px; margin-bottom: 30px; line-height: 1.4; }
                        .button { background-color: white; color: #667eea; padding: 15px 30px; border-radius: 25px; font-weight: bold; font-size: 16px; }
                    </style>
                    <script>
                        document.addEventListener('DOMContentLoaded', function() {
                            // Report content height
                            const height = document.body.scrollHeight;
                            PEBridge.reportHeight(height);
                        });
                    </script>
                </head>
                <body>
                    <div class="container">
                        <div class="close" onclick="PEBridge.handleAction('close_action')">✕</div>
                        <div class="content">
                            <div class="title">Welcome to Our App</div>
                            <div class="description">This is a sample full-screen message that takes over the entire screen. Perfect for onboarding or important announcements.</div>
                            <div class="button" onclick="PEBridge.handleAction('get_started_action')">Get Started</div>
                        </div>
                    </div>
                </body>
                </html>
                """,
                displayDuration: 2,
                shouldDismissOnTap: false,
                actions: [
                    "get_started_action": IAMAction(
                        type: .custom,
                        parameters: ["id": "onboarding_complete", "action": "onboarding_complete"]
                    ),
                    "close_action": IAMAction(
                        type: .dismiss,
                        parameters: [:]
                    )
                ],
                startDate: now,
                endDate: futureDate,
                priority: 3,
                audience: nil,
                frequency: IAMFrequency(type: .recurring, interval: 0),
                trigger: IAMTriggerCondition(type: "custom", event: "full_screen",
                                             conditions: triggerCondition(field: "type", value: "full_screen"))
            )
        ]
    }
    
    // MARK: - Internal Methods
    
    /// Processes a new message from the server
    /// - Parameter response: The message response from the server
    func processNewMessage(_ response: IAMMessageResponse) {
        guard isEnabled else { return }

        runOnMain { [weak self] in
            guard let self = self else { return }
            do {
                // Save the message
                try self.repository.saveMessage(response)

                // If it's an auto-trigger message, add it to the queue
                if response.trigger.type == "auto" {
                    if let message = try self.repository.fetchMessage(withId: response.id),
                       !self.isDeferred(message),
                       self.rulesEngine.isEligibleForDisplay(message),
                       message.canDisplay() {
                        self.queueManager.addMessage(message)
                    }
                }
            } catch {
                PELogger.error(
                    className: String(describing: IAMController.self),
                    message: "Error processing new message: \(error.localizedDescription)"
                )
            }
        }
    }
    
    /// Processes a new message from the server
    /// - Parameters:
    ///   - response: The message response from the server
    ///   - completion: Completion handler called when processing is done
    func processNewMessage(_ response: IAMMessageResponse, completion: @escaping () -> Void) {
        guard isEnabled else {
            completion()
            return
        }

        runOnMain { [weak self] in
            guard let self = self else {
                completion()
                return
            }
            do {
                // Save the message
                try self.repository.saveMessage(response)

                // If it's an auto-trigger message, add it to the queue
                if response.trigger.type == "auto" {
                    if let message = try self.repository.fetchMessage(withId: response.id),
                       !self.isDeferred(message),
                       self.rulesEngine.isEligibleForDisplay(message),
                       message.canDisplay() {
                        self.queueManager.addMessage(message)
                    }
                }
                completion()
            } catch {
                PELogger.error(
                    className: String(describing: IAMController.self),
                    message: "Error processing new message: \(error.localizedDescription)"
                )
                completion()
            }
        }
    }
    
    /// Processes multiple new messages from the server
    /// - Parameter responses: The message responses from the server
    func processNewMessages(_ responses: [IAMMessageResponse]) {
        for response in responses {
            processNewMessage(response)
        }
    }
    
    /// Processes multiple new messages from the server
    /// - Parameters:
    ///   - responses: The message responses from the server
    ///   - completion: Completion handler called when all processing is done
    func processNewMessages(_ responses: [IAMMessageResponse], completion: @escaping () -> Void) {
        let dispatchGroup = DispatchGroup()
        
        for response in responses {
            dispatchGroup.enter()
            processNewMessage(response) {
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            completion()
        }
    }
    
    // MARK: - Private Methods
    
    /// Sets up observers for app lifecycle events
    private func setupAppLifecycleObservers() {
        // Observe app foreground event
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        // Observe app background event
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    /// Called when the app becomes active
    @objc private func appDidBecomeActive() {
        // Log diagnostics about display records when app becomes active
        PELogger.info(
            className: String(describing: IAMController.self),
            message: "App became active - Display records state:"
        )
        repository.diagnosticDisplayRecordsCheck()

        // Continue any pending app-open delay from the time that was left.
        triggerDelayScheduler.resume()

        if !appOpenHandled {
            appOpenHandled = true
            performAppOpen()
        } else {
            // Later activations: refresh data + analytics, but do NOT re-show auto.
            syncManager.startSync()
        }
    }

    /// App open (once per session): fetch fresh campaigns first, then show
    /// auto-triggers. If the fetch fails, fall back to the campaigns already
    /// stored locally. Auto display no longer happens inside sync (decoupled
    /// in IAMSyncManager.apply) so it fires exactly here, once per session.
    private func performAppOpen() {
        // Stamp the app-open instant BEFORE the sync: trigger.delay counts from
        // here, so sync time is absorbed by the delay instead of added to it.
        appOpenAt = ProcessInfo.processInfo.systemUptime
        PELogger.debug(
            className: String(describing: IAMController.self),
            message: "App open — syncing fresh campaigns before evaluating auto-triggers"
        )
        syncManager.syncMessages { [weak self] error in
            // The reason is on the info line, not only in the error stream: a field
            // report of "IAM shows nothing" is unactionable without it, and reading
            // os_log's %{private} error message needs a profile on a real device. A
            // Cloudflare 403 against the IAM host looked exactly like a bad site key
            // until the error stream was captured. Android already carries the status
            // code in the message it reports (`Metadata fetch failed: HTTP <code>`).
            if let error = error {
                PELogger.debug(
                    className: String(describing: IAMController.self),
                    message: "App-open sync failed — falling back to existing data: "
                        + "\(error.localizedDescription)"
                )
            } else {
                PELogger.debug(
                    className: String(describing: IAMController.self),
                    message: "App-open sync succeeded — showing fresh data"
                )
            }
            // Campaign-store snapshot, once per session — the only way to inspect
            // what synced now that the public getIAMDatabaseState() is gone.
            // Matches Android, which logs the same summary at controller init.
            // Strictly gated: it concatenates every stored campaign's HTML and
            // getDatabaseSummary() must run on main (CoreData context), so it
            // never executes unless the host opted into logging.
            if PELogger.isLoggingEnable {
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    PELogger.debug(
                        className: String(describing: IAMController.self),
                        message: "IAM Database Summary on App Open:\n"
                            + self.getDatabaseSummary()
                    )
                }
            }
            // Audience inputs are refreshed BEFORE evaluating, so segment- and
            // geo-targeted campaigns can match on this same pass rather than
            // waiting for the next launch.
            self?.refreshAudienceInputs {
                DispatchQueue.main.async { self?.processAutoTriggers() }
            }
        }
    }

    /// Refreshes what audience conditions resolve against — the subscriber-backed
    /// snapshot and the notification-authorization state — then runs `completion`
    /// regardless of the outcome.
    ///
    /// Neither failure is fatal: the cached snapshot is used instead, and campaigns
    /// targeting data that has never been fetched are deferred rather than
    /// mis-evaluated.
    func refreshAudienceInputs(completion: @escaping () -> Void) {
        notificationPermissionReader { [weak self] enabled in
            self?.rulesEngine.cacheNotificationPermission(enabled: enabled)
            self?.refreshSubscriberState(completion)
        }
    }

    private func refreshSubscriberState(_ completion: @escaping () -> Void) {
        // Before anything is read: a snapshot taken under a previous subscriber must
        // not answer for this one, and only the fetch would otherwise replace it.
        rulesEngine.invalidateSubscriberStateIfIdentityChanged(subscriberStateProvider.subscriberIdentity)

        guard subscriberStateProvider.hasSubscriber else {
            // No subscriber yet (no device token, or subscribe has not completed).
            // Nothing to fetch; subscriber-backed conditions stay deferred.
            PELogger.debug(
                className: String(describing: IAMController.self),
                message: "IAM: no subscriber yet — skipping subscriber-state fetch"
            )
            completion()
            return
        }

        subscriberStateProvider.fetchSubscriberFields(IAMSubscriberStateMapper.requestedFields) {
            [weak self] rawFields in
            guard let self = self else {
                completion()
                return
            }
            // The fetch completes on a network queue. Hopping here — rather than
            // letting the apply hop on its own — keeps the snapshot in place before
            // `completion` lets auto-trigger evaluation run.
            self.runOnMain {
                if let rawFields = rawFields {
                    let state = IAMSubscriberStateMapper.state(from: rawFields)
                    self.rulesEngine.applySubscriberState(
                        segments: state.segments,
                        attributes: state.attributes,
                        scalars: state.scalars,
                        identity: self.subscriberStateProvider.subscriberIdentity
                    )
                } else {
                    PELogger.error(
                        className: String(describing: IAMController.self),
                        message: "IAM: subscriber-state fetch failed — evaluating against the cached snapshot"
                    )
                }
                completion()
            }
        }
    }

    /// Called when the App ID becomes available (setAppId / setInitialInfo).
    /// Wrappers (React Native, Flutter) configure the SDK from JS/Dart AFTER the
    /// app is already active — the `didBecomeActive` observer registered in init
    /// has already missed its moment and never fires this session, so campaigns
    /// would sync but never display. Run app-open now in that case; when the app
    /// is not active yet (native init during launch), just sync — the observer
    /// performs app-open moments later.
    func handleAppOpenOrSync() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if UIApplication.shared.applicationState == .active {
                if !self.appOpenHandled {
                    self.appOpenHandled = true
                    self.performAppOpen()
                } else {
                    self.syncManager.startSync()
                }
            } else {
                self.syncManager.syncMessages { _ in }
            }
        }
    }

    /// Evaluates all stored auto-trigger campaigns and enqueues the eligible ones.
    /// Called once per session on app open (see `appDidBecomeActive`). Reads the
    /// local store, so it works whether the app-open sync brought fresh data or
    /// fell back to the previously cached campaigns.
    func processAutoTriggers() {
        guard isEnabled else { return }
        guard Thread.isMainThread else {
            runOnMain { [weak self] in self?.processAutoTriggers() }
            return
        }
        do {
            // Batch-added so the highest-priority campaign of the whole set displays
            // first (fetch order is not priority order).
            let eligible = try repository.fetchValidMessages().filter { message in
                message.decodedTrigger?.type == "auto"
                    && !isDeferred(message)
                    && rulesEngine.isEligibleForDisplay(message)
                    && message.canDisplay()
            }
            // App-open path: hold back anything still inside its delay window. The
            // delay is measured from app open, so a slow sync has already eaten into
            // it — a campaign whose window elapsed during the sync queues at once.
            // This is the ONLY path that honours `trigger.delay`; the custom-trigger
            // path ignores it even though the field lives on the shared trigger.
            let now = ProcessInfo.processInfo.systemUptime
            var immediate: [IAMMessage] = []
            for message in eligible {
                let remaining = IAMTriggerDelay.remaining(triggerJSON: message.trigger,
                                                          appOpenAt: appOpenAt,
                                                          now: now)
                if remaining > 0 {
                    triggerDelayScheduler.schedule(messageId: message.id, after: remaining)
                } else {
                    immediate.append(message)
                }
            }

            if !immediate.isEmpty {
                queueManager.addMessages(immediate)
            }
        } catch {
            PELogger.error(
                className: String(describing: IAMController.self),
                message: "Error processing auto-triggers: \(error.localizedDescription)"
            )
        }
    }
    
    /// Called when the app enters background
    @objc private func appDidEnterBackground() {
        // Log diagnostics about display records when app enters background
        PELogger.info(
            className: String(describing: IAMController.self),
            message: "App entering background - Display records state:"
        )
        repository.diagnosticDisplayRecordsCheck()

        // Freeze any pending app-open delay: background time must not count
        // toward it.
        triggerDelayScheduler.pause()

        // Ask for the next out-of-foreground refresh on the way out. Scheduling here
        // rather than at launch means a request is pending precisely when the app is
        // about to stop refreshing on its own, and iOS coalesces repeat submissions of
        // the same identifier so a background/foreground cycle cannot pile them up.
        IAMBackgroundRefresh.shared.scheduleNext()
    }
    
    // MARK: - Selector Methods
    
    /// Processes a message using selector (for pre-iOS 13 compatibility)
    /// - Parameter messageId: The ID of the message to process
    @objc internal func processMessageFromSelector(_ messageId: String) {
        guard isEnabled else { return }

        runOnMain { [weak self] in
            guard let self = self else { return }
            do {
                // Fetch the message
                guard let message = try self.repository.fetchMessage(withId: messageId) else {
                    PELogger.error(
                        className: String(describing: IAMController.self),
                        message: "Could not find message with ID: \(messageId)"
                    )
                    return
                }

                // Check deferral, eligibility and frequency caps
                if !self.isDeferred(message),
                   self.rulesEngine.isEligibleForDisplay(message),
                   message.canDisplay() {
                    self.queueManager.perform(#selector(IAMQueueManager.addMessageFromSelector(_:)),
                                              with: message)
                } else {
                    PELogger.debug(
                        className: String(describing: IAMController.self),
                        message: "Message \(messageId) skipped: not eligible for display or frequency cap reached"
                    )
                }
            } catch {
                PELogger.error(
                    className: String(describing: IAMController.self),
                    message: "Error processing message: \(error.localizedDescription)"
                )
            }
        }
    }
}

// MARK: - Response Models

/// Response model for messages from server
private struct IAMMessagesResponse: Codable {
    let messages: [IAMMessageResponse]
    let error: String?
    let errorCode: Int?
    
    enum CodingKeys: String, CodingKey {
        case messages = "data"
        case error = "error"
        case errorCode = "error_code"
    }
}

// MARK: - Trigger Management

extension IAMController {
    /// Processes a trigger event
    /// - Parameters:
    ///   - name: Name of the trigger
    ///   - parameters: Optional parameters for the trigger
    func processTrigger(_ name: String, parameters: [String: Any]? = nil) {
        // Runs on the main queue: store reads are view-context confined.
        runOnMain { [weak self] in
            guard let self = self, self.isEnabled else { return }

            do {
                let messages = try self.repository.fetchMessages(forTrigger: name)

                // Trigger conditions are matched against the parameters this
                // occurrence carried; the audience is then evaluated against
                // subscriber and device data only. The parameters are never written
                // to the attribute store — that store also holds subscriber
                // attributes, and the previous set-then-remove approach overwrote a
                // same-named attribute and then deleted it outright.
                let matchingMessages = IAMTriggerMatcher.filter(messages: messages, parameters: parameters)

                let eligibleMessages = matchingMessages.filter {
                    !self.isDeferred($0) && self.rulesEngine.isEligibleForDisplay($0)
                }

                self.queueManager.addMessages(eligibleMessages)
            } catch {
                PELogger.error(
                    className: String(describing: IAMController.self),
                    message: "Error processing trigger: \(error.localizedDescription)"
                )
            }
        }
    }
}

