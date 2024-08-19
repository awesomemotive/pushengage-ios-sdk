//
//  PEPayLoad.swift
//  PushEngage
//
//  Created by Abhishek on 18/02/21.
//

import Foundation
import UIKit

// MARK: - PEPayload
struct PEPayload: Codable {
    let aps: Aps?
    let custom: Custom?
    
    enum CodingKeys: String, CodingKey {
        case custom = "pe"
        case aps = "aps"
    }
}

// MARK: - Aps
struct Aps: Codable {
    let alert: Alert?
    let badge: Int?
    let sound: String?
    let mutableContent, contentAvailable: Int?
    let category, threadID, targetContentID: String?

    enum CodingKeys: String, CodingKey {
        case alert, badge, sound
        case mutableContent = "mutable-content"
        case contentAvailable = "content-available"
        case category
        case threadID = "thread-id"
        case targetContentID = "target-content-id"
    }
}

// MARK: - Alert
struct Alert: Codable {
    let title, subtitle, body: String?
}

// MARK: - Custom
struct Custom: Codable {
    let tag, attachmentURL, launchURL: String?
    let isSponsered: Int?
    let postback: AnyCodable?
    let badgeIncrement: Int?
    let title, body: String?
    let badge: Int?
    let sound, subtitle: String?
    let actionButtons: [ActionButtonInfo]?
    var additionalData: [String: String]?
    let deeplinking: String?
    
    enum CodingKeys: String, CodingKey {
        case tag
        case attachmentURL = "att"
        case launchURL = "u"
        case isSponsered = "rf"
        case postback = "pb"
        case badgeIncrement = "bi"
        case title = "t"
        case body = "b"
        case badge = "ba"
        case sound = "s"
        case subtitle = "sb"
        case actionButtons = "ab"
        case deeplinking = "dl"
        case additionalData = "ad"
    }
}

// MARK: - ActionButtonInfo
struct ActionButtonInfo: Codable {
    let id, text: String
    
    enum CodingKeys: String, CodingKey {
        case id = "a"
        case text = "b"
    }
}

@objcMembers
public class CustomUIModel: NSObject {
    
    public var title: String
    public var body: String
    public var image: UIImage?
    public var buttons: [CustomUIButtons]?
    
    init(title: String,
         body: String,
         image: UIImage?,
         buttons: [CustomUIButtons]?) {
        self.title = title
        self.body = body
        self.image = image
        self.buttons = buttons
    }
    
}

@objcMembers
public class CustomUIButtons: NSObject {
    
    public var text: String
    public var id: String
    
     init(text: String,
          id: String) {
        self.text = text
        self.id = id
    }
}
