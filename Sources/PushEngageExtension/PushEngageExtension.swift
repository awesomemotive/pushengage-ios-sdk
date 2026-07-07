//
//  PushEngageExtension.swift
//  PushEngageExtension
//

import Foundation
import UserNotifications

@objc public final class PushEngageExtension: NSObject {

    static var manager: NotificationExtensionType = NotificationExtensionFactory.make()

    @objc public static func didReceiveNotificationExtensionRequest(_ request: UNNotificationRequest,
                                                                    bestContentHandler: UNMutableNotificationContent) {
        manager.didReceiveNotificationExtensionRequest(request, bestContentHandler: bestContentHandler)
    }

    @objc public static func serviceExtensionTimeWillExpire(_ request: UNNotificationRequest,
                                                            content: UNMutableNotificationContent?)
        -> UNMutableNotificationContent? {
        return manager.serviceExtensionTimeWillExpire(request, content: content)
    }

    @objc public static func getCustomUIPayLoad(for request: UNNotificationRequest) -> CustomUIModel {
        return manager.getContentExtensionInfo(for: request)
    }
}
