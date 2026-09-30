import Foundation
import CoreData

extension IAMDisplayRecord {
    @nonobjc class func fetchRequest() -> NSFetchRequest<IAMDisplayRecord> {
        return NSFetchRequest<IAMDisplayRecord>(entityName: "IAMDisplayRecord")
    }

    @NSManaged var displayDate: Date
    @NSManaged var id: UUID
    @NSManaged var message: IAMMessage?

    /// The campaign this display belongs to, held independently of the relationship.
    /// Frequency caps are lifetime, so the history has to survive the campaign row: a
    /// full-replace drops any campaign the server stops sending, and the relationship
    /// goes with it. Re-linked by id when the campaign comes back.
    @NSManaged var messageId: String?
} 