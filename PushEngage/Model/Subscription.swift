//
//  Subscription.swift
//  PushEngage
//
//  Created by Abhishek on 21/02/21.
//

import Foundation

// MARK: - SubscriptionInfo
struct SubscriptionInfo: Codable {
    var siteID: Int?
    var subscription: Subscription?
    var deviceType, device, deviceVersion, deviceModel: String?
    var deviceManufacturer: String?
    var latitude, longitude: String?
    var timezone: String?
    var language, userAgent, totalScrWidthHeight, host: String?
    var attributes: [String: String]?
    var profileID: String?
    var isNotificationEnable: Int?
    var certEnv: String?

    enum CodingKeys: String, CodingKey {
        case siteID = "site_id"
        case subscription
        case deviceType = "device_type"
        case device
        case deviceVersion = "device_version"
        case deviceModel = "device_model"
        case deviceManufacturer = "device_manufacturer"
        case latitude, longitude, timezone
        case language
        case userAgent = "user_agent"
        case totalScrWidthHeight = "total_scr_width_height"
        case host, attributes
        case profileID = "profile_id"
        case isNotificationEnable = "notification_disabled"
        case certEnv = "env"
    }
}

// MARK: - Subscription
struct Subscription: Codable {
    var endpoint, projectID: String?

    enum CodingKeys: String, CodingKey {
        case endpoint
        case projectID = "project_id"
    }
}


// MARK: - AddSubscriberResponse

struct AddSubscriberResponse: Codable {
    let errorCode: Int
    let data: AddSubscriberData?
    let errorMessage: String?
    let error: NetworkError?

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case data = "data"
        case errorMessage = "error_message"
        case error
    }
}

// MARK: - AddSubscriberData
struct AddSubscriberData: Codable {
    let subscriberHash: String?

    enum CodingKeys: String, CodingKey {
        case subscriberHash = "subscriber_hash"
    }
}

// MARK: - Check SubscriberApi

@objcMembers
@objc final public class CheckSubscriberResponse: NSObject, Codable {
    public let errorCode: Int?
    public let data: CheckSubscriberData?
    public let errorMessage: String?
    
    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case data = "data"
        case errorMessage = "error_message"
    }
}

// MARK: - Check response data

@objcMembers
@objc final public class CheckSubscriberData: NSObject, Codable {
    public let deviceToken: String?
    
    enum CodingKeys: String, CodingKey {
        case deviceToken = "gateway_endpoint"
    }
}

// MARK: -

struct SubscriberUpgrade: Codable {
    let deviceTokenHash: String
    let subscription: Subscription
    let siteId: Int
    
    enum CodingKeys: String, CodingKey {
        case deviceTokenHash = "device_token_hash"
        case subscription
        case siteId = "site_id"
    }
}



