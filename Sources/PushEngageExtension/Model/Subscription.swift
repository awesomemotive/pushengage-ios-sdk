//
//  Subscription.swift
//  PushEngage
//
//  Created by Abhishek on 21/02/21.
//

import Foundation

// MARK: - SubscriptionInfo
package struct SubscriptionInfo: Codable {
    package var siteID: Int?
    package var subscription: Subscription?
    package var deviceType, device, deviceVersion, deviceModel: String?
    var deviceManufacturer: String?
    var timezone: String?
    var language, userAgent, totalScreenWidthHeight, host: String?
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
        case timezone
        case language
        case userAgent = "user_agent"
        case totalScreenWidthHeight = "total_screen_width_height"
        case host, attributes
        case profileID = "profile_id"
        case isNotificationEnable = "notification_disabled"
        case certEnv = "env"
    }
}

// MARK: - Subscription
package struct Subscription: Codable {
    var endpoint, projectID: String?

    enum CodingKeys: String, CodingKey {
        case endpoint
        case projectID = "project_id"
    }
}


// MARK: - AddSubscriberResponse

package struct AddSubscriberResponse: Codable {
    package let errorCode: Int
    package let data: AddSubscriberData?
    package let errorMessage: String?
    package let error: NetworkError?

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case data = "data"
        case errorMessage = "error_message"
        case error
    }
}

// MARK: - AddSubscriberData
package struct AddSubscriberData: Codable {
    package let subscriberHash: String?

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

package struct SubscriberUpgrade: Codable {
    package let deviceTokenHash: String
    package let subscription: Subscription
    let siteId: Int
    package let deviceType: String = "ios"

    enum CodingKeys: String, CodingKey {
        case deviceTokenHash = "device_token_hash"
        case subscription
        case siteId = "site_id"
        case deviceType = "device_type"
    }
}
