import Foundation

/// Manages the state of messages in the queue
final class IAMQueueStateManager {
    
    // MARK: - Message States
    
    /// Represents the state of a message in the queue
    enum MessageState {
        /// Message is queued but not yet ready for display
        case queued
        /// Message is ready for display
        case ready
        /// Message is currently being displayed
        case displaying
        /// Message has been dismissed
        case dismissed
        /// Message has expired
        case expired
    }
    
    // MARK: - Singleton
    
    /// Shared instance of the queue state manager
    static let shared = IAMQueueStateManager()
    
    // MARK: - Properties
    
    /// Dictionary mapping message IDs to their states
    private var messageStates: [String: MessageState] = [:]
    
    /// Dictionary mapping message IDs to their display timestamps
    private var displayTimestamps: [String: Date] = [:]
    
    /// Dictionary mapping message IDs to their dismiss timestamps
    private var dismissTimestamps: [String: Date] = [:]
    
    // MARK: - Initialization
    
    /// Private initializer for singleton
    private init() {}
    
    // MARK: - State Management
    
    /// Updates the state of a message
    /// - Parameters:
    ///   - messageId: The ID of the message
    ///   - state: The new state
    func updateState(for messageId: String, to state: MessageState) {
        messageStates[messageId] = state
        
        // Update timestamps based on state
        switch state {
        case .displaying:
            displayTimestamps[messageId] = Date()

        case .dismissed:
            dismissTimestamps[messageId] = Date()

        case .expired:
            // Clean up state for expired messages
            displayTimestamps.removeValue(forKey: messageId)
            dismissTimestamps.removeValue(forKey: messageId)

        default:
            break
        }
    }
    
    /// Gets the current state of a message
    /// - Parameter messageId: The ID of the message
    /// - Returns: The current state, or .queued if not found
    func getState(for messageId: String) -> MessageState {
        return messageStates[messageId] ?? .queued
    }
    
    /// Checks if a message is currently being displayed
    /// - Parameter messageId: The ID of the message
    /// - Returns: True if the message is being displayed
    func isDisplaying(_ messageId: String) -> Bool {
        return messageStates[messageId] == .displaying
    }
    
    // MARK: - Display History
    
    /// Gets the time a message was last displayed
    /// - Parameter messageId: The ID of the message
    /// - Returns: The display time, or nil if not found
    func getLastDisplayTime(for messageId: String) -> Date? {
        return displayTimestamps[messageId]
    }
    
    /// Gets the time a message was last dismissed
    /// - Parameter messageId: The ID of the message
    /// - Returns: The dismiss time, or nil if not found
    func getLastDismissTime(for messageId: String) -> Date? {
        return dismissTimestamps[messageId]
    }
    
    /// Gets the display duration for a message
    /// - Parameter messageId: The ID of the message
    /// - Returns: The display duration in seconds, or nil if not found
    func getDisplayDuration(for messageId: String) -> TimeInterval? {
        guard let displayTime = displayTimestamps[messageId],
              let dismissTime = dismissTimestamps[messageId] else {
            return nil
        }
        
        return dismissTime.timeIntervalSince(displayTime)
    }
    
    // MARK: - Cleanup
    
    /// Clears all state data
    func clearAllStates() {
        messageStates.removeAll()
        displayTimestamps.removeAll()
        dismissTimestamps.removeAll()
    }
    
    /// Clears state data for a message
    /// - Parameter messageId: The ID of the message
    func clearState(for messageId: String) {
        messageStates.removeValue(forKey: messageId)
        displayTimestamps.removeValue(forKey: messageId)
        dismissTimestamps.removeValue(forKey: messageId)
    }
} 