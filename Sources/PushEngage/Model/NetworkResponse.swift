//
//  ErrorResponse.swift
//  PushEngage
//
//  Created by Abhishek on 08/03/21.
//

import Foundation

// This struct is for the all the api call which is having not data in the response.
struct NetworkResponse: Codable {
    let errorCode: Int?
    let errorMessage: String?
    let error: NetworkError?
    let data: Data?

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case error
        case data
    }
    
    struct Data: Codable {
        let success: Bool?
    }
}

struct NetworkError: Codable {
    let message: String?
    let code: Int?
    let details: NetworkErrorDetail?
    
    enum CodingKeys: String, CodingKey {
        case message
        case code
        case details
    }
    
    struct NetworkErrorDetail: Codable {
        let message: String?
        let path: String?
    }
}


// MARK: - SubsciberDetailsResponse

@objcMembers
@objc public class SubsciberDetailsResponse: NSObject, Decodable {
    public let errorCode: Int?
    public let data: SubscriberDetailsData?
    public let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case data = "data"
        case errorMessage = "error_message"
    }
}

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

struct SDKServerLogger: Codable {
    let app: String
    let name: String
    let loggerData: LoggerData
    
    enum CodingKeys: String, CodingKey {
        case app
        case name
        case loggerData = "data"
    }
}

// MARK: - Logger data

struct LoggerData: Codable {
    let tag: String?
    let deviceTokenHash: String
    let device: String?
    let timezone: String
    let error: String
    
    enum CodingKeys: String, CodingKey {
        case tag
        case deviceTokenHash = "device_token_hash"
        case device
        case timezone
        case error
    }
}



