//
//  TrackEventRequest.swift
//  PushEngage
//
//  Wire payload for the trackEvent API. Mirrors the Android
//  `TrackEventRequest` snake_case shape sent to `POST events/track`.
//

import Foundation

package struct TrackEventRequest: Codable {
    let siteId: Int
    package let deviceTokenHash: String
    package let eventName: String
    let provider: String
    let eventType: String
    package let profileId: String?
    package let data: [String: TrackEventValue]

    enum CodingKeys: String, CodingKey {
        case siteId          = "site_id"
        case deviceTokenHash = "device_token_hash"
        case eventName       = "event_name"
        case provider
        case eventType       = "event_type"
        case profileId       = "profile_id"
        case data
    }

    package static let defaultProvider  = "PushEngage"
    package static let defaultEventType = "PushEngage.CustomEvent"

    package init(siteId: Int, deviceTokenHash: String, eventName: String,
                provider: String, eventType: String, profileId: String?,
                data: [String: TrackEventValue]) {
        self.siteId = siteId
        self.deviceTokenHash = deviceTokenHash
        self.eventName = eventName
        self.provider = provider
        self.eventType = eventType
        self.profileId = profileId
        self.data = data
    }
}

/// Strongly-typed wire value for `TrackEventRequest.data`. Unlike `AnyCodable`,
/// this disambiguates Bool from numeric NSNumber via `CFGetTypeID` — necessary
/// because `NSNumber(value: true) as? Int` returns `1` in Swift, which would
/// otherwise serialize as JSON integer `1` instead of JSON boolean `true` and
/// silently break cross-platform parity with Android (which sends `true`).
package enum TrackEventValue: Encodable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i):    try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b):   try container.encode(b)
        }
    }

    /// Converts a validated `Any` value into a typed wire value. Returns `nil`
    /// for unsupported inputs — the validator should reject those upstream
    /// before this is called.
    package static func from(_ value: Any) -> TrackEventValue? {
        // NSNumber wraps Bool, Int, Float, Double on the Obj-C bridge.
        // Disambiguate Bool via CFBoolean before falling into numeric branches.
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            let typeChar = String(cString: number.objCType)
            switch typeChar {
            case "c", "C", "s", "S", "i", "I", "l", "L", "q", "Q":
                return .int(number.int64Value)
            case "f", "d":
                return .double(number.doubleValue)
            default:
                return .double(number.doubleValue)
            }
        }
        if let s = value as? String { return .string(s) }
        if let b = value as? Bool   { return .bool(b) }
        return nil
    }
}

// Required so `TrackEventRequest` keeps Codable conformance. Decoding is not
// exercised in production (we never deserialize a TrackEventRequest), but
// the type stays Codable for symmetry.
extension TrackEventValue: Decodable {
    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { self = .string(s); return }
        if let b = try? container.decode(Bool.self)   { self = .bool(b);   return }
        if let i = try? container.decode(Int64.self)  { self = .int(i);    return }
        if let d = try? container.decode(Double.self) { self = .double(d); return }
        throw DecodingError.dataCorruptedError(in: container,
              debugDescription: "TrackEventValue: unsupported JSON type")
    }
}
