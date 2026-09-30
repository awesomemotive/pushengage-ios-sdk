import Foundation

/// A JSON value carried through the SDK verbatim.
///
/// `audience` and `trigger.conditions` are held this way rather than as typed
/// models, for two reasons:
///
/// - **Isolation.** Campaigns decode as one array, so a typed model lets a
///   single malformed `audience` throw and take *every* campaign in the
///   response down with it. Held raw, a bad audience fails closed for that one
///   campaign at display time and the rest still sync.
/// - **One interpreter.** A model *and* an evaluator that both understand the
///   shape invites the two to disagree. `IAMConditionEvaluator` is the only
///   thing that reads it.
struct IAMRawJSON: Codable {

    private let value: IAMJSONValue

    /// The JSON bytes, ready to persist or hand to the evaluator.
    var data: Data {
        (try? value.serialized()) ?? Data()
    }

    init(from decoder: Decoder) throws {
        value = try IAMJSONValue(from: decoder)
    }

    init(data: Data) throws {
        value = try IAMJSONValue(serialized: data)
    }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

/// Minimal JSON tree — only as much as `IAMRawJSON` needs to round-trip a value
/// through `Codable` without knowing its shape.
private indirect enum IAMJSONValue: Codable {
    case null
    case bool(Bool)
    case integer(Int64)
    case double(Double)
    case string(String)
    case array([IAMJSONValue])
    case object([String: IAMJSONValue])

    private struct DynamicKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: DynamicKey.self) {
            var object: [String: IAMJSONValue] = [:]
            for key in container.allKeys {
                object[key.stringValue] = try container.decode(IAMJSONValue.self, forKey: key)
            }
            self = .object(object)
            return
        }

        if var container = try? decoder.unkeyedContainer() {
            var array: [IAMJSONValue] = []
            while !container.isAtEnd {
                array.append(try container.decode(IAMJSONValue.self))
            }
            self = .array(array)
            return
        }

        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let integer = try? container.decode(Int64.self) {
            // Integers before doubles: a whole number that came back as "100.0"
            // would stop matching a string comparison against "100".
            self = .integer(integer)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .integer(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .double(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .array(let values):
            var container = encoder.unkeyedContainer()
            for value in values {
                try container.encode(value)
            }
        case .object(let values):
            var container = encoder.container(keyedBy: DynamicKey.self)
            for (key, value) in values {
                try container.encode(value, forKey: DynamicKey(stringValue: key))
            }
        }
    }

    /// A bare `null` or scalar round-trips as well as an object — a campaign may
    /// legitimately send `"audience": null`.
    ///
    /// A scalar is written by serializing it inside an array and dropping the
    /// brackets, rather than with `JSONSerialization`'s fragment *writing* option:
    /// that option is iOS 13+, the SDK supports iOS 12, and an unrecognised write
    /// option there raises an Objective-C exception no `try?` can catch. (Reading
    /// fragments is fine — that option predates iOS 12.)
    func serialized() throws -> Data {
        let value = foundation
        if value is [Any] || value is [String: Any] {
            return try JSONSerialization.data(withJSONObject: value)
        }
        let wrapped = try JSONSerialization.data(withJSONObject: [value])
        return Data(wrapped.dropFirst().dropLast())
    }

    init(serialized data: Data) throws {
        self = IAMJSONValue(
            foundation: try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        )
    }

    private var foundation: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .integer(let value): return value
        case .double(let value): return value
        case .string(let value): return value
        case .array(let values): return values.map { $0.foundation }
        case .object(let values): return values.mapValues { $0.foundation }
        }
    }

    private init(foundation: Any) {
        switch foundation {
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            self = .bool(number.boolValue)
        case let number as NSNumber:
            self = CFNumberIsFloatType(number) ? .double(number.doubleValue)
                                               : .integer(number.int64Value)
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(array.map { IAMJSONValue(foundation: $0) })
        case let object as [String: Any]:
            self = .object(object.mapValues { IAMJSONValue(foundation: $0) })
        default:
            self = .null
        }
    }
}
