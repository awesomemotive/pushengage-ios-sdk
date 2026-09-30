import Foundation

/// Represents an operation that can be queued for offline execution
struct IAMSyncOperation: Codable {
    /// Types of sync operations
    enum OperationType: String, Codable {
        case fetchMessages
        case uploadAnalytics
        case syncTriggers
    }
    
    /// The type of operation
    let type: OperationType
    
    /// The timestamp when the operation was created
    let timestamp: Date
    
    /// The priority of the operation (lower value means higher priority)
    let priority: Int
    
    /// Additional parameters for the operation
    let parameters: [String: String]?
    
    /// The number of times the operation has been retried
    var retryCount: Int
    
    /// Creates a new sync operation
    /// - Parameters:
    ///   - type: The type of operation
    ///   - priority: The priority of the operation
    ///   - parameters: Additional parameters for the operation
    init(type: OperationType, priority: Int = 0, parameters: [String: String]? = nil) {
        self.type = type
        self.timestamp = Date()
        self.priority = priority
        self.parameters = parameters
        self.retryCount = 0
    }
}

/// Manager for handling offline operations
final class IAMOfflineQueue: IAMNetworkStateObserver {
    // MARK: - Singleton
    
    /// Shared instance
    static let shared = IAMOfflineQueue()
    
    // MARK: - Properties
    
    /// The queue of operations
    private var operations: [IAMSyncOperation] = []
    
    /// The key used to store operations in UserDefaults
    private let storageKey = "com.pushengage.iam.offlineQueue"
    
    /// Serialises `operations`, `isProcessing` and `isPaused`. They are reached from the
    /// main thread (reachability listener, enqueue paths) and from a URLSession
    /// completion thread (the processQueue continuation).
    private let stateQueue = DispatchQueue(label: "com.pushengage.iam.offlineQueue.state")

    /// The maximum number of retries for an operation
    private let maxRetries = 3
    
    /// Whether the queue is currently processing
    private var isProcessing = false
    
    /// Whether the queue is paused
    private var isPaused = false
    
    /// The network state manager
    private let networkStateManager: IAMNetworkStateManager
    
    /// The sync manager
    private weak var syncManager: IAMSyncManager?
    
    // MARK: - Initialization
    
    /// Creates a new offline queue
    /// - Parameter networkStateManager: The network state manager
    private init(networkStateManager: IAMNetworkStateManager = .shared) {
        self.networkStateManager = networkStateManager
        
        // Load saved operations
        stateQueue.sync { loadOperationsLocked() }
        
        // Register for network state changes
        networkStateManager.addObserver(self)
    }
    
    // MARK: - Queue Operations
    
    /// Sets the sync manager
    /// - Parameter syncManager: The sync manager
    func setSyncManager(_ syncManager: IAMSyncManager) {
        self.syncManager = syncManager
    }
    
    /// Enqueues an operation
    /// - Parameter operation: The operation to enqueue
    func enqueueOperation(_ operation: IAMSyncOperation) {
        let isRunnable: Bool = stateQueue.sync {
            // Check if a similar operation already exists
            if let index = operations.firstIndex(where: { $0.type == operation.type }) {
                // Replace the existing operation, carrying the larger retry count over:
                // taking the incoming one wholesale let a fresh enqueue reset the budget
                // between retries, so maxRetries stopped bounding anything.
                var merged = operation
                merged.retryCount = max(operations[index].retryCount, operation.retryCount)
                operations[index] = merged
            } else {
                // Insert the operation based on priority
                let index = operations.firstIndex { $0.priority > operation.priority } ?? operations.endIndex
                operations.insert(operation, at: index)
            }

            // Save operations
            saveOperationsLocked()
            return !isPaused
        }

        // Kicked outside the lock: processQueue takes it again.
        if isRunnable && networkStateManager.isConnected {
            processQueue()
        }
    }
    
    /// Dequeues the next operation
    /// - Returns: The next operation, or nil if the queue is empty
    func dequeueNextOperation() -> IAMSyncOperation? {
        stateQueue.sync { () -> IAMSyncOperation? in
            guard !operations.isEmpty else { return nil }
            return operations.removeFirst()
        }
    }
    
    /// Processes the queue
    func processQueue() {
        guard networkStateManager.isConnected else { return }

        // Claiming the queue and taking the next operation is one step: split in two, a
        // second caller passes the isProcessing check before the first has set it.
        let claimed: IAMSyncOperation? = stateQueue.sync { () -> IAMSyncOperation? in
            guard !isProcessing, !isPaused, !operations.isEmpty else { return nil }
            isProcessing = true
            return operations.removeFirst()
        }

        guard let operation = claimed else { return }

        // Process the operation
        processOperation(operation) { [weak self] success in
            guard let self = self else { return }
            
            if !success && operation.retryCount < self.maxRetries {
                // Retry the operation with exponential backoff
                var retriedOperation = operation
                retriedOperation.retryCount += 1
                
                // Calculate delay with exponential backoff
                let delay = pow(2.0, Double(retriedOperation.retryCount)) * 0.5
                
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.enqueueOperation(retriedOperation)
                }
            }
            
            self.stateQueue.sync {
                // Save operations
                self.saveOperationsLocked()
                self.isProcessing = false
            }

            // Continue processing
            self.processQueue()
        }
    }
    
    /// Pauses the queue
    func pauseQueue() {
        stateQueue.sync { isPaused = true }
    }
    
    /// Resumes the queue
    func resumeQueue() {
        stateQueue.sync { isPaused = false }
        processQueue()
    }
    
    /// Clears the queue
    func clearQueue() {
        stateQueue.sync {
            operations.removeAll()
            saveOperationsLocked()
        }
    }
    
    // MARK: - Private Methods
    
    /// Processes an operation
    /// - Parameters:
    ///   - operation: The operation to process
    ///   - completion: Called when the operation is complete
    private func processOperation(_ operation: IAMSyncOperation, completion: @escaping (Bool) -> Void) {
        guard let syncManager = syncManager else {
            completion(false)
            return
        }
        
        switch operation.type {
        case .fetchMessages:
            syncManager.syncMessages { error in
                completion(error == nil)
            }
        case .uploadAnalytics:
            syncManager.syncAnalytics { error in
                completion(error == nil)
            }
        case .syncTriggers:
            syncManager.syncTriggers { error in
                completion(error == nil)
            }
        }
    }
    
    /// Loads operations from UserDefaults. Callers must hold `stateQueue`.
    private func loadOperationsLocked() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }
        
        do {
            operations = try JSONDecoder().decode([IAMSyncOperation].self, from: data)
        } catch {
            PELogger.error(
                className: String(describing: IAMOfflineQueue.self),
                message: "Failed to load operations: \(error.localizedDescription)"
            )
        }
    }
    
    /// Saves operations to UserDefaults. Callers must hold `stateQueue`.
    private func saveOperationsLocked() {
        do {
            let data = try JSONEncoder().encode(operations)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            PELogger.error(
                className: String(describing: IAMOfflineQueue.self),
                message: "Failed to save operations: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - IAMNetworkStateObserver
    
    func networkStateDidChange(isConnected: Bool) {
        guard isConnected else { return }
        processQueue()
    }
} 