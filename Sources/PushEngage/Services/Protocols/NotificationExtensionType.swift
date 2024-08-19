//
//  NotificationExtensionProtocol.swift
//  PushEngage
//
//  Created by Abhishek on 16/02/21.
//

import UserNotifications

protocol NotificationExtensionType {
    
    @available(iOS 10.0, *)
    func didReceiveNotificationExtensionRequest(_ request: UNNotificationRequest,
                                                bestContentHandler: UNMutableNotificationContent)
    @available(iOS 10.0, *)
    func serviceExtensionTimeWillExpire(_ request: UNNotificationRequest,
                                        content: UNMutableNotificationContent?) -> UNMutableNotificationContent?
    @available(iOS 10.0, *)
    func getContentExtensionInfo(for request: UNNotificationRequest) -> CustomUIModel
}
