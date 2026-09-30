import Foundation
import CoreData

extension IAMMessage {
    @nonobjc class func fetchRequest() -> NSFetchRequest<IAMMessage> {
        return NSFetchRequest<IAMMessage>(entityName: "IAMMessage")
    }

    @NSManaged var actions: Data?
    @NSManaged var audience: Data?
    @NSManaged var displayDuration: Int64
    @NSManaged var endDate: Date?
    @NSManaged var frequency: Data?
    @NSManaged var htmlContent: String?
    @NSManaged var id: String
    @NSManaged var position: String
    @NSManaged var priority: Int16
    @NSManaged var shouldDismissOnTap: Bool
    @NSManaged var startDate: Date?
    @NSManaged var trigger: Data?
    @NSManaged var displayRecords: NSSet?
} 