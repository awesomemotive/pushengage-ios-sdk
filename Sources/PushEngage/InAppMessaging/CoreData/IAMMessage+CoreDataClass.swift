import Foundation
import CoreData

@objc(IAMMessage)
class IAMMessage: NSManagedObject {
    
    // MARK: - Convenience Methods
    
    /// Creates a new IAMMessage instance from a message response or updates an existing one
    /// - Parameters:
    ///   - response: The message response from the server
    ///   - context: The managed object context to create the message in
    /// - Returns: An IAMMessage instance (either existing or new)
    static func create(from response: IAMMessageResponse, in context: NSManagedObjectContext) throws -> IAMMessage {
        // Check if a message with this ID already exists
        let fetchRequest = NSFetchRequest<IAMMessage>(entityName: "IAMMessage")
        fetchRequest.predicate = NSPredicate(format: "id == %@", response.id)
        fetchRequest.fetchLimit = 1
        
        let existingMessages = try context.fetch(fetchRequest)
        let message = existingMessages.first ?? IAMMessage(context: context)
        
        // Set/update properties
        message.id = response.id

        reattachDisplayHistory(to: message, in: context)
        message.position = response.position.rawValue
        message.htmlContent = response.htmlContent
        message.displayDuration = response.displayDuration
        message.shouldDismissOnTap = response.shouldDismissOnTap
        message.priority = response.priority
        message.startDate = response.startDate
        message.endDate = response.endDate
        
        // Safely encode complex objects to Data
        do {
            // Encode actions
            if let actions = try? JSONEncoder().encode(response.actions) {
                message.actions = actions
            } else {
                PELogger.error(
                    className: String(describing: IAMMessage.self),
                    message: "Failed to encode actions for message \(response.id)"
                )
            }
            
            // Store the audience JSON verbatim: the evaluator is the only thing
            // that interprets its shape, so re-encoding it through a model here
            // would just add a second interpretation free to disagree.
            message.audience = response.audience?.data


            // Assigned unconditionally: this is an upsert, so an omitted frequency
            // has to clear the stored rule. Leaving the old blob would keep a
            // campaign capped after its rule was removed in the dashboard.
            if let frequency = response.frequency {
                if let frequencyData = try? JSONEncoder().encode(frequency) {
                    message.frequency = frequencyData
                } else {
                    PELogger.error(
                        className: String(describing: IAMMessage.self),
                        message: "Failed to encode frequency for message \(response.id)"
                    )
                    message.frequency = nil
                }
            } else {
                message.frequency = nil
            }
            
            // Encode trigger (this is required)
            if let triggerData = try? JSONEncoder().encode(response.trigger) {
                message.trigger = triggerData
            } else {
                PELogger.error(
                    className: String(describing: IAMMessage.self),
                    message: "Failed to encode trigger for message \(response.id)"
                )
                throw IAMError.invalidMessageFormat
            }
        } catch {
            PELogger.error(
                className: String(describing: IAMMessage.self),
                message: "Error encoding data for message \(response.id): \(error.localizedDescription)"
            )
            throw error
        }
        
        return message
    }
    
    /// Decodes the actions dictionary from stored Data
    var decodedActions: [String: IAMAction]? {
        guard let actionsData = actions else { return nil }
        return try? JSONDecoder().decode([String: IAMAction].self, from: actionsData)
    }
    
    /// Re-links display records this campaign left behind, and stamps `messageId` on any
    /// of its records predating that attribute.
    ///
    /// `displayRecords` is Nullify rather than Cascade, so a campaign dropped by a
    /// full-replace leaves its history behind instead of taking it along. Frequency caps
    /// are lifetime: without this, pausing a campaign in the dashboard and resuming it
    /// would show a `one_time` campaign again to someone who already dismissed it.
    private static func reattachDisplayHistory(to message: IAMMessage,
                                               in context: NSManagedObjectContext) {
        let request = IAMDisplayRecord.fetchRequest()
        request.predicate = NSPredicate(format: "messageId == %@ AND message == nil", message.id)
        do {
            for record in try context.fetch(request) {
                record.message = message
            }
        } catch {
            PELogger.error(
                className: String(describing: IAMMessage.self),
                message: "Could not re-link display history for \(message.id): "
                    + "\(error.localizedDescription)"
            )
        }

        // Records written before `messageId` existed carry the relationship only; stamp
        // them so they survive this campaign's next removal.
        for case let record as IAMDisplayRecord in message.displayRecords ?? []
        where record.messageId?.isEmpty ?? true {
            record.messageId = message.id
        }
    }

    /// Decodes the frequency settings from stored Data
    var decodedFrequency: IAMFrequency? {
        guard let frequencyData = frequency else { return nil }
        return try? JSONDecoder().decode(IAMFrequency.self, from: frequencyData)
    }
    
    /// Decodes the trigger condition from stored Data
    var decodedTrigger: IAMTriggerCondition? {
        guard let triggerData = trigger else { return nil }
        return try? JSONDecoder().decode(IAMTriggerCondition.self, from: triggerData)
    }
    
    /// Checks if the message is currently valid based on its date range
    var isValid: Bool {
        let now = Date()
        
        if let startDate = startDate, startDate > now {
            return false
        }
        
        if let endDate = endDate, endDate < now {
            return false
        }
        
        return true
    }
    
    /// Gets the most recent display record for this message
    private func getLastDisplayRecord() -> IAMDisplayRecord? {
        let records = displayRecords as? Set<IAMDisplayRecord> ?? []
        let recordsCount = records.count
        
        PELogger.debug(
            className: String(describing: IAMMessage.self),
            message: "Message \(id) has \(recordsCount) display records"
        )
        
        guard recordsCount > 0 else { return nil }
        
        let sorted = records.sorted(by: { $0.displayDate > $1.displayDate })
        let mostRecent = sorted.first
        
        if let date = mostRecent?.displayDate {
            PELogger.debug(
                className: String(describing: IAMMessage.self),
                message: "Most recent display for message \(id) was at \(date)"
            )
        }
        
        return mostRecent
    }

    /// Checks if the message can be displayed based on its frequency settings
    func canDisplay() -> Bool {
        guard let frequencyData = self.frequency else {
            PELogger.debug(
                className: String(describing: IAMMessage.self),
                message: "Message \(id) has no frequency settings, allowed to display"
            )
            // No frequency cap defined, so it passes
            return true
        }

        guard let frequency = try? JSONDecoder().decode(IAMFrequency.self, from: frequencyData) else {
            // Malformed frequency rule fails closed (flow doc §3.7)
            PELogger.error(
                className: String(describing: IAMMessage.self),
                message: "Message \(id) has malformed frequency settings, not displaying"
            )
            return false
        }

        // Fetch display records directly from the relationship
        let records = displayRecords as? Set<IAMDisplayRecord> ?? []
        let displayCount = records.count

        PELogger.debug(
            className: String(describing: IAMMessage.self),
            message: "Message \(id) frequency check: type=\(frequency.type.rawValue), "
                + "count=\(frequency.count.map(String.init) ?? "absent"), current displays=\(displayCount)"
        )

        switch frequency.type {
        case .oneTime:
            // One-time messages can only be shown once, interval is ignored
            let canShow = displayCount < 1
            if !canShow {
                PELogger.debug(
                    className: String(describing: IAMMessage.self),
                    message: "Message \(id) is one-time and already shown \(displayCount) times"
                )
            }
            return canShow

        case .recurring:
            // Unlimited repeats, gated only on the minimum interval. `count` is
            // deliberately not read — a recurring campaign has no total cap; use
            // `capped` when one is wanted.
            //
            // `interval` is required for this type: absent means the rule cannot be
            // applied, so fail closed. An explicit 0 or negative value is legal and
            // means "no spacing".
            guard let interval = frequency.interval else {
                PELogger.error(
                    className: String(describing: IAMMessage.self),
                    message: "Message \(id): 'recurring' frequency without an interval — "
                        + "cannot honour the spacing, so not eligible"
                )
                return false
            }
            return hasIntervalElapsed(interval)

        case .unknown:
            // Unrecognized frequency type is treated as no cap (forward-compatible,
            // §3.7). The asymmetry is deliberate: an unknown *type* stays lenient,
            // while a malformed rule of a known type fails closed.
            return true

        case .capped:
            // Honour BOTH halves of "up to N times, at most once every X" — the total
            // cap AND the minimum spacing. Enforcing only the count would let all N
            // displays fire back-to-back in one session.
            //
            // `count` is required for this type. A missing one used to mean unlimited,
            // i.e. a campaign asking to be capped became UNLIMITED — failing open in
            // the one place the author explicitly asked for a limit.
            guard let maxCount = frequency.count else {
                PELogger.error(
                    className: String(describing: IAMMessage.self),
                    message: "Message \(id): 'capped' frequency without a count — "
                        + "cannot honour the cap, so not eligible"
                )
                return false
            }
            // The cap is checked first, so a campaign at its limit stays ineligible
            // regardless of spacing.
            if displayCount >= maxCount {
                PELogger.debug(
                    className: String(describing: IAMMessage.self),
                    message: "Message \(id) reached cap: \(displayCount)/\(maxCount)"
                )
                return false
            }
            // `interval` is optional here: absent or non-positive is a pure count cap.
            return hasIntervalElapsed(frequency.interval ?? 0)
        }
    }

    /// Whether enough time has passed since the last display to satisfy a minimum
    /// spacing of `intervalSeconds`.
    ///
    /// A non-positive interval means "no spacing constraint", and a message that has
    /// never been displayed always satisfies the spacing. Extracted so `capped` and
    /// `recurring` share one implementation — the elapsed-time logic previously
    /// existed twice, which is how `capped` came to ignore it entirely.
    private func hasIntervalElapsed(_ intervalSeconds: TimeInterval) -> Bool {
        guard intervalSeconds > 0 else { return true }
        guard let lastDisplay = getLastDisplayRecord() else { return true }

        let elapsed = Date().timeIntervalSince(lastDisplay.displayDate)
        let hasElapsed = elapsed >= intervalSeconds
        if !hasElapsed {
            PELogger.debug(
                className: String(describing: IAMMessage.self),
                message: "Message \(id) interval not met: \(elapsed) < \(intervalSeconds)"
            )
        }
        return hasElapsed
    }
} 