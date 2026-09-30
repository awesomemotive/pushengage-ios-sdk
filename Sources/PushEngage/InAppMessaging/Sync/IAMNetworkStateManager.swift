import Foundation

/// Protocol for objects that want to be notified of network state changes
protocol IAMNetworkStateObserver: AnyObject {
    /// Called when the network state changes
    /// - Parameter isConnected: Whether the device is connected to the internet
    func networkStateDidChange(isConnected: Bool)
}

/// Manager for monitoring network connectivity for in-app messaging
final class IAMNetworkStateManager {
    // MARK: - Singleton
    
    /// Shared instance
    static let shared = IAMNetworkStateManager()
    
    // MARK: - Properties
    
    /// The underlying reachability manager
    private let reachabilityManager: NetworkReachabilityManager?
    
    /// Observers of network state changes
    private var observers = NSHashTable<AnyObject>.weakObjects()
    
    /// Whether the device is currently connected to the internet
    private(set) var isConnected: Bool = false
    
    /// The current connection type
    private(set) var connectionType: NetworkReachabilityManager.ConnectionType?
    
    // MARK: - Initialization
    
    /// Creates a new network state manager
    private init() {
        self.reachabilityManager = NetworkReachabilityManager()
        setupReachabilityObserver()
    }
    
    // MARK: - Observer Management
    
    /// Adds an observer for network state changes
    /// - Parameter observer: The observer to add
    func addObserver(_ observer: IAMNetworkStateObserver) {
        observers.add(observer)
        
        // Notify the new observer of the current state
        observer.networkStateDidChange(isConnected: isConnected)
    }
    
    /// Removes an observer for network state changes
    /// - Parameter observer: The observer to remove
    func removeObserver(_ observer: IAMNetworkStateObserver) {
        observers.remove(observer)
    }
    
    // MARK: - Private Methods
    
    /// Sets up the reachability observer
    private func setupReachabilityObserver() {
        reachabilityManager?.listener = { [weak self] status in
            guard let self = self else { return }
            
            switch status {
            case .reachable(let connectionType):
                self.isConnected = true
                self.connectionType = connectionType
            case .notReachable, .unknown:
                self.isConnected = false
                self.connectionType = nil
            }
            
            self.notifyObservers()
        }
        
        // Start listening for network changes
        _ = reachabilityManager?.startListening()
        
        // Set initial state
        if let reachabilityManager = reachabilityManager {
            isConnected = reachabilityManager.isReachable
            
            if reachabilityManager.isReachableOnEthernetOrWiFi {
                connectionType = .ethernetOrWiFi
            } else if reachabilityManager.isReachableOnWWAN {
                connectionType = .wwan
            }
        }
    }
    
    /// Notifies all observers of the current network state
    private func notifyObservers() {
        for observer in observers.allObjects {
            if let observer = observer as? IAMNetworkStateObserver {
                observer.networkStateDidChange(isConnected: isConnected)
            }
        }
    }
    
    // MARK: - Deinitializer
    
    deinit {
        reachabilityManager?.stopListening()
    }
} 