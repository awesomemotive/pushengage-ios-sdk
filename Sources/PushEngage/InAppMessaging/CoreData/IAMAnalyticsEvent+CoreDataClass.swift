import Foundation
import CoreData

@objc(IAMAnalyticsEvent)
class IAMAnalyticsEvent: NSManagedObject {

    // MARK: - Convenience Methods

    /// Creates a new analytics event
    /// - Parameters:
    ///   - type: The type of analytics event
    ///   - messageId: The ID of the message associated with the event
    ///   - btnId: The actions-map key the HTML invoked (`btn_id`); clicks only
    ///   - btnText: The action's label (`btn_text`); clicks only
    ///   - btnType: The action's wire value, e.g. `open_url` (`btn_type`); clicks only
    ///   - context: The managed object context to create the event in
    /// - Returns: A new IAMAnalyticsEvent instance
    static func create(type: IAMAnalyticsEventType,
                       messageId: String,
                       btnId: String? = nil,
                       btnText: String? = nil,
                       btnType: String? = nil,
                       in context: NSManagedObjectContext) throws -> IAMAnalyticsEvent {
        let event = IAMAnalyticsEvent(context: context)
        event.id = UUID()
        event.eventType = type.rawValue
        event.messageId = messageId
        event.eventDate = Date()
        event.btnId = btnId
        event.btnText = btnText
        event.btnType = btnType
        return event
    }
}
