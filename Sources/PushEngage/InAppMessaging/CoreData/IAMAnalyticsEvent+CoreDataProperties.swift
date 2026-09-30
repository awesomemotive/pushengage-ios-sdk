import Foundation
import CoreData

extension IAMAnalyticsEvent {
    @nonobjc class func fetchRequest() -> NSFetchRequest<IAMAnalyticsEvent> {
        return NSFetchRequest<IAMAnalyticsEvent>(entityName: "IAMAnalyticsEvent")
    }

    @NSManaged var eventDate: Date
    @NSManaged var eventType: String
    @NSManaged var id: UUID
    @NSManaged var messageId: String

    /// Upload attempts that ended in a non-2xx the event could not be dropped for.
    /// Bounds the head-of-line block: without it a persistently failing endpoint
    /// (a revoked site key, a wrong host) keeps the oldest event at the front of
    /// every fetch window forever and nothing behind it ever uploads.
    @NSManaged var uploadAttempts: Int16

    /// The button that was tapped, reported verbatim as the analytics `btn_*`
    /// fields. Typed columns rather than a JSON blob: the shape is fixed, so a blob
    /// only added a serialize/parse round-trip and a malformed-JSON path. Storing
    /// them also means a click still uploads correctly when the campaign it came
    /// from was replaced by a sync in the meantime.
    @NSManaged var btnId: String?
    @NSManaged var btnText: String?
    @NSManaged var btnType: String?
}
