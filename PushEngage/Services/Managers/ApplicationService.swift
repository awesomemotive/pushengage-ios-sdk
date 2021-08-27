//
//  ApplicationService.swift
//  PushEngage
//
//  Created by Abhishek on 03/02/21.
//

import Foundation
import UIKit
import UserNotifications

protocol LastNotificationSetDelagate: AnyObject {
    func setLast(notification infoDict: [AnyHashable: Any], completionHandler: ((UIBackgroundFetchResult) -> Void)?)
    func silentRemoteNotificationRecivedNotification(with userInfo: [AnyHashable: Any], isOpened: Bool)
}

class ApplicationService: ApplicationProtocol {
    
    private var userDefault: UserDefaultProtocol
    private let subscriberService: SubscriberService
    private let notificationLifeCycleService: NotificationLifeCycleService
    private let networkService: NetworkRouter
    private let operationQueue: OperationQueue
    
    weak var notifydelegate: LastNotificationSetDelagate?
    
     init(userDefault: UserDefaultProtocol,
          subscriberService: SubscriberService,
          notificationLifeCycleService: NotificationLifeCycleService,
          networkService: NetworkRouter) {
        self.userDefault = userDefault
        self.subscriberService = subscriberService
        self.notificationLifeCycleService = notificationLifeCycleService
        self.networkService = networkService
        self.operationQueue = OperationQueue()
    }
    
    /// This function make sure that device token is register to pushengage server A.K.A (add Subscriber.)
    /// And also responsible to update the device token to server also.
    func registerDeviceToServer(with deviceToken: Data) {
        let token = deviceToken.reduce("", {$0 + String(format: "%02X", $1)})
        let existingDeviceToken = userDefault.deviceToken
        userDefault.deviceToken = token
        
        if existingDeviceToken.isEmpty || existingDeviceToken == userDefault.deviceToken {
            userDefault.istriedFirstTime = false
            subscriberService.retryAddSubscriberProcess { [weak self] _ in
                self?.userDefault.istriedFirstTime = true
            }
        } else {
            let siteStatus = SiteStatus(rawValue: userDefault.siteStatus)
            if siteStatus == .active {
                userDefault.istriedFirstTime = false
                subscriberService.upgradeSubscription { [weak self] _, _ in
                    self?.userDefault.istriedFirstTime = true
                }
                PELogger.debug(className: String(describing: ApplicationService.self),
                               message: "Successfully updated Device token the PushEngage Server.")
            }
        }
    }
    
    func recivedRemoteNotification(application: UIApplication,
                                   userInfo: [AnyHashable: Any],
                                   completionHandler: ((UIBackgroundFetchResult) -> Void)?) -> Bool {
        var backgroundJobFired = false
        let peNotification = PENotification(userInfo: userInfo)
        
        if self.isAlertNotificationWithCustomAlert(info: userInfo)
            || peNotification.isSponsered == 1 {
            if #available(iOS 10.0, *) {
                backgroundJobFired = true
                self.addNotificationRequest(application: application,
                                            notification: peNotification,
                                            completionHandler: completionHandler)
            } else {
                self.notificationForiOS9(peNotification)
            }
        } else if application.applicationState == .active {
            notifydelegate?.setLast(notification: userInfo, completionHandler: nil)
            if Utility.isNotifiyIsDisplayable(userInfo: userInfo) {
                notifydelegate?.silentRemoteNotificationRecivedNotification(with: userInfo, isOpened: true)
            }
            return backgroundJobFired
            
        } else {
            backgroundJobFired = true
            notifydelegate?.setLast(notification: userInfo, completionHandler: completionHandler)
        }
        return backgroundJobFired
    }
    
    @available(iOS, deprecated:9.0)
    private func notificationForiOS9(_ notification: PENotification) {
        let notification = Utility.createUILocalNotification(for: notification)
        UIApplication.shared.scheduleLocalNotification(notification)
    }
    
    @available(iOS 10.0, *)
    func addNotificationRequest(application: UIApplication,
                                notification: PENotification,
                                completionHandler: ((UIBackgroundFetchResult) -> Void)?) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            BackgroundTaskExpirationHandler.run(application: application) { [weak self] (background) in
                let request: UNNotificationRequest?
                    = notification.isSponsered == 1 ? self?.createSponseredNotification(notification: notification) :
                Utility.createUNNotificationRequest(notification: notification, networkService: self?.networkService)
                if let notificationRequest = request {
                    
                    UNUserNotificationCenter.current().add(notificationRequest) { (error) in
                        PELogger.debug(className: String(describing: self),
                                       message: error.debugDescription)
                        if completionHandler != nil {
                            completionHandler?(.newData)
                        }
                    }
                }
                background.end()
            }
            self?.notificationLifeCycleService
                .withRetrynotificationLifecycleUpdate(with: .viewed,
                                                      deviceHash: self?.userDefault.deviceToken ?? "",
                                                      notificationId: notification.tag,
                                                      actionid: nil, completionHandler: nil)
        }
    }
    
    /// func take care for the sponsered notification as  sponsered notification is recognised as silent notification in SDK.
    /// And then create notification with data available from postback call the 0.25 second sponsered notfication is fired.
    @available(iOS 10.0, *)
    private func createSponseredNotification(notification: PENotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.sound = UNNotificationSound.default
        content.userInfo = notification.rawPayload
        let sponseredInput: SponseredNotificationInput = (nil ,
                              content ,
                              self.notificationLifeCycleService ,
                              self.networkService,
                              notification)
        let sponserOperation = SponseredNotifictaionOperation(input: sponseredInput)
        sponserOperation.onResult = { result in
            switch result {
            case .success(let updateAttachment):
                PELogger.info(className: String(describing: ApplicationService.self),
                              message: updateAttachment.attachmentString ?? "")
            case .failure(let error):
                PELogger.error(className: String(describing: ApplicationService.self),
                               message: error.errorDescription ?? "")
            }
        }
        let downloadOperationQueue: DownloadOperationInput? = nil

        let imageDownloadOperation = DownloadAttachmentOperation(inputValue: downloadOperationQueue)
        imageDownloadOperation.onResult = { result in
            switch result {
            case .failure(let error):
                PELogger.error(className: String(describing: ApplicationService.self),
                               message: error.errorDescription ?? "")

            case .success(let message):
                PELogger.info(className: String(describing: ApplicationService.self), message: message)
            }
        }
        imageDownloadOperation.addDependency(sponserOperation)
        operationQueue.addOperations([sponserOperation, imageDownloadOperation], waitUntilFinished: true)
        let identifier = "PESponsered\(UUID().uuidString)"
        let notify = PENotification(userInfo: content.userInfo)
        Utility.addButtonTo(withNotification: notify, content: content)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.25, repeats: false)
        content.threadIdentifier = "pushengage-sponsered-notification"
        return UNNotificationRequest(identifier: identifier,
                                     content: content,
                                     trigger: trigger)
    }
    
    private func isAlertNotificationWithCustomAlert(info: [AnyHashable: Any]) -> Bool {
        if info[userInfo: PayloadConstants.aps]?[userInfo: PayloadConstants.alert] == nil
            && (info[userInfo: PayloadConstants.custom]?[string: PayloadConstants.title] != nil
                    || info[userInfo: PayloadConstants.custom]?[string: PayloadConstants.customsubtitle] != nil
                    || info[userInfo: PayloadConstants.custom]?[string: PayloadConstants.customBody] != nil ) {
            return true
        }
        return false
    }
}

