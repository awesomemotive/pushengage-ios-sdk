//
//  PESubscriberFieldsValidator.swift
//  PushEngage
//
//  Validates payloads for `PushEngage.identify(...)` and `PushEngage.logout(...)`.
//  Pure-Swift, no UIKit, no UserDefaults — directly exercisable by plain XCTest
//  without spinning up the SDK. Mirrors Android's `PESubscriberFieldsValidator`
//  and the web SDK validator at
//  pushengage-web-sdk/client/src/api/validators/subscriber.validator.ts.
//

import Foundation

internal enum PESubscriberFieldsValidator {

    /// The 12 keys the PushEngage backend recognizes as predefined subscriber
    /// fields. Anything outside this set is rejected client-side, matching the
    /// web SDK's `validSubscriberFields`.
    static let validSubscriberFields: [String] = [
        "first_name",
        "last_name",
        "email",
        "phone",
        "gender",
        "dob",
        "language",
        "profile_id",
        "country",
        "city",
        "state",
        "zip"
    ]

    /// Default field set wiped when `logout(...)` is called with a `nil` or
    /// empty list — matches the web SDK fallback.
    static let defaultLogoutFields: [String] = [
        "first_name",
        "last_name",
        "email",
        "phone",
        "gender",
        "dob",
        "profile_id"
    ]

    /// Returns `nil` when `fields` is a valid identify payload, else a
    /// human-readable error message.
    static func validateIdentifyPayload(_ fields: [String: Any]?) -> String? {
        guard let fields else {
            return "Payload is required. The payload should be in object format, e.g., {key: value}."
        }
        if fields.isEmpty {
            return "Payload must have at least one key."
        }
        for key in fields.keys {
            if !validSubscriberFields.contains(key) {
                return "Key '\(key)' is not valid. Valid keys are \(formatList(validSubscriberFields))."
            }
        }
        for value in fields.values {
            if !isAllowedValue(value) {
                return "Value must be a string, number, or boolean."
            }
        }
        return nil
    }

    /// Returns `nil` when every name in `fieldNames` is one of the valid
    /// subscriber fields, else a human-readable error message.
    /// Empty list is considered valid — the handler normalizes nil/empty to
    /// `defaultLogoutFields` before calling.
    static func validateLogoutFieldNames(_ fieldNames: [String]) -> String? {
        for name in fieldNames {
            if !validSubscriberFields.contains(name) {
                return "Subscriber field name '\(name)' is not valid. Valid names are \(formatList(validSubscriberFields))."
            }
        }
        return nil
    }

    /// Coerces a numeric `profile_id` to its string form so it travels to the
    /// server in the same shape the web SDK sends — matches
    /// `formatSubscriberFields` in subscriber.api.ts.
    static func formatSubscriberFields(_ fields: [String: Any]) -> [String: Any] {
        guard let profileId = fields["profile_id"], !(profileId is String) else {
            return fields
        }
        // Match Android: coerce any non-String `profile_id` whose Any wraps a Number.
        // CFBoolean carve-out excluded since boolean profile_id makes no
        // semantic sense and the web SDK only coerces numbers.
        if let asNumber = profileId as? NSNumber, !PESubscriberFieldsStringify.isBool(profileId) {
            var result = fields
            result["profile_id"] = PESubscriberFieldsStringify.stringify(number: asNumber)
            return result
        }
        return fields
    }

    // MARK: - Helpers

    private static func isAllowedValue(_ value: Any) -> Bool {
        if value is String { return true }
        if value is Bool { return true }
        if value is NSNumber {
            // NSNumber covers Int/Double/Float bridged from Any.
            return true
        }
        return false
    }

    private static func formatList(_ values: [String]) -> String {
        if values.isEmpty { return "" }
        if values.count == 1 { return values[0] }
        let head = values.dropLast().joined(separator: ", ")
        let tail = values.last!
        return "\(head), and \(tail)"
    }
}
