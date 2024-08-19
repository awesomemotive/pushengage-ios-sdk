//
//  NotificationService.swift
//  PushEngageNotificationServiceExtension
//
//  Created by Himshikhar Gayan on 14/02/24.
//

import UserNotifications
import PushEngage

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?
    var request : UNNotificationRequest?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.request = request
        self.contentHandler = contentHandler
        self.bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        if let bestContent = bestAttemptContent {
            PushEngage.didReceiveNotificationExtensionRequest(request, bestContentHandler: bestContent)
            contentHandler(bestContent)
        }
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let request = request ,let bestAttemptContent =  bestAttemptContent {
            guard let content = PushEngage.serviceExtensionTimeWillExpire(request, content: bestAttemptContent) else {
                contentHandler(bestAttemptContent)
                return
            }
            contentHandler(content)
        }
    }

}
