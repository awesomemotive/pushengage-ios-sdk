//
//  Permission.swift
//  PushEngage
//
//  Created by Abhishek on 21/02/21.
//

import Foundation

package struct SubscriberDetails: Codable {

    package var siteID: Int?
    package var deviceToken: String?
    package var deviceTokenHash: String?
    package var isUnSubscribed: Int?
    package var triggerStatus: Int?
    package var profileId: String?
    var timezone: String?
    package var deviceType: String?
    package var segment: [String]?
    package var segments: [Segment]?
    package var segmentId: Int?
    package var notificationDisabled: Bool?
    package var goalCount: Int?
    package var goalValue: Double?
    package var goalName: String?

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

package struct Segment: Codable {
    package let name: String
    let duration: Int

    enum CodingKeys: String, CodingKey {
        case name
        case duration
    }
}
