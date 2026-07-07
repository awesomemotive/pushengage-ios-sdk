//
//  ErrorResponse.swift
//  PushEngage
//
//  Created by Abhishek on 08/03/21.
//

import Foundation

// This struct is for the all the api call which is having not data in the response.
package struct NetworkResponse: Codable {
    package let errorCode: Int?
    package let errorMessage: String?
    package let error: NetworkError?
    package let data: Data?

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case error
        case data
    }

    package struct Data: Codable {
        package let success: Bool?
    }
}

package struct NetworkError: Codable {
    package let message: String?
    let code: Int?
    package let details: NetworkErrorDetail?

    enum CodingKeys: String, CodingKey {
        case message
        case code
        case details
    }

    package struct NetworkErrorDetail: Codable {
        package let message: String?
        let path: String?
    }
}


// MARK: - SubscriberDetailsResponse

// The Obj-C runtime name keeps the historical spelling so 0.1.x Obj-C
// consumers keep resolving the bridged class.
@objcMembers
@objc(SubsciberDetailsResponse) public class SubscriberDetailsResponse: NSObject, Decodable {
    public let errorCode: Int?
    public let data: SubscriberDetailsData?
    public let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case data = "data"
        case errorMessage = "error_message"
    }
}

@available(*, deprecated, renamed: "SubscriberDetailsResponse")
public typealias SubsciberDetailsResponse = SubscriberDetailsResponse

// MARK: - SubscriberDetailsData
@objcMembers
@objc public class SubscriberDetailsData: NSObject, Decodable {

    /// Every field the server returned, keyed by the wire-format (snake_case)
    /// name. Callers read fields by string lookup, e.g.
    /// `data.rawFields["country"] as? String`. No fixed field list.
    public let rawFields: [String: Any]

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public required init(from decoder: Decoder) throws {
        var raw: [String: Any] = [:]
        if let dyn = try? decoder.container(keyedBy: DynamicKey.self) {
            for key in dyn.allKeys {
                if let decoded = try? dyn.decode(AnyCodable.self, forKey: key) {
                    raw[key.stringValue] = decoded.value
                }
            }
        }
        self.rawFields = raw
        super.init()
    }
}


// MARK: - Error Logging Model

package struct SDKServerLogger: Codable {
    let app: String
    package let name: String
    let loggerData: LoggerData
    
    enum CodingKeys: String, CodingKey {
        case app
        case name
        case loggerData = "data"
    }
}

// MARK: - Logger data

struct LoggerData: Codable {
    package let tag: String?
    package let deviceTokenHash: String
    let device: String?
    let timezone: String
    package let error: String
    
    enum CodingKeys: String, CodingKey {
        case tag
        case deviceTokenHash = "device_token_hash"
        case device
        case timezone
        case error
    }
}



