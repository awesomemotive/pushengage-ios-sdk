//
//  DeepLinkingTypes.swift
//  PushEngage
//
//  Created by Abhishek on 09/02/21.
//

import Foundation

public enum DeepLinkingTypes {
    case screens
    case websites
}


public enum PermissonStatus: String {
    
    /// The application is authorized to post user notifications.
    
    case granted
    
    /// The application is not authorized to post user notifications.
    
    case denied
    
    /// The user has not yet made a choice regarding whether the application may post user notifications.
    
    case notYetRequested
    
    /// The application is temporarily authorized to post notifications. Only available to app clips.
    
//    @available(iOS 14.0, *)
//    case ephemeral
//    
//    /// The application is authorized to post non-interruptive user notifications.
//    
//    @available(iOS 12.0, macCatalyst 13.0, *)
//    case provisinal
//    
//    
//    case unknown
}


// Various network connection states -- made consistent.
enum NetworkConnectionStatus: String {
    
    case connected
    case disconnected
    case connecting
    case disconnecting
    case error
    
}

// The key to the notification's "userInfo" dictionary.
enum StatusKey: String {
    case networkStatusKey
    case notificationStatusKey
}


enum RegistraionStatus {
    case registered
    case notRegistered(String, NotRegisteredType)
}

enum NotRegisteredType {
    case notificationDisable
    case both
    case siteKeyissue
    
    var value: String {
        switch self {
        case .notificationDisable:
            return "notification id disable or denied"
        case .both:
            return "site key is not valid and notification disabled"
        case .siteKeyissue:
            return "siteKey is not valid or verified"
        }
    }
}

enum SiteStatus: String {
    case active
    case inactive
    case hold
    case delete
    case none 
    
}


enum  PayloadKey: String {
    case attachmentKey = "att"
    case launchUrlKey = "u"
    case custom = "pe"
    case deeplinking = "dl"
    case actionSelected = "actionSelected"
    case additionalData = "ad"
    case tag = "tag"
    case duplicate = "duplicate"
    case title = "t"
    case aps = "aps"
    case alert = "alert"
    case sound = "sound"
    case badge = "badge"
    case custombadge = "ba"
    case customSound = "s"
    case actionButton = "ab"
    case customsubtitle = "sb"
    case customBody = "b"
}
