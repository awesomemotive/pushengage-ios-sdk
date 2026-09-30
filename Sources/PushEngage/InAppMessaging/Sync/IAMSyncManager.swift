import Foundation

/// Errors that can occur during synchronization
enum IAMSyncError: Error {
    /// Failed to connect to the server
    case connectionFailed
    
    /// Failed to parse the server response
    case invalidResponse
    
    /// The server returned an error
    case serverError(String)
    
    /// The operation timed out
    case timeout
    
    /// An unknown error occurred
    case unknown(Error?)
}

extension IAMSyncError: LocalizedError {

    /// Spelled out because the default `Error` description for an enum with an associated
    /// value is `"The operation couldn't be completed. (PushEngage.IAMSyncError error 1.)"`,
    /// which reaches the log instead of the actual cause. A field report of "IAM shows
    /// nothing" is unactionable without the real reason — a Cloudflare `HTTP 403` against
    /// the IAM host was indistinguishable from a bad site key until the underlying error was
    /// surfaced. `unknown` deliberately forwards its wrapped error's description, which is
    /// where the status code lives.
    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "could not connect to the IAM host"
        case .invalidResponse:
            return "the IAM host returned a response that could not be parsed"
        case .serverError(let detail):
            return "the IAM host returned an error: \(detail)"
        case .timeout:
            return "the IAM request timed out"
        case .unknown(let underlying):
            guard let underlying = underlying else { return "an unknown IAM sync error" }
            return underlying.localizedDescription
        }
    }
}

/// Protocol for conflict resolution
protocol IAMConflictResolver {
    /// Resolves a conflict between local and server data
    /// - Parameters:
    ///   - localData: The local data
    ///   - serverData: The server data
    ///   - completion: Called when the conflict is resolved
    func resolveConflict<T>(localData: T, serverData: T, completion: @escaping (T) -> Void)
}

/// Default conflict resolver that always uses server data
class IAMDefaultConflictResolver: IAMConflictResolver {
    func resolveConflict<T>(localData: T, serverData: T, completion: @escaping (T) -> Void) {
        // Default strategy: server wins
        completion(serverData)
    }
}

/// Manager for synchronizing data between local and server
final class IAMSyncManager: IAMNetworkStateObserver {
    // MARK: - Singleton
    
    /// Shared instance
    static let shared = IAMSyncManager()
    
    // MARK: - Properties
    
    /// The network state manager
    private let networkStateManager: IAMNetworkStateManager
    
    /// The offline queue
    private let offlineQueue: IAMOfflineQueue
    
    /// The conflict resolver
    private let conflictResolver: IAMConflictResolver
    
    /// The analytics manager
    private let analyticsManager: IAMAnalyticsManager
    
    /// The repository for data operations
    private let repository: IAMRepository

    /// The real backend by default; injectable so tests can substitute a fake
    /// (e.g. IAMNetworkServiceMock for deterministic offline content).
    private let networkService: IAMNetworkServiceType

    /// IAM metadata persistence (version/status/hosts/fetch time)
    private let prefs: IAMPrefs

    /// Runtime configuration (site key + environment) pushed in by PEManager
    private let configuration: IAMConfiguration

    /// The sync interval in seconds.
    ///
    /// 6 hours, matching Android's `SYNC_INTERVAL_HOURS = 6` WorkManager job so a
    /// campaign edit reaches both platforms on the same cadence. Note the platforms are
    /// not equivalent beyond the number: this is an in-process `Timer`, so it does not
    /// fire while backgrounded and dies with the process, where Android's job survives
    /// both. In practice iOS refreshes on app open, which is already the dominant path;
    /// true background refresh needs `BGTaskScheduler` and host-app Background Modes,
    /// which is a public-API change rather than a bug fix.
    private let syncInterval: TimeInterval = 21600 // 6 hours (Android parity)

    /// How long after a completed campaign sync a further request is treated as part of
    /// the same burst and answered from what was just fetched. See `syncMessages`.
    private let syncCoalescingWindow: TimeInterval = 10

    /// Guards the campaign-sync coalescing state below. `syncMessages` is reachable from
    /// several queues — the network-state observer, the sync timer, the offline queue and
    /// the controller's main-queue app-open path — so the in-flight flag and its waiting
    /// completions cannot be left unsynchronised.
    private let syncStateLock = NSLock()

    /// True while a campaign fetch is on the wire. Later callers attach rather than
    /// starting a second fetch.
    private var isFetchingCampaigns = false

    /// Completions of callers that arrived while a fetch was in flight; all are answered
    /// with that fetch's outcome.
    private var pendingMessageSyncCompletions: [(IAMSyncError?) -> Void] = []
    
    /// The last sync time for messages
    private var lastMessageSyncTime: Date?
    
    /// The last sync time for analytics
    private var lastAnalyticsSyncTime: Date?
    
    /// The last sync time for triggers
    private var lastTriggerSyncTime: Date?
    
    /// Whether a sync is in progress
    private var isSyncing = false
    
    /// The sync timer
    private var syncTimer: Timer?
    
    // MARK: - Initialization
    
    /// Creates a new sync manager
    /// - Parameters:
    ///   - networkStateManager: The network state manager
    ///   - offlineQueue: The offline queue
    ///   - conflictResolver: The conflict resolver
    ///   - analyticsManager: The analytics manager
    ///   - repository: The repository for data operations
    init(
        networkStateManager: IAMNetworkStateManager = .shared,
        offlineQueue: IAMOfflineQueue = .shared,
        conflictResolver: IAMConflictResolver = IAMDefaultConflictResolver(),
        analyticsManager: IAMAnalyticsManager = .shared,
        repository: IAMRepository = IAMRepository(),
        networkService: IAMNetworkServiceType = IAMNetworkServiceImpl(),
        prefs: IAMPrefs = .shared,
        configuration: IAMConfiguration = .shared
    ) {
        self.networkStateManager = networkStateManager
        self.offlineQueue = offlineQueue
        self.conflictResolver = conflictResolver
        self.analyticsManager = analyticsManager
        self.repository = repository
        self.networkService = networkService
        self.prefs = prefs
        self.configuration = configuration

        // Set up the offline queue
        offlineQueue.setSyncManager(self)

        // Route the analytics manager's flushes through the real uploader
        analyticsManager.setUploadHandler { [weak self] completion in
            guard let self = self else {
                completion(nil)
                return
            }
            self.syncAnalytics(completion: completion)
        }

        // Register for network state changes
        networkStateManager.addObserver(self)
        
        // Set up the sync timer
        setupSyncTimer()
        
        // Load last sync times
        loadLastSyncTimes()
    }
    
    // MARK: - Sync Operations
    
    /// Starts the sync process
    func startSync() {
        guard !isSyncing, networkStateManager.isConnected else {
            // If offline, queue the operations
            if !networkStateManager.isConnected {
                queueSyncOperations()
            }
            return
        }
        
        isSyncing = true
        
        // Sync in order: messages, analytics, triggers
        syncMessages { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                PELogger.error(
                    className: String(describing: IAMSyncManager.self),
                    message: "Failed to sync messages: \(error.localizedDescription)"
                )
            }
            
            self.syncAnalytics { error in
                if let error = error {
                    PELogger.error(
                        className: String(describing: IAMSyncManager.self),
                        message: "Failed to sync analytics: \(error.localizedDescription)"
                    )
                }
                
                self.syncTriggers { error in
                    if let error = error {
                        PELogger.error(
                            className: String(describing: IAMSyncManager.self),
                            message: "Failed to sync triggers: \(error.localizedDescription)"
                        )
                    }
                    
                    self.isSyncing = false
                    self.saveLastSyncTimes()
                }
            }
        }
    }
    
    /// Syncs messages with the server (contract §1–§2): metadata-gated fetch,
    /// full-replace persistence, iam_status purge. Gated on the App ID
    /// (site_key), NOT on a push subscription — in-app messaging must work
    /// even when notification permission was never granted.
    /// - Parameter completion: Called when the sync is complete
    func syncMessages(completion: @escaping (IAMSyncError?) -> Void) {
        guard let siteKey = configuration.siteKey, !siteKey.isEmpty else {
            PELogger.debug(
                className: String(describing: IAMSyncManager.self),
                message: "IAM sync skipped: no App ID configured yet"
            )
            completion(nil)
            return
        }

        // Collapse the app-open burst. Four independent callers legitimately kick a sync
        // around one app open — SDK init with a persisted site key, a wrapper's
        // `setAppId` after the app is already active, the `didBecomeActive` observer, and
        // the network-state observer — and none can simply be removed, because each
        // covers an integration path the others do not. `startSync`'s `isSyncing` flag
        // does not help: two of them reach this method directly rather than through
        // `startSync`. Untreated, a cold launch did four full metadata round trips, and
        // on a first install (no stored version) four campaign downloads and four
        // full-replaces of the whole campaign set. Android does one sync per open.
        //
        // Two guards, because the burst has two shapes:
        //   1. ALREADY IN FLIGHT — the launch case. The four calls overlap, so a
        //      "recently completed" check cannot catch them: none has completed yet.
        //      Later callers attach to the request in flight and are answered from it.
        //   2. JUST COMPLETED — a caller arriving moments after the first finished.
        //      Answered from what was just fetched.
        //
        // A FAILED sync stamps no completion time, so the next caller retries rather
        // than inheriting a failure it could have recovered from.
        syncStateLock.lock()
        if isFetchingCampaigns {
            pendingMessageSyncCompletions.append(completion)
            syncStateLock.unlock()
            PELogger.debug(
                className: String(describing: IAMSyncManager.self),
                message: "IAM sync joined the fetch already in flight"
            )
            return
        }
        if let lastSync = lastMessageSyncTime,
           Date().timeIntervalSince(lastSync) < syncCoalescingWindow {
            syncStateLock.unlock()
            PELogger.debug(
                className: String(describing: IAMSyncManager.self),
                message: "IAM sync coalesced: a sync completed "
                    + String(format: "%.1f", Date().timeIntervalSince(lastSync)) + "s ago"
            )
            completion(nil)
            return
        }
        isFetchingCampaigns = true
        syncStateLock.unlock()

        networkService.syncCampaigns(siteKey: siteKey,
                                     storedVersion: prefs.iamVersion) { [weak self] result in
            guard let self = self else { return }

            let outcome: IAMSyncError?
            switch result {
            case .success(let syncResult):
                self.syncStateLock.lock()
                self.lastMessageSyncTime = Date()
                self.syncStateLock.unlock()
                self.apply(syncResult)
                outcome = nil

            case .failure(let error):
                PELogger.error(
                    className: String(describing: IAMSyncManager.self),
                    message: "Error syncing campaigns: \(error.localizedDescription)"
                )
                outcome = .unknown(error)
            }

            // Release the in-flight slot and hand everyone who joined the same answer.
            self.syncStateLock.lock()
            self.isFetchingCampaigns = false
            let joined = self.pendingMessageSyncCompletions
            self.pendingMessageSyncCompletions.removeAll()
            self.syncStateLock.unlock()

            completion(outcome)
            joined.forEach { $0(outcome) }
        }
    }

    /// Applies a campaign sync outcome (mirrors Android's IAMSyncManager).
    private func apply(_ result: IAMCampaignSyncResult) {
        switch result.status {
        case .active:
            PELogger.debug(
                className: String(describing: IAMSyncManager.self),
                message: "Sync ACTIVE: \(result.campaigns.count) campaigns, version \(result.version ?? "-")"
            )
            do {
                // Full-replace so paused/deleted campaigns are dropped while
                // surviving ones keep their display history.
                try repository.replaceAllMessages(result.campaigns)
            } catch {
                PELogger.error(
                    className: String(describing: IAMSyncManager.self),
                    message: "Full-replace failed: \(error.localizedDescription)"
                )
                return
            }
            if let version = result.version {
                prefs.iamVersion = version
            }
            prefs.iamStatus = IAMNetworkConstants.activeStatus
            // Persist the analytics host (from the metadata api block) for the
            // standalone analytics uploader. The campaigns host is resolved
            // fresh from metadata each sync, so it isn't persisted.
            if let analyticsHost = result.analyticsHost {
                prefs.iamAnalyticsUrl = analyticsHost
            }
            // NOTE: auto-trigger display is intentionally NOT done here. It is
            // decoupled from sync and evaluated once per session on app open
            // (IAMController.processAutoTriggers) so campaigns don't re-show on
            // every foreground/timer sync — only when the app opens.

        case .inactive:
            PELogger.debug(
                className: String(describing: IAMSyncManager.self),
                message: "Sync INACTIVE: purging local campaigns"
            )
            try? repository.replaceAllMessages([])
            prefs.iamStatus = "inactive"

        case .unchanged:
            PELogger.debug(
                className: String(describing: IAMSyncManager.self),
                message: "Sync UNCHANGED: nothing to do"
            )
        }
    }
    
    /// Uploads locally recorded analytics to the backend (contract §2.3):
    /// impressions and clicks only in v1 — other event types stay local and
    /// are cleared once their batch is processed so they never block the
    /// fetch window or grow unboundedly.
    /// - Parameter completion: Called when the sync is complete
    func syncAnalytics(completion: @escaping (IAMSyncError?) -> Void) {
        // Event attributes are read on the main queue (the store's view
        // context is main-queue confined); the upload happens off it.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                completion(nil)
                return
            }
            self.performAnalyticsSync(completion: completion)
        }
    }

    /// True while a batch is on the wire. `performAnalyticsSync` is main-queue
    /// confined, so a plain flag suffices.
    ///
    /// Three callers reach `syncAnalytics` — the analytics manager's upload handler,
    /// the campaign sync and the offline queue — and only the first is covered by the
    /// analytics manager's own flag. Rows are deleted after the upload answers, so
    /// without this an overlapping flush reads and re-sends the very same batch, and
    /// every impression and click in it is counted twice.
    private var isUploadingAnalytics = false

    /// Events the backend has already accepted but whose local rows could not be
    /// deleted. They must never be sent again — a later flush retries the delete only.
    private var uploadedAwaitingDeletion: Set<UUID> = []

    /// Failed attempts an analytics event gets before it is dropped. Only the event a
    /// batch stopped on is charged, once per flush, so this has to clear a busy session
    /// spent against a down backend — dropping on a transient outage would lose events
    /// that would have uploaded fine. High enough for that, low enough that a permanent
    /// failure (revoked site key, wrong host) stops wedging the fetch window forever.
    private static let maxUploadAttempts: Int16 = 25

    private func performAnalyticsSync(completion: @escaping (IAMSyncError?) -> Void) {
        guard !isUploadingAnalytics else {
            // Another flush owns this batch; reporting success keeps the offline queue
            // from re-enqueueing an upload that is already happening.
            completion(nil)
            return
        }

        do {
            let events = try repository.fetchUnsyncdAnalyticsEvents(limit: 100)
            guard !events.isEmpty else {
                lastAnalyticsSyncTime = Date()
                completion(nil)
                return
            }

            // Rows left behind by a delete that failed after a successful upload: the
            // backend has them, so retry the delete and keep them out of the payload.
            let leftovers = events.filter { uploadedAwaitingDeletion.contains($0.id) }
            if !leftovers.isEmpty {
                deleteUploadedEvents(leftovers)
            }

            let unsent = events.filter { !uploadedAwaitingDeletion.contains($0.id) }
            guard !unsent.isEmpty else {
                lastAnalyticsSyncTime = Date()
                completion(nil)
                return
            }

            // Each payload is kept paired with the event it came from: an event type this
            // build cannot put on the wire yields no payload, so positions do not line up.
            let sendable: [(event: IAMAnalyticsEvent, payload: IAMAnalyticsPayload)] =
                unsent.compactMap { event in
                    analyticsPayload(from: event).map { (event, $0) }
                }
            let sendableIds = Set(sendable.map { $0.event.id })
            // Nothing was sent, so these cannot double-count. Cleared so they never
            // block the fetch window or grow unboundedly.
            let unsendable = unsent.filter { !sendableIds.contains($0.id) }

            guard !sendable.isEmpty else {
                try? repository.deleteAnalyticsEvents(unsendable)
                lastAnalyticsSyncTime = Date()
                completion(nil)
                return
            }

            isUploadingAnalytics = true
            networkService.reportAnalytics(payloads: sendable.map { $0.payload }) { [weak self] result in
                guard let self = self else { return }
                // The reply arrives on the network queue; the store's view context is
                // main-queue confined and so is the in-flight flag.
                DispatchQueue.main.async {
                    self.isUploadingAnalytics = false
                    switch result {
                    case .success(let outcome):
                        // Only what the backend accounted for is cleared. Clearing the whole
                        // batch re-POSTed the delivered events on the next flush.
                        let settled = outcome.syncedIndices
                            .filter { sendable.indices.contains($0) }
                            .map { sendable[$0].event }
                        self.deleteUploadedEvents(settled + unsendable)
                        if outcome.allSynced {
                            self.lastAnalyticsSyncTime = Date()
                            completion(nil)
                        } else {
                            // Only the event the batch stopped on reached the wire; the
                            // ones behind it were never attempted, so only it is charged.
                            let settledIndices = Set(outcome.syncedIndices)
                            if let failed = sendable.indices
                                .first(where: { !settledIndices.contains($0) }) {
                                self.chargeFailedUpload(sendable[failed].event)
                            }
                            completion(.unknown(outcome.failure))
                        }
                    case .failure(let error):
                        completion(.unknown(error))
                    }
                }
            }
        } catch {
            completion(.unknown(error))
        }
    }

    /// Deletes events the backend has accepted, remembering any it could not delete so
    /// the next flush retries the delete instead of re-sending them.
    private func chargeFailedUpload(_ event: IAMAnalyticsEvent) {
        do {
            let dropped = try repository.recordFailedUpload(for: [event],
                                                            maxAttempts: Self.maxUploadAttempts)
            if !dropped.isEmpty {
                PELogger.error(
                    className: String(describing: IAMSyncManager.self),
                    message: "Dropping analytics event(s) \(dropped) after "
                        + "\(Self.maxUploadAttempts) failed uploads — the events behind "
                        + "them were blocked from uploading at all"
                )
            }
        } catch {
            PELogger.error(
                className: String(describing: IAMSyncManager.self),
                message: "Could not record a failed analytics upload: \(error.localizedDescription)"
            )
        }
    }

    private func deleteUploadedEvents(_ events: [IAMAnalyticsEvent]) {
        guard !events.isEmpty else { return }
        let ids = events.map { $0.id }
        do {
            try repository.deleteAnalyticsEvents(events)
            uploadedAwaitingDeletion.subtract(ids)
        } catch {
            uploadedAwaitingDeletion.formUnion(ids)
            PELogger.error(
                className: String(describing: IAMSyncManager.self),
                message: "Uploaded analytics could not be cleared (\(error.localizedDescription)) — "
                    + "holding \(ids.count) event(s) back so they are not counted twice"
            )
        }
    }

    /// Maps stored analytics events onto §2.3 payloads.
    ///
    /// The `btn_*` fields are read straight off the event, which recorded them at
    /// tap time. They used to be re-resolved from the stored campaign, which meant a
    /// click that outlived its campaign — the next sync full-replaces the set —
    /// uploaded with no button payload at all. `btn_type` is the lowercase
    /// `actions[].type` wire value, and the backend routes `dismiss` to `close`.
    func analyticsPayloads(from events: [IAMAnalyticsEvent]) -> [IAMAnalyticsPayload] {
        events.compactMap(analyticsPayload(from:))
    }

    /// The §2.3 payload for one stored event, or nil when its type has no wire form.
    func analyticsPayload(from event: IAMAnalyticsEvent) -> IAMAnalyticsPayload? {
        switch event.eventType {
        case IAMAnalyticsEventType.impression.rawValue:
            return IAMAnalyticsPayload(campaignId: event.messageId, impression: 1, click: 0)

        case IAMAnalyticsEventType.click.rawValue:
            return IAMAnalyticsPayload(campaignId: event.messageId,
                                       impression: 0,
                                       click: 1,
                                       btnId: event.btnId,
                                       btnText: event.btnText,
                                       btnType: event.btnType)

        default:
            // An event type this build does not know about is not invented onto
            // the wire; it is dropped, and the batch is still cleared.
            return nil
        }
    }
    
    /// Syncs triggers with the server
    /// - Parameter completion: Called when the sync is complete
    func syncTriggers(completion: @escaping (IAMSyncError?) -> Void) {
        // Check if we need to sync
        guard shouldSyncTriggers() else {
            completion(nil)
            return
        }
        
        // TODO: Implement triggers sync with server
        // For now, just update the last sync time
        lastTriggerSyncTime = Date()
        completion(nil)
    }
    
    /// Forces a sync
    func forceSync() {
        // Reset last sync times
        lastMessageSyncTime = nil
        lastAnalyticsSyncTime = nil
        lastTriggerSyncTime = nil
        
        // Start sync
        startSync()
    }
    
    // MARK: - Private Methods
    
    /// Sets up the sync timer
    private func setupSyncTimer() {
        // Invalidate existing timer
        syncTimer?.invalidate()
        
        // Create a new timer
        syncTimer = Timer.scheduledTimer(
            timeInterval: syncInterval,
            target: self,
            selector: #selector(syncTimerFired),
            userInfo: nil,
            repeats: true
        )
    }
    
    /// Called when the sync timer fires
    @objc private func syncTimerFired() {
        startSync()
    }
    
    /// Queues sync operations
    private func queueSyncOperations() {
        if shouldSyncMessages() {
            offlineQueue.enqueueOperation(IAMSyncOperation(type: .fetchMessages, priority: 0))
        }
        
        if shouldSyncAnalytics() {
            offlineQueue.enqueueOperation(IAMSyncOperation(type: .uploadAnalytics, priority: 1))
        }
        
        if shouldSyncTriggers() {
            offlineQueue.enqueueOperation(IAMSyncOperation(type: .syncTriggers, priority: 2))
        }
    }
    
    // Auto-trigger display used to be re-fired here on every sync. It is now
    // decoupled and evaluated once per session on app open
    // (IAMController.processAutoTriggers), so campaigns show when the app opens
    // rather than on every foreground/timer sync.

    /// Checks if we should sync messages
    /// - Returns: Whether we should sync messages
    private func shouldSyncMessages() -> Bool {
        guard let lastSync = lastMessageSyncTime else {
            return true
        }
        
        return Date().timeIntervalSince(lastSync) >= syncInterval
    }
    
    /// Checks if we should sync analytics
    /// - Returns: Whether we should sync analytics
    private func shouldSyncAnalytics() -> Bool {
        guard let lastSync = lastAnalyticsSyncTime else {
            return true
        }
        
        return Date().timeIntervalSince(lastSync) >= syncInterval
    }
    
    /// Checks if we should sync triggers
    /// - Returns: Whether we should sync triggers
    private func shouldSyncTriggers() -> Bool {
        guard let lastSync = lastTriggerSyncTime else {
            return true
        }
        
        return Date().timeIntervalSince(lastSync) >= syncInterval
    }
    
    /// Loads the last sync times from UserDefaults
    private func loadLastSyncTimes() {
        let defaults = UserDefaults.standard
        
        if let lastMessageSync = defaults.object(forKey: "com.pushengage.iam.lastMessageSyncTime") as? Date {
            lastMessageSyncTime = lastMessageSync
        }
        
        if let lastAnalyticsSync = defaults.object(forKey: "com.pushengage.iam.lastAnalyticsSyncTime") as? Date {
            lastAnalyticsSyncTime = lastAnalyticsSync
        }
        
        if let lastTriggerSync = defaults.object(forKey: "com.pushengage.iam.lastTriggerSyncTime") as? Date {
            lastTriggerSyncTime = lastTriggerSync
        }
    }
    
    /// Saves the last sync times to UserDefaults
    private func saveLastSyncTimes() {
        let defaults = UserDefaults.standard
        
        if let lastMessageSync = lastMessageSyncTime {
            defaults.set(lastMessageSync, forKey: "com.pushengage.iam.lastMessageSyncTime")
        }
        
        if let lastAnalyticsSync = lastAnalyticsSyncTime {
            defaults.set(lastAnalyticsSync, forKey: "com.pushengage.iam.lastAnalyticsSyncTime")
        }
        
        if let lastTriggerSync = lastTriggerSyncTime {
            defaults.set(lastTriggerSync, forKey: "com.pushengage.iam.lastTriggerSyncTime")
        }
    }
    
    // MARK: - IAMNetworkStateObserver
    
    func networkStateDidChange(isConnected: Bool) {
        if isConnected {
            // Start sync when connection is restored
            startSync()
        }
    }
} 
