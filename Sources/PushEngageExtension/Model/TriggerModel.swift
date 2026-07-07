//
//  TriggerModel.swift
//  PushEngage
//
//  Created by Abhishek on 07/04/21.
//

import Foundation

package struct TriggerModel: Codable {
    var partitionKey: String
    package var data: TriggerModelData

    package init(partitionKey: String, data: TriggerModelData) {
        self.partitionKey = partitionKey
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case partitionKey = "PartitionKey"
        case data = "Data"
    }
}

package struct TriggerModelData: Codable {
    var siteId: Int
    package var deviceTokenHash: String
    package let campaignName: String
    package let eventName: String
    var timezone: String?
    package var referenceId: String?
    package var profileId: String?
    package var data: [String: String]?

    package init(siteId: Int,
                deviceTokenHash: String,
                campaignName: String,
                eventName: String,
                timezone: String? = nil,
                referenceId: String? = nil,
                profileId: String? = nil,
                data: [String: String]? = nil) {
        self.siteId = siteId
        self.deviceTokenHash = deviceTokenHash
        self.campaignName = campaignName
        self.eventName = eventName
        self.timezone = timezone
        self.referenceId = referenceId
        self.profileId = profileId
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case siteId = "site_id"
        case deviceTokenHash = "device_token_hash"
        case campaignName = "campaign_name"
        case eventName = "event_name"
        case timezone = "timezone"
        case referenceId = "ref_id"
        case profileId = "profile_id"
        case data = "data"
    }
}

package struct TriggerResponse: Codable {
    package var sequenceNumber, shardID: String

    enum CodingKeys: String, CodingKey {
        case sequenceNumber = "SequenceNumber"
        case shardID = "ShardId"
    }
}
