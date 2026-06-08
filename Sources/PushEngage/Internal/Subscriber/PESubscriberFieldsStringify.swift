//
//  PESubscriberFieldsStringify.swift
//  PushEngage
//
//  Shared stringification helpers for `PESubscriberFieldsValidator` (which
//  coerces `profile_id` Number → String at the wire seam) and
//  `PESubscriberFieldsHandler` (which stringifies cache values for the
//  identify short-circuit comparison). Single source of truth so the cache
//  key shape can't desync from the wire shape.
//

import Foundation

internal enum PESubscriberFieldsStringify {

    /// CFBoolean discriminator. `NSNumber(value: true)` and `NSNumber(value: 1)`
    /// both have objCType `c`; only `CFGetTypeID` reliably distinguishes them.
    static func isBool(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    /// Produces a clean decimal string for an NSNumber. Integer-valued doubles
    /// (e.g., 42.0) keep their fractional `.0` to match Kotlin's
    /// `Double.toString()` shape. Used by both the validator (profile_id
    /// coercion) and the handler (cache-key stringification).
    static func stringify(number: NSNumber) -> String {
        let typeChar = String(cString: number.objCType)
        switch typeChar {
        case "c", "C", "s", "S", "i", "I", "l", "L", "q", "Q":
            return number.stringValue
        default:
            let d = number.doubleValue
            if d == floor(d) && d.isFinite {
                return "\(d)"
            }
            return number.stringValue
        }
    }

    /// Stringifies an entire `[String: Any]` dict for cache-key comparison.
    /// Bool emits "true"/"false"; numbers go through `stringify(number:)`;
    /// String passes through. The validator guarantees no other types reach
    /// here, but defensive `String(describing:)` keeps this total.
    static func stringifyDict(_ fields: [String: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in fields {
            if let s = v as? String { out[k] = s; continue }
            if let number = v as? NSNumber {
                if isBool(v) {
                    out[k] = number.boolValue ? "true" : "false"
                } else {
                    out[k] = stringify(number: number)
                }
                continue
            }
            out[k] = String(describing: v)
        }
        return out
    }
}
