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

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case error
    }
}

struct  NetworkError: Codable {
    let message: String
    let code: Int
    
    enum CodingKeys: String, CodingKey {
        case message
        case code
    }
}


// MARK: - SubsciberDetailsResponse

@objcMembers
@objc public class SubsciberDetailsResponse: NSObject, Codable {
    public var errorCode: Int?
    public var data: SubscriberDetailsData?
    public var errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case data = "data"
        case errorMessage = "error_message"
    }
}

// MARK: - SubscriberDetailsData
@objcMembers
@objc public class SubscriberDetailsData: NSObject, Codable {
    public var city, device, host, userAgent: String?
    public var deviceType: String?
    public var segments: [String]?
    public var timezone, country, tsCreated, state: String?
    public var subscriptionURL: String?

    enum CodingKeys: String, CodingKey {
        case city, device, host
        case userAgent = "user_agent"
        case deviceType = "device_type"
        case segments, timezone, country
        case tsCreated = "ts_created"
        case state
        case subscriptionURL = "subscription_url"
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



