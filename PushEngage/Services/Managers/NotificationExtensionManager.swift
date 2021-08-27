//
//  NotificationExtensionManager.swift
//  PushEngage
//
//  Created by Abhishek on 16/02/21.
//

import Foundation
import UserNotifications
import UIKit


class NotificationExtensionManager: NotificationExtensionProtocol {
    
    var networkService: NetworkRouter
    var notifcationLifeCycleService: NotificationLifeCycleService
    var userDefaultDatasource: UserDefaultProtocol
    private var operationQueue: OperationQueue
    
    init(networkService: NetworkRouter,
         notifcationLifeCycleService: NotificationLifeCycleService,
         userDefaultDatasource: UserDefaultProtocol) {
        self.networkService = networkService
        self.notifcationLifeCycleService = notifcationLifeCycleService
        self.userDefaultDatasource = userDefaultDatasource
        self.operationQueue = OperationQueue()
    }
    
    @available(iOS 10.0, *)
    func didReceiveNotificationExtensionRequest(_ request: UNNotificationRequest,
                                                bestContentHandler: UNMutableNotificationContent) {
        
        if Utility.isPEPayload(userInfo: request.content.userInfo) == false {
            PELogger.debug(className: String(describing: NotificationExtensionManager.self),
                           message: "payload is not pushengage.")
            return
        }
        
        let notificationObj = PENotification(userInfo: request.content.userInfo)
        self.addButtonTo(extension: request,
                         withNotification: notificationObj,
                         content: bestContentHandler)
        updateBadgeCount(with: notificationObj, for: bestContentHandler)
        if let sound = notificationObj.sound {
            bestContentHandler.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: sound))
        } else {
            bestContentHandler.sound = UNNotificationSound.default
        }
        
        if let att = notificationObj.attachmentURL, !att.isEmpty {
            let downloadOperationQueue: DownloadOperationInput = (att,
                                                                  bestContentHandler, networkService)
            
            let imageDownloadOperation = DownloadAttachmentOperation(inputValue: downloadOperationQueue)
            imageDownloadOperation.onResult = { result in
                switch result {
                case .failure(let error):
                    PELogger.error(className: String(describing: NotificationExtensionManager.self),
                                   message: error.errorDescription ?? "")
                    
                case .success(let message):
                    PELogger.info(className: String(describing: NotificationExtensionManager.self), message: message)
                }
            }
            operationQueue.addOperations([imageDownloadOperation], waitUntilFinished: true)
        }
        notifcationLifeCycleService
            .withRetrynotificationLifecycleUpdate(with: .viewed,
                                         deviceHash: userDefaultDatasource.subscriberHash,
                                         notificationId: notificationObj.tag,
                                         actionid: nil,
                                         completionHandler: nil)
    }
    
    @available(iOS 10.0, *)
    func serviceExtensionTimeWillExpire(_ request: UNNotificationRequest,
                                        content: UNMutableNotificationContent?) -> UNMutableNotificationContent? {
        if Utility.isPEPayload(userInfo: request.content.userInfo) == false {
            PELogger.debug(className: String(describing: NotificationExtensionManager.self),
                           message: "payload is not pushengage.")
            return nil
        }
        let notification = PENotification(userInfo: request.content.userInfo)
        guard let updateContent = content else {
            return nil
        }
        self.addButtonTo(extension: request,
                         withNotification: notification,
                         content: updateContent)
        return updateContent
    }
    
    @available(iOS 10.0, *)
    func getContentExtensionInfo(for request: UNNotificationRequest) -> CustomUIModel {
        let notification = PENotification(userInfo: request.content.userInfo)
        var images: [UIImage] = []
        request.content.attachments.forEach { (attachment) in
            if attachment.url.startAccessingSecurityScopedResource() {
                if let data = try? Data(contentsOf: attachment.url),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
                attachment.url.stopAccessingSecurityScopedResource()
            }
        }
        var buttons: [CustomUIButtons] = []
        notification.actionButtons?.compactMap { $0 }.forEach {
            let buttonObj = CustomUIButtons(text: $0.title,
                                            id: $0.id)
            buttons.append(buttonObj)
         }
        
        return CustomUIModel(title: notification.title ?? "",
                             body: notification.body ?? "",
                             image: images.first, buttons: buttons)
    }
    
    // MARK: - upate badge count handler method implmentation
    
    @available(iOS 10.0, *)
    private func updateBadgeCount(with notification: PENotification? ,
                                  for replacementContent: UNMutableNotificationContent ) {
        
        guard let increment = notification?.badgeIncrement else {
            if let badge = notification?.badge {
                userDefaultDatasource.badgeCount = badge
            }
            return
        }
        
        var currentBadgeValue = userDefaultDatasource.badgeCount ?? 0
        currentBadgeValue += increment
        
        if currentBadgeValue < 0 {
            currentBadgeValue = 0
        }
        
        replacementContent.badge = NSNumber(value: currentBadgeValue)
        userDefaultDatasource.badgeCount = currentBadgeValue
    }
    
    @available(iOS 10.0, *)
    private func addButtonTo(extension request: UNNotificationRequest,
                             withNotification: PENotification,
                             content: UNMutableNotificationContent) {
        
        // If developer has already set the catogery identifier then we
        // will not over ride the category with over created one
        
        if !request.content.categoryIdentifier.isEmpty {
            return
        }
        Utility.addButtonTo(withNotification: withNotification, content: content)
    }
}
