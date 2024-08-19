//
//  Permission.swift
//  PushEngage
//
//  Created by Abhishek on 21/02/21.
//

import Foundation

struct SubscriberDetails: Codable {
    
    var siteID: Int?
    var deviceToken: String?
    var deviceTokenHash: String?
    var isUnSubscribed: Int?
    var triggerStatus: Int?
    var profileId: String?
    var timezone: String?
    var deviceType: String?
    var segment: [String]?
    var segments: [Segment]?
    var segmentId: Int?
    var notificationDisabled: Bool?
    var goalCount: Int?
    var goalValue: Double?
    var goalName: String?
    
    enum CodingKeys: String, CodingKey {
        case siteID = "site_id"
        case deviceTokenHash = "device_token_hash"
        case isUnSubscribed = "IsUnSubscribed"
        case triggerStatus = "triggerStatus"
        case profileId = "profile_id"
        case timezone = "timezone"
        case deviceType = "device_type"
        case segment = "segment"
        case segments = "segments"
        case deviceToken = "device_token"
        case segmentId = "segment_id"
        case notificationDisabled = "delete_on_notification_disable"
        case goalCount = "count"
        case goalValue = "value"
        case goalName = "name"
    }
}

struct Segment: Codable {
    let name: String
    let duration: Int
    
    enum CodingKeys: String, CodingKey {
        case name
        case duration
    }
}

