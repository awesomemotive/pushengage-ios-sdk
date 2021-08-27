//
//  PENotification.swift
//  PushEngage
//
//  Created by Abhishek on 28/05/21.
//

import Foundation

@objc public enum ActionType: Int {
    case opened
    case taken
}

@objcMembers
@objc public class PENotification: NSObject {
    
    var timeoutTimer: Timer?
    public var completionBlock: PENotificationDisplayNotification?
    internal(set)public var title: String?
    internal(set)public var body: String?
    internal(set)public var badge: Int?
    internal(set)public var sound: String?
    internal(set)public var mutableContent: Int
    internal(set)public var contentAvailable: Int
    internal(set)public var category: String?
    internal(set)public var threadId: String?
    internal(set)public var targetContentId: String?
    internal(set)public var tag: String
    internal(set)public var attachmentURL: String?
    internal(set)public var launchURL: String?
    internal(set)public var isSponsered: Int
    internal(set)public var badgeIncrement: Int?
    internal(set)public var additionalData: [String: String]?
    internal(set)public var actionButtons: [PEActionButton]?
    internal(set)public var subtitle: String?
    internal(set)public var rawPayload: [AnyHashable: Any]
    internal(set)public var deeplinking: String?
    var postback: AnyCodable?
    
    init(userInfo: [AnyHashable: Any]) {
        var parsedValue: PEPayload? = Utility.parse(typeof: PEPayload.self,
                                                    payload: userInfo)
        self.rawPayload = userInfo
        self.mutableContent = parsedValue?.aps?.mutableContent ?? 0
        self.contentAvailable = parsedValue?.aps?.contentAvailable ?? 0
        self.category = parsedValue?.aps?.category
        self.targetContentId = parsedValue?.aps?.targetContentID
        self.tag = parsedValue?.custom?.tag ?? ""
        self.attachmentURL = parsedValue?.custom?.attachmentURL
        self.launchURL = parsedValue?.custom?.launchURL
        self.isSponsered = parsedValue?.custom?.isSponsered ?? 0
        self.badgeIncrement = parsedValue?.custom?.badgeIncrement 
        self.additionalData = parsedValue?.custom?.additionalData
        self.postback = parsedValue?.custom?.postback
        self.deeplinking = parsedValue?.custom?.deeplinking
        self.actionButtons = parsedValue?.custom?
                             .actionButtons?
                             .compactMap { return PEActionButton(id: $0.id, title: $0.text) }
        super.init()
        self.setUpAlert(from: parsedValue)
        parsedValue = nil
    }
    
    private func setUpAlert(from notification: PEPayload?) {
        if notification?.aps?.alert == nil {
            self.title = notification?.custom?.title
            self.body = notification?.custom?.body
            self.badge = notification?.custom?.badge
            self.subtitle = notification?.custom?.subtitle
            self.sound = notification?.custom?.sound
        } else {
            self.title = notification?.aps?.alert?.title
            self.body = notification?.aps?.alert?.body
            self.badge = notification?.aps?.badge
            self.subtitle = notification?.aps?.alert?.subtitle
            self.sound = notification?.aps?.sound
        }
    }
    
    public class PEActionButton {
        var id: String
        var title: String
        
        init(id: String,
             title: String) {
            self.id = id
            self.title = title
        }
    }
    
    deinit {
        releaseTimer()
        PELogger.debug(className: String(describing: PENotification.self),
                       message: "PENotification is deinitalized")
    }

    // MARK: - will show in forground
    
    func timeOutTimerSetup() {
        timeoutTimer = Timer.init(timeInterval: 25.0,
                                  target: self,
                                  selector: #selector(timeoutFired(timer:)),
                                  userInfo: tag, repeats: false)
    }
    
    
    @objc func timeoutFired(timer: Timer) {
        self.completionTask(notification: self)
    }
    
    func setCompletion(for block: @escaping PENotificationDisplayNotification) {
        completionBlock = block
    }
    
    func getCompletionBlock() -> PENotificationDisplayNotification {
        let block = { [weak self] (notification: PENotification?) -> Void in
            self?.completionTask(notification: notification)
        }
        return block
    }
    
    func completionTask(notification: PENotification?) {
        timeoutTimer?.invalidate()
        if completionBlock != nil {
            completionBlock?(notification)
            completionBlock = nil
        }
    }
    
    func releaseTimer() {
        if completionBlock != nil && timeoutTimer != nil {
            timeoutTimer?.invalidate()
            timeoutTimer = nil
        }
    }
    
    func startTimeoutTimer() {
        if let unWrapTimeout = timeoutTimer {
            RunLoop.current.add(unWrapTimeout, forMode: .common)
        }
    }

}

@objcMembers
@objc public class PENotificationOpenResult: NSObject {
   
    public var notification: PENotification
    public var notificationAction: PEnotificationAction
    
    public init(notification: PENotification,
                notficationAction: PEnotificationAction) {
        self.notification = notification
        self.notificationAction = notficationAction
        super.init()
    }
}

@objcMembers
@objc public class PEnotificationAction: NSObject {
    
    internal (set) public var actionID: String?
    public var actionType: ActionType
    
    public init(actionID: String?,  
                actionType: ActionType) {
        self.actionID = actionID
        self.actionType = actionType
        super.init()
    }
}
