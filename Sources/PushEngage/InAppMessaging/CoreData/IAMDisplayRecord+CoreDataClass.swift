import Foundation
import CoreData

@objc(IAMDisplayRecord)
class IAMDisplayRecord: NSManagedObject {
    
    // MARK: - Convenience Methods
    
    /// Creates a new display record for a message
    /// - Parameters:
    ///   - message: The message that was displayed
    ///   - context: The managed object context to create the record in
    /// - Returns: A new IAMDisplayRecord instance
    static func create(for message: IAMMessage, in context: NSManagedObjectContext) -> IAMDisplayRecord {
        let record = IAMDisplayRecord(context: context)
        record.id = UUID()
        record.displayDate = Date()
        record.message = message
        record.messageId = message.id
        return record
    }
} 