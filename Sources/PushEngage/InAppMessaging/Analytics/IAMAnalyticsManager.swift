import Foundation

/// Manager for in-app messaging analytics
final class IAMAnalyticsManager: IAMNetworkStateObserver {
    // MARK: - Singleton
    
    /// Shared instance
    static let shared = IAMAnalyticsManager()
    
    // MARK: - Properties
    
    /// Repository for data operations
    private let repository: IAMRepository
    
    /// Queue for processing analytics operations
    private let analyticsQueue = DispatchQueue(label: "com.pushengage.iam.analytics", qos: .utility)
    
    /// Maximum batch size for processing analytics events
    private let maxBatchSize = 50
    
    /// Whether analytics is enabled
    private var isEnabled = true
    
    /// Network state manager for monitoring connectivity
    private let networkStateManager: IAMNetworkStateManager
    
    /// Offline queue for handling operations when offline
    private let offlineQueue: IAMOfflineQueue
    
    /// Whether a sync is in progress
    private var isSyncing = false

    /// Uploads pending events through the real sync pipeline (wired by
    /// IAMSyncManager). Events are only deleted there, after a successful
    /// upload — never locally.
    private var uploadHandler: ((@escaping (IAMSyncError?) -> Void) -> Void)?

    // MARK: - Initialization
    
    /// Creates a new analytics manager
    /// - Parameters:
    ///   - repository: Repository for data operations
    ///   - networkStateManager: Network state manager
    ///   - offlineQueue: Offline queue
    init(
        repository: IAMRepository = IAMRepository(),
        networkStateManager: IAMNetworkStateManager = .shared,
        offlineQueue: IAMOfflineQueue = .shared
    ) {
        self.repository = repository
        self.networkStateManager = networkStateManager
        self.offlineQueue = offlineQueue
        
        // Register for network state changes
        networkStateManager.addObserver(self)
    }
    
    // MARK: - Event Tracking
    
    /// Tracks an impression event when a message is presented to the user
    /// - Parameter messageId: ID of the message
    func trackImpression(messageId: String) {
        trackEvent(type: .impression, messageId: messageId)
    }

    /// Records the tap of a button in an in-app message.
    ///
    /// **Every** button tap is a click, including a dismiss button: the backend
    /// derives `Closes` from a click whose `btn_type` is `dismiss`, so skipping
    /// dismiss buttons meant that metric could never be populated. Non-button
    /// dismissals stay unreported by design.
    ///
    /// - Parameters:
    ///   - messageId: campaign id (`campaign_id`)
    ///   - actionId: the actions-map key the HTML invoked (`btn_id`)
    ///   - action: the resolved action, supplying `btn_text` and `btn_type`
    func recordActionTap(messageId: String, actionId: String, action: IAMAction) {
        recordClick(messageId: messageId,
                    actionId: actionId,
                    label: action.label,
                    actionType: action.type.rawValue)
    }

    /// Records a click with its button payload spelled out.
    /// - Parameters:
    ///   - messageId: campaign id (`campaign_id`)
    ///   - actionId: the actions-map key (`btn_id`)
    ///   - label: the action's label (`btn_text`)
    ///   - actionType: the action's lowercase wire value (`btn_type`)
    func recordClick(messageId: String, actionId: String, label: String?, actionType: String?) {
        trackEvent(type: .click,
                   messageId: messageId,
                   btnId: actionId,
                   btnText: label,
                   btnType: actionType)
    }


    
    // MARK: - Batch Processing

    /// Registers the upload pipeline used to flush pending events.
    /// - Parameter handler: Uploads pending events and reports the outcome
    func setUploadHandler(_ handler: @escaping (@escaping (IAMSyncError?) -> Void) -> Void) {
        uploadHandler = handler
    }

    /// Flushes pending analytics events through the upload pipeline
    /// - Parameter completion: Called when processing is complete
    func processPendingEvents(completion: ((Result<Int, Error>) -> Void)? = nil) {
        guard isEnabled else {
            completion?(.success(0))
            return
        }

        // If offline, queue the operation and return
        if !networkStateManager.isConnected {
            offlineQueue.enqueueOperation(IAMSyncOperation(type: .uploadAnalytics, priority: 1))
            completion?(.failure(IAMSyncError.connectionFailed))
            return
        }

        guard let uploadHandler = uploadHandler else {
            completion?(.success(0))
            return
        }

        analyticsQueue.async { [weak self] in
            guard let self = self else { return }

            // Checked and set on the queue that owns the flag. Done on the caller's
            // thread, two callers arriving on different threads both pass it. `sync` is
            // not an option: trackEvent reaches here already on this queue.
            guard !self.isSyncing else {
                DispatchQueue.main.async { completion?(.success(0)) }
                return
            }
            self.isSyncing = true

            let pending = (try? self.repository.fetchUnsyncdAnalyticsEvents(limit: self.maxBatchSize).count) ?? 0

            guard pending > 0 else {
                self.isSyncing = false
                DispatchQueue.main.async { completion?(.success(0)) }
                return
            }

            uploadHandler { error in
                self.analyticsQueue.async {
                    self.isSyncing = false
                    DispatchQueue.main.async {
                        if let error = error {
                            completion?(.failure(error))
                        } else {
                            completion?(.success(pending))
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Tracks an analytics event.
    ///
    /// Persist-first: the event is stored, then uploaded through the pending-events
    /// pipeline — immediately when online, otherwise on reconnect or the next pass.
    /// A tap made offline is therefore queued, not dropped.
    private func trackEvent(type: IAMAnalyticsEventType,
                            messageId: String,
                            btnId: String? = nil,
                            btnText: String? = nil,
                            btnType: String? = nil) {
        guard isEnabled else { return }

        analyticsQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                try self.repository.recordAnalyticsEvent(type: type,
                                                         messageId: messageId,
                                                         btnId: btnId,
                                                         btnText: btnText,
                                                         btnType: btnType)

                // If we have network, try to process events immediately
                if self.networkStateManager.isConnected && !self.isSyncing {
                    self.processPendingEvents()
                }
            } catch {
                PELogger.error(
                    className: String(describing: IAMAnalyticsManager.self),
                    message: "Failed to record analytics event: \(error.localizedDescription)"
                )
            }
        }
    }
    
    // MARK: - IAMNetworkStateObserver
    
    func networkStateDidChange(isConnected: Bool) {
        if isConnected {
            // Process pending events when connection is restored
            processPendingEvents()
        }
    }
} 