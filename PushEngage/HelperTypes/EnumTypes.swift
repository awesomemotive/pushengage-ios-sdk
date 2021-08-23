//
//  DeepLinkingTypes.swift
//  PushEngage
//
//  Created by Abhishek on 09/02/21.
//

import Foundation

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

enum SiteStatus: String {
    case active
    case inactive
    case hold
    case delete
    case none 
    
}
