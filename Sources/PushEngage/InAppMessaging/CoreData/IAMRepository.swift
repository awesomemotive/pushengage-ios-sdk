import Foundation
import CoreData

/// Repository class for handling In-App Messaging data operations
final class IAMRepository {
    
    // MARK: - Properties
    
    private let coreDataManager: IAMCoreDataManager
    
    // MARK: - Initialization
    
    init(coreDataManager: IAMCoreDataManager = .shared) {
        self.coreDataManager = coreDataManager
    }
    
    // MARK: - Message Operations
    
    /// Saves a message from a server response
    /// - Parameter response: The message response from the server
    func saveMessage(_ response: IAMMessageResponse) throws {
        try coreDataManager.performBackgroundTask { context in
            _ = try IAMMessage.create(from: response, in: context)
            PELogger.debug(
                className: String(describing: IAMRepository.self),
                message: "Saved/updated message with ID: \(response.id)"
            )
        }
    }
    
    /// Saves multiple messages from server responses
    /// - Parameter responses: Array of message responses from the server
    func saveMessages(_ responses: [IAMMessageResponse]) throws {
        // Skip if empty to avoid unnecessary Core Data operations
        guard !responses.isEmpty else {
            PELogger.debug(
                className: String(describing: IAMRepository.self),
                message: "No messages to save, skipping"
            )
            return
        }
        
        do {
            try coreDataManager.performBackgroundTask { context in
                for response in responses {
                    do {
                        _ = try IAMMessage.create(from: response, in: context)
                        PELogger.debug(
                            className: String(describing: IAMRepository.self),
                            message: "Saved/updated message with ID: \(response.id)"
                        )
                    } catch {
                        // Log error but continue with other messages
                        PELogger.error(
                            className: String(describing: IAMRepository.self),
                            message: "Failed to save message \(response.id): \(error.localizedDescription)"
                        )
                    }
                }
            }
        } catch {
            PELogger.error(
                className: String(describing: IAMRepository.self),
                message: "Core Data operation failed: \(error.localizedDescription). Will retry later."
            )
            
            // Re-throw the error to notify caller
            throw error
        }
    }
    
    /// Full-replace of the local campaign set (backend contract §2.2):
    /// campaigns absent from `responses` are deleted, the rest are upserted in
    /// place so surviving campaigns keep their display/analytics history and
    /// frequency-capping state. An empty list purges all campaigns (used when
    /// iam_status is not active).
    func replaceAllMessages(_ responses: [IAMMessageResponse]) throws {
        try coreDataManager.performBackgroundTask { context in
            let idsToKeep = responses.map { $0.id }

            let request = NSFetchRequest<IAMMessage>(entityName: "IAMMessage")
            if !idsToKeep.isEmpty {
                request.predicate = NSPredicate(format: "NOT (id IN %@)", idsToKeep)
            }
            for message in try context.fetch(request) {
                context.delete(message)
            }

            // Upsert the survivors/new campaigns (create(from:in:) updates in
            // place when the id already exists).
            for response in responses {
                _ = try IAMMessage.create(from: response, in: context)
            }

            PELogger.debug(
                className: String(describing: IAMRepository.self),
                message: "Full-replace complete: kept/updated \(idsToKeep.count) campaigns"
            )
        }
    }

    /// Fetches every stored campaign (including expired ones) sorted by
    /// priority — used by the debug database summary.
    func fetchAllMessages() throws -> [IAMMessage] {
        let request = IAMMessage.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "priority", ascending: true)]
        return try coreDataManager.executeFetchRequest(request)
    }

    /// Number of analytics events not yet uploaded (every stored event is
    /// pending on iOS — uploaded events are deleted).
    func unsyncedAnalyticsEventCount() throws -> Int {
        try coreDataManager.executeFetchRequest(IAMAnalyticsEvent.fetchRequest()).count
    }

    /// Fetches all valid messages sorted by priority
    /// - Returns: Array of valid messages
    func fetchValidMessages() throws -> [IAMMessage] {
        let request = IAMMessage.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "priority", ascending: true)]
        let messages = try coreDataManager.executeFetchRequest(request)
        return messages.filter { $0.isValid }
    }
    
    /// Fetches messages for a specific trigger
    /// - Parameter triggerName: Name of the trigger
    /// - Returns: Array of valid messages for the trigger
    func fetchMessages(forTrigger triggerName: String) throws -> [IAMMessage] {
        let messages = try fetchValidMessages()
        return messages.filter { message in
            guard let trigger = message.decodedTrigger else { return false }
            return trigger.event == triggerName
        }
    }
    
    /// Fetches a message by its ID
    /// - Parameter id: The ID of the message to fetch
    /// - Returns: The message, or nil if not found
    func fetchMessage(withId id: String) throws -> IAMMessage? {
        let request = IAMMessage.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try coreDataManager.executeFetchRequest(request).first
    }
    
    /// Records a message display
    /// - Parameter message: The message that was displayed
    func recordDisplay(for message: IAMMessage) throws {
        try coreDataManager.performBackgroundTask { context in
            // Fetch fresh copy of the message in this context
            guard let messageInContext = try? context.existingObject(with: message.objectID) as? IAMMessage else {
                PELogger.error(
                    className: String(describing: IAMRepository.self),
                    message: "Failed to find message with ID: \(message.id) in context"
                )
                return
            }
            
            _ = IAMDisplayRecord.create(for: messageInContext, in: context)
            
            PELogger.debug(
                className: String(describing: IAMRepository.self),
                message: "Created display record for message ID: \(message.id), total records: \(messageInContext.displayRecords?.count ?? 0)"
            )
            
            // Make sure we save the context
            try context.save()
        }
    }
    
    /// Deletes expired messages
    func deleteExpiredMessages() throws {
        try coreDataManager.performBackgroundTask { context in
            let request = IAMMessage.fetchRequest()
            request.predicate = NSPredicate(format: "endDate < %@", Date() as NSDate)
            let messages = try context.fetch(request)
            messages.forEach { context.delete($0) }
        }
    }
    
    // MARK: - Analytics Operations
    
    /// Records an analytics event
    /// - Parameters:
    ///   - type: Type of the analytics event
    ///   - messageId: ID of the associated message
    ///   - btnId: Actions-map key of the tapped button (`btn_id`); clicks only
    ///   - btnText: The action's label (`btn_text`); clicks only
    ///   - btnType: The action's wire value (`btn_type`); clicks only
    func recordAnalyticsEvent(type: IAMAnalyticsEventType,
                              messageId: String,
                              btnId: String? = nil,
                              btnText: String? = nil,
                              btnType: String? = nil) throws {
        try coreDataManager.performBackgroundTask { context in
            _ = try IAMAnalyticsEvent.create(type: type,
                                             messageId: messageId,
                                             btnId: btnId,
                                             btnText: btnText,
                                             btnType: btnType,
                                             in: context)
        }
    }
    
    /// Fetches analytics events that haven't been synced
    /// - Parameter limit: Maximum number of events to fetch
    /// - Returns: Array of analytics events
    func fetchUnsyncdAnalyticsEvents(limit: Int = 100) throws -> [IAMAnalyticsEvent] {
        let request = IAMAnalyticsEvent.fetchRequest()
        request.fetchLimit = limit
        request.sortDescriptors = [NSSortDescriptor(key: "eventDate", ascending: true)]
        return try coreDataManager.executeFetchRequest(request)
    }
    
    /// Records a failed upload attempt against an event, deleting it once it has
    /// exhausted `maxAttempts`.
    /// - Returns: The ids that were dropped for exhausting their attempts.
    @discardableResult
    func recordFailedUpload(for events: [IAMAnalyticsEvent], maxAttempts: Int16) throws -> [UUID] {
        guard !events.isEmpty else { return [] }
        var dropped: [UUID] = []
        try coreDataManager.performBackgroundTask { context in
            for event in events {
                guard let eventInContext = try? context.existingObject(with: event.objectID)
                        as? IAMAnalyticsEvent else {
                    continue
                }
                eventInContext.uploadAttempts += 1
                if eventInContext.uploadAttempts >= maxAttempts {
                    dropped.append(eventInContext.id)
                    context.delete(eventInContext)
                }
            }
        }
        return dropped
    }

    /// Deletes analytics events
    /// - Parameter events: Events to delete
    func deleteAnalyticsEvents(_ events: [IAMAnalyticsEvent]) throws {
        try coreDataManager.performBackgroundTask { context in
            for event in events {
                guard let eventInContext = try? context.existingObject(with: event.objectID) as? IAMAnalyticsEvent else {
                    continue
                }
                context.delete(eventInContext)
            }
        }
    }
    
    // MARK: - Diagnostics
    
    /// Diagnostics: Count all display records in the database
    func diagnosticDisplayRecordsCheck() {
        do {
            let request = IAMDisplayRecord.fetchRequest()
            let allRecords = try coreDataManager.executeFetchRequest(request)
            
            PELogger.info(
                className: String(describing: IAMRepository.self),
                message: "Total display records in database: \(allRecords.count)"
            )
            
            // Check each message's display records
            let messageRequest = IAMMessage.fetchRequest()
            let messages = try coreDataManager.executeFetchRequest(messageRequest)
            
            for message in messages {
                let displayCount = message.displayRecords?.count ?? 0
                
                PELogger.info(
                    className: String(describing: IAMRepository.self),
                    message: "Message \(message.id) has \(displayCount) display records"
                )
            }
        } catch {
            PELogger.error(
                className: String(describing: IAMRepository.self),
                message: "Failed to check display records: \(error.localizedDescription)"
            )
        }
    }
}