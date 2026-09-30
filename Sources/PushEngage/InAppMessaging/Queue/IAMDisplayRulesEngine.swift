import Foundation
import UIKit

/// Engine for evaluating display rules for in-app messages
final class IAMDisplayRulesEngine {

    // MARK: - Singleton

    /// Shared instance of the display rules engine
    static let shared = IAMDisplayRulesEngine()

    // MARK: - Properties

    /// Repository for data operations
    private let repository: IAMRepository

    /// Values audience conditions resolve against
    private let deviceProperties: IAMDeviceProperties

    // MARK: - Initialization

    init(repository: IAMRepository = IAMRepository(),
         userDefaults: UserDefaults = .standard) {
        self.repository = repository
        self.deviceProperties = IAMDeviceProperties(userDefaults: userDefaults)
    }

    // MARK: - Rule Evaluation

    /// Evaluates if a message is eligible for display based on all rules.
    ///
    /// Audience conditions resolve against **subscriber and device data only**.
    /// Trigger parameters are deliberately not visible here — they are matched by
    /// the trigger's own conditions, keeping the two vocabularies separate: the
    /// trigger asks "did this happen, with this data?", the audience asks "is
    /// this the right person?".
    ///
    /// - Parameter message: The message to evaluate
    /// - Returns: True if the message is eligible for display
    func isEligibleForDisplay(_ message: IAMMessage) -> Bool {
        // Check if message is valid (not expired)
        guard isMessageValid(message) else {
            log("Message \(message.id) not valid for the current date: "
                + "startDate=\(message.startDate?.description ?? "nil"), "
                + "endDate=\(message.endDate?.description ?? "nil")")
            return false
        }

        // Check frequency cap
        guard checkFrequencyCap(message) else {
            let displayCount = (message.displayRecords as? Set<IAMDisplayRecord>)?.count ?? 0
            let detail: String
            if let frequency = message.decodedFrequency {
                let count = frequency.count.map { "\($0)" } ?? "absent"
                let interval = frequency.interval.map { "\($0)" } ?? "absent"
                detail = "type=\(frequency.type.rawValue), count=\(count), interval=\(interval)"
            } else {
                detail = "unreadable"
            }
            log("Message \(message.id) excluded by frequency cap: "
                + "displayCount=\(displayCount), frequency=\(detail)")
            return false
        }

        // Check audience targeting
        guard matchesAudience(message) else {
            // Shape-agnostic on purpose: audienceFields understands the grouped
            // object and the legacy array alike, so this line cannot claim a valid
            // audience is malformed just because it did not match.
            let fields = IAMConditionEvaluator.audienceFields(message.audience)
            let detail: String
            if let fields = fields {
                detail = fields.isEmpty ? "no criteria" : "fields=\(fields.sorted().joined(separator: ","))"
            } else {
                detail = "unparseable"
            }
            log("Message \(message.id) doesn't match audience criteria: \(detail)")
            return false
        }

        // All rules passed
        log("Message \(message.id) is eligible for display")
        return true
    }

    private func log(_ message: String) {
        PELogger.debug(className: String(describing: IAMDisplayRulesEngine.self), message: message)
    }
    
    // MARK: - Individual Rules
    
    /// Checks if a message is valid based on its date range
    /// - Parameter message: The message to check
    /// - Returns: True if the message is valid
    private func isMessageValid(_ message: IAMMessage) -> Bool {
        let now = Date()
        
        // Check start date
        if let startDate = message.startDate, startDate > now {
            return false
        }
        
        // Check end date
        if let endDate = message.endDate, endDate < now {
            return false
        }
        
        return true
    }
    
    /// Checks if a message passes frequency cap rules
    /// - Parameter message: The message to check
    /// - Returns: True if the message passes frequency cap
    private func checkFrequencyCap(_ message: IAMMessage) -> Bool {
        // Delegate to the message's own frequency check for consistency
        return message.canDisplay()
    }
    
    /// Checks if a message matches audience targeting rules
    /// - Parameter message: The message to check
    /// - Returns: True if the message matches audience targeting
    private func matchesAudience(_ message: IAMMessage) -> Bool {
        guard let audienceData = message.audience, !audienceData.isEmpty else {
            // No audience targeting defined, so it passes
            return true
        }

        return IAMConditionEvaluator.matchesAudience(audienceData,
                                                    context: .audience(deviceProperties),
                                                    messageId: message.id)
    }

    /// Whether `message` targets subscriber-backed data that has not been fetched
    /// yet.
    ///
    /// The caller **defers** such a campaign — skips it for this pass — rather
    /// than evaluating it. Evaluating would be wrong in both directions: a
    /// positive operator fails, so the campaign would never show on a fresh
    /// install; a negative operator passes, so with OR groups a single such
    /// condition would show it to *everyone*.
    func requiresUnavailableSubscriberState(_ message: IAMMessage) -> Bool {
        guard !deviceProperties.hasSubscriberState else { return false }

        // A malformed audience is handled by matchesAudience (which fails closed);
        // there is nothing to defer on.
        guard let fields = IAMConditionEvaluator.audienceFields(message.audience) else {
            return false
        }

        return fields.contains(where: IAMConditionEvaluator.isSubscriberBacked)
    }

    // MARK: - Attributes

    /// Sets a user attribute value
    /// - Parameters:
    ///   - value: The value to set
    ///   - field: The field to set the value for
    func setUserAttribute(_ value: String, for field: String) {
        deviceProperties.setUserAttribute(value, for: field)
    }

    /// Removes a user attribute
    /// - Parameter field: The field to remove
    func removeUserAttribute(for field: String) {
        deviceProperties.removeUserAttribute(for: field)
    }

    /// Caches the subscriber-backed audience data. See `IAMDeviceProperties` for
    /// the layout and why it replaces rather than merges.
    func applySubscriberState(segments: Set<String>,
                              attributes: [String: String],
                              scalars: [String: String],
                              identity: String) {
        deviceProperties.applySubscriberState(segments: segments,
                                              attributes: attributes,
                                              scalars: scalars,
                                              identity: identity)
    }

    /// Discards the cached snapshot when it describes a different subscriber.
    func invalidateSubscriberStateIfIdentityChanged(_ identity: String) {
        deviceProperties.invalidateSubscriberStateIfIdentityChanged(identity)
    }

    /// Records the notification-authorization state, which is only readable
    /// asynchronously and so cannot be resolved during evaluation.
    func cacheNotificationPermission(enabled: Bool) {
        deviceProperties.cacheNotificationPermission(enabled: enabled)
    }


    // MARK: - Time Window Evaluation
    
    /// Checks if the current time is within a specified time window
    /// - Parameter timeWindow: The time window to check
    /// - Returns: True if the current time is within the window
    func isWithinTimeWindow(_ timeWindow: DateInterval?) -> Bool {
        guard let timeWindow = timeWindow else {
            // No time window specified, so it passes
            return true
        }
        
        let now = Date()
        return timeWindow.contains(now)
    }
    
    /// Creates a time window for a specific day part
    /// - Parameters:
    ///   - startHour: The start hour (0-23)
    ///   - startMinute: The start minute (0-59)
    ///   - endHour: The end hour (0-23)
    ///   - endMinute: The end minute (0-59)
    /// - Returns: A date interval representing the time window for today
    func createDayPartTimeWindow(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) -> DateInterval? {
        let calendar = Calendar.current
        let now = Date()
        
        guard let today = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: now),
              let startDate = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: today),
              let endDate = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: today) else {
            return nil
        }
        
        return DateInterval(start: startDate, end: endDate)
    }
} 
