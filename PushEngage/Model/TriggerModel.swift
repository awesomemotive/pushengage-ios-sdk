//
//  TriggerModel.swift
//  PushEngage
//
//  Created by Abhishek on 07/04/21.
//

import Foundation

@objcMembers
@objc public class TriggerCampaign: NSObject {
    var campaignName, eventName: String
    var data: [String: String]?
    var notificationDetails: [TriggerNotification]?
    
    public init(campaignName: String,
                eventName: String,
                notificationDetails: [TriggerNotification]?,
                data: [String: String]?) {
        self.eventName = eventName
        self.campaignName = campaignName
        self.notificationDetails = notificationDetails
        self.data = data
    }
    
}

@objcMembers
@objc public class TriggerNotification: NSObject {
    
    var title: Input?
    var message: Input?
    var notificationURL: Input
    var notificationImage: Input?
    var bigImage: Input?
    var actions: Input?
    
    public init(notificationURL: Input,
                title: Input?,
                message: Input?,
                notificationImage: Input?,
                bigImage: Input?,
                actions: Input?) {
        self.notificationURL = notificationURL
        self.title = title
        self.message = message
        self.actions = actions
        self.bigImage = bigImage
        self.notificationImage = notificationImage
    }
}

@objcMembers
@objc public class Input: NSObject {
    var key: String
    var value: String
    var dict: [String: String] {
        return [key: value]
    }
    
    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}


struct TriggerResponse: Codable {
    var sequenceNumber, shardID: String

    enum CodingKeys: String, CodingKey {
        case sequenceNumber = "SequenceNumber"
        case shardID = "ShardId"
    }
}

