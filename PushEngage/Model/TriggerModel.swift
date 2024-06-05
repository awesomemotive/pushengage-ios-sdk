//
//  TriggerModel.swift
//  PushEngage
//
//  Created by Abhishek on 07/04/21.
//

import Foundation

@objc public enum TriggerAlertType: Int {
    case priceDrop
    case inventory
}

@objc public enum TriggerAlertAvailabilityType: Int {
    case inStock
    case outOfStock
}

@objcMembers
@objc public class TriggerCampaign: NSObject {
    let campaignName: String
    let eventName: String
    var referenceId: String?
    var profileId: String?
    var data: [String: String]?
    
    public init(campaignName: String,
                eventName: String,
                referenceId: String?=nil,
                profileId: String?=nil,
                data: [String: String]?=nil) {
        self.eventName = eventName
        self.campaignName = campaignName
        self.profileId = profileId
        self.referenceId = referenceId
        self.data = data
    }
    
}

@objc public class TriggerAlert: NSObject {
    let type: TriggerAlertType
    let productId: String
    let link: String
    let price: Double
    let variantId: String?
    let expiryDateTime: Date?
    let alertPrice: Double?
    let availability: TriggerAlertAvailabilityType?
    let profileId: String?
    let mrp: Double?
    let data: [String: String]?
    
    public init(type: TriggerAlertType,
                productId: String,
                link: String,
                price: Double,
                variantId: String?=nil,
                expiryTimestamp: Date?=nil,
                alertPrice: Double?=nil,
                availability: TriggerAlertAvailabilityType?=nil,
                profileId: String?=nil,
                mrp: Double?=nil,
                data: [String : String]?=nil) {
        self.type = type
        self.productId = productId
        self.link = link
        self.price = price
        self.variantId = variantId
        self.expiryDateTime = expiryTimestamp
        self.alertPrice = alertPrice
        self.availability = availability
        self.profileId = profileId
        self.mrp = mrp
        self.data = data
    }
}

struct TriggerModel: Codable {
    var partitionKey: String
    var data: TriggerModelData

    enum CodingKeys: String, CodingKey {
        case partitionKey = "PartitionKey"
        case data = "Data"
    }
}

struct TriggerModelData: Codable {
    var siteId: Int
    var deviceTokenHash: String
    let campaignName: String
    let eventName: String
    var timezone: String?
    var referenceId: String?
    var profileId: String?
    var data: [String: String]?
    
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

struct TriggerResponse: Codable {
    var sequenceNumber, shardID: String

    enum CodingKeys: String, CodingKey {
        case sequenceNumber = "SequenceNumber"
        case shardID = "ShardId"
    }
}
