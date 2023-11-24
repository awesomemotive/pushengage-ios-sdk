//
//  PushEngageUNUserNotificationCenter.swift
//  PushEngage
//
//  Created by Abhishek on 22/05/21.
//

import UIKit
import UserNotifications

// method Swizzling of UNUsernotificationCenterDelegate method for iOS 10+ 

class PEUNUserNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static var singleInstance: PEUNUserNotificationCenterDelegate?
    static func sharedInstance() -> PEUNUserNotificationCenterDelegate? {
        let lockQueue = DispatchQueue(label: "com.pushengage.lock.queue.singleInstance", attributes: .concurrent)
        lockQueue.sync(flags: [.barrier]) {
            if singleInstance == nil {
                singleInstance = PEUNUserNotificationCenterDelegate()
            }
        }
        return singleInstance
    }
}

@available(iOS 10.0, *)
typealias PENotificationCenterCompletionHandler = (UNNotificationPresentationOptions) -> Void

// This class hooks into the following iSO 10 UNUserNotificationCenterDelegate selectors:
// - userNotificationCenter:willPresentNotification:withCompletionHandler:
//   - Reads PushEngage inFocusDisplayType to respect it's setting.
// - userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:
//   - Used to process opening notifications.
//
// NOTE: On iOS 10, when a UNUserNotificationCenterDelegate is set,
//       UIApplicationDelegate notification selectors no longer fire.
//       However, this class maintains firing of UIApplicationDelegate selectors if the app did not setup it's
//       own UNUserNotificationCenterDelegate.
//       This ensures we don't produce any side effects to standard iOS API selectors.
//       The callLegacyAppDeletegateSelector selector below takes care of this backwards compatibility handling.

@available(iOS 10.0, *)
class PushEngageUNUserNotificationCenter: NSObject {
    
    public static func setup() {
        swizzleSelector()
        registerDelegate()
    }
    
    private static var delegateUNClass: AnyClass?
    
    // Store an array of all UNUserNotificationCenterDelegate subclasses to iterate over in cases
    // where UNUserNotificationCenterDelegate swizzled methods are not overriden in main AppDelegate
    // But rather in one of the subclasses
    private static var delegateUNSubClasses: [AnyClass]?
    
    // ensures setDelegate: swizzles will never get executed
    // twice for the same delegate object
    // weak reference to avoid retain cycles
    private weak static var previousDelegate: UNUserNotificationCenterDelegate?
    
    private static let selector = PESelectorHelper.shared
    
    private static let viewModel = PushEngage.manager
    
    private static var iOS10work = true
    
    
    private static func swizzleSelector() {
        selector.injectToActualClassAtRuntime(#selector(setPEUNDelegate(delegate:)),
                                              #selector(setter: UNUserNotificationCenter.delegate),
                                              [], PushEngageUNUserNotificationCenter.self,
                                              UNUserNotificationCenter.self)
        
        selector
            .injectToActualClassAtRuntime(#selector(pushEngageRequestAuthorizationWithOptions(options:completionHandler:)),
                                              #selector(UNUserNotificationCenter
                                              .requestAuthorization(options:completionHandler:)),
                                              [], PushEngageUNUserNotificationCenter.self,
                                              UNUserNotificationCenter.self)
        selector
            .injectToActualClassAtRuntime(#selector(pushEngageGetNotificationSettings(completionHandler:)),
                                          #selector(UNUserNotificationCenter
                                          .getNotificationSettings(completionHandler:)),
                                           [], PushEngageUNUserNotificationCenter.self,
                                           UNUserNotificationCenter.self)
    }
    
    private static func registerDelegate() {
        let currentNotificationCenter = UNUserNotificationCenter.current()
        if currentNotificationCenter.delegate == nil {
            
              // Set PEUNUserNotificationCenterDelegate.sharedInstance as a
              // UNUserNotificationCenterDelegate.
              // Note that PEUNUserNotificationCenterDelegate does not contain the methods such as
              // "willPresentNotification" as this assigment triggers setPEUNDelegate which
              //  will attach the selectors to the class at runtime.
             
            currentNotificationCenter.delegate = PEUNUserNotificationCenterDelegate
                                                .sharedInstance()
        } else {
            
             // This handles the case where a delegate may have already been assigned before
             // PushEngage is loaded into memory.
             // This re-assignment triggers setPEUNDelegate providing it with the
             //  existing delegate instance so PushEngage can swizzle in its logic.
            
            let oldDelegate = currentNotificationCenter.delegate
            currentNotificationCenter.delegate = oldDelegate
        }
    }
    
    private static var useCachedUNNotificationSettings = false
    private static weak var cachedUNNotificationSettings: UNNotificationSettings?
    
    @objc dynamic func pushEngageRequestAuthorizationWithOptions(options: UNAuthorizationOptions = [],
                                                                 completionHandler: @escaping (Bool, Error?) -> Void) {
        let block = { (granted: Bool, error: Error?) in
            Self.useCachedUNNotificationSettings = false
            if granted == true {
                Self.viewModel
                    .notificationPermissionStatus
                    .notificationPermissionStatus.value = .granted
            } else {
                Self.viewModel
                    .notificationPermissionStatus
                    .notificationPermissionStatus.value = .denied
            }
            completionHandler(granted, error)
        }
        self.pushEngageRequestAuthorizationWithOptions(options: options, completionHandler: block)
    }
    
    /// if developer haven't set  UNUserNotificationCenterDelegate in the
    /// application below method will call once
    /// if developer have set UNUserNotificationCenterDelegate below method will call twice
    /// this is the expected behaviour of this delegate swizzling. because of this only
    /// developer implementation will called after SDK's implementation.
    @objc dynamic func setPEUNDelegate(delegate: UNUserNotificationCenterDelegate) {
        PELogger.debug(className: String(describing: PushEngageUNUserNotificationCenter.self),
                       message: "PushEngageUNDelegate called: \(delegate)")
        if Self.previousDelegate === delegate {
            self.setPEUNDelegate(delegate: delegate)
            return
        }
        Self.previousDelegate = delegate
        self.hookSelectorToDelegate(for: delegate)
        self.setPEUNDelegate(delegate: delegate)
    }
    
    
    /// This selector hooks and swizzle the implementation of the UNNotificationSettings and update the setting status of the
    /// for the notifications.
    @objc dynamic func pushEngageGetNotificationSettings(completionHandler: @escaping (UNNotificationSettings) -> Void) {
        if Self.cachedUNNotificationSettings != nil
            && Self.useCachedUNNotificationSettings
            && Self.iOS10work {
            completionHandler(Self.cachedUNNotificationSettings!)
            return
        }
        
        let block = { (settings: UNNotificationSettings) in
            Self.cachedUNNotificationSettings = settings
            completionHandler(settings)
        }
        self.pushEngageGetNotificationSettings(completionHandler: block)
    }
    
    /// This function handles to hook all the selector of PushEngageUNUserNotificationCenter
    ///  with the UNUserNotificationCenterDelegate
    private func hookSelectorToDelegate(for delegate: UNUserNotificationCenterDelegate) {
        PELogger.debug(className: String(describing: PushEngageUNUserNotificationCenter.self),
                       message: "\(delegate)")
        Self.delegateUNClass = Self.selector
                                   .getClassWithProtocolInHierarchy(type(of: delegate),
                                    UNUserNotificationCenterDelegate.self)
        if Self.delegateUNClass == nil {
            PELogger.debug(className: String(describing: PushEngageUNUserNotificationCenter.self),
                           message: "protocol in hierarcy is not present")
        } else {
            Self.delegateUNSubClasses = Self.selector.getSubclasses(of: Self.delegateUNClass!)
           
            if Self.delegateUNSubClasses == nil {
                PELogger.debug(className: String(describing: PushEngageUNUserNotificationCenter.self),
                               message: "delegateUNSubClasses not availbale")
            } else {
                Self.selector
                    .injectToActualClassAtRuntime(#selector(
                                                    pushEngageUserNotificationCenter(_:willPresent:withCompletionHandler:)),
                                                  #selector(
                                                    delegate.userNotificationCenter(_:willPresent:withCompletionHandler:)),
                                                  Self.delegateUNSubClasses!,
                                                  PushEngageUNUserNotificationCenter.self, Self.delegateUNClass!)
                Self.selector
                    .injectToActualClassAtRuntime(#selector(
                                                    pushEngageUserNotificationCenter(_:didReceive:withCompletionHandler:)),
                                                  #selector(
                                                    delegate.userNotificationCenter(_:didReceive:withCompletionHandler:)),
                                                  Self.delegateUNSubClasses!,
                                                  PushEngageUNUserNotificationCenter.self, Self.delegateUNClass!)
            }
        }
    }
    
    /// This method invokes when notifications delivered in foreground mode only.
    /// And provide the implementaion to handle the foreground handler of PushEngage.
    @objc dynamic func pushEngageUserNotificationCenter(_ center: UNUserNotificationCenter,
                                                        willPresent notification: UNNotification,
                                                        withCompletionHandler
                                                        completionHandler: @escaping
                                                        (UNNotificationPresentationOptions) -> Void) {
        let parseuserInfo =  notification.request.content.userInfo
        PELogger.debug(className: String(describing: PushEngageUNUserNotificationCenter.self), message: "\(parseuserInfo)")
        if !Utility.isPEPayload(userInfo: parseuserInfo) {
            self.proceedNotificationWithCenter(center, notification: notification, pushEngageCenter: self,
                                               completionHandler: completionHandler)
            if !self.responds(to: #selector(pushEngageUserNotificationCenter(_:willPresent:withCompletionHandler:))) {
                completionHandler(UNNotificationPresentationOptions(rawValue: 7))
            }
            return
        }
        
        Self.viewModel.handleWillPresentNotificationInForeground(with: parseuserInfo) { [weak self] (responseNotification) in
            let notifiyDisplayType = responseNotification
                != nil ? UNNotificationPresentationOptions(rawValue: 7) : UNNotificationPresentationOptions(rawValue: 0)
            self?.finishProcessingNotification(notification: notification,
                                         center: center, displayType: notifiyDisplayType,
                                         completionHandler: completionHandler,
                                         instance: self)
        }
    }
    
    private func proceedNotificationWithCenter(_ center: UNUserNotificationCenter,
                                               notification: UNNotification,
                                               pushEngageCenter: AnyObject?,
                                               completionHandler: @escaping
                                                (UNNotificationPresentationOptions) -> Void) {
        if pushEngageCenter?.responds(to:
                                     #selector(pushEngageUserNotificationCenter(_:willPresent:withCompletionHandler:)))
                                    ?? false {
            pushEngageCenter?.pushEngageUserNotificationCenter(center, willPresent: notification,
                                                  withCompletionHandler: completionHandler)
        } else {
            
            self.oldAppDelegateSelector(notification: notification,
                                               isTextReply: false,
                                               actionIdentifier: nil, userText: nil,
                                               fromPresentNotification: true,
                                               withCompletionHandler: {})
        }
    }
    
    private func finishProcessingNotification(notification: UNNotification,
                                              center: UNUserNotificationCenter,
                                              displayType: UNNotificationPresentationOptions,
                                              completionHandler: @escaping PENotificationCenterCompletionHandler,
                                              instance: PushEngageUNUserNotificationCenter?) {
        let completionHandlerOptions = displayType
        if Self.viewModel.getAppId() != nil {
            Self.viewModel.receivedNotification(with: notification.request.content.userInfo, isOpened: false)
        }
        self.proceedNotificationWithCenter(center, notification: notification,
                                           pushEngageCenter: instance,
                                           completionHandler: completionHandler)
        PELogger.debug(className: String(describing: PushEngageUNUserNotificationCenter.self),
                       message: "finished processing notification" +
                       "and firing completionHandler with option \(completionHandlerOptions)")
        completionHandler(completionHandlerOptions)
    }
    
    
    /// This method or selector invokes when notification has some action on it like
    /// some one clicked the notification or action buttons. And used to process opening notification
    @objc dynamic func pushEngageUserNotificationCenter(_ center: UNUserNotificationCenter,
                                                        didReceive response: UNNotificationResponse,
                                                        withCompletionHandler
                                                        completionHandler: @escaping () -> Void) {
        let parseuserInfo = response.notification.request.content.userInfo
        PELogger.debug(className: String(describing: PushEngageUNUserNotificationCenter.self),
                       message: "\(parseuserInfo)")
        if parseuserInfo[userInfo: PayloadConstants.custom]?[string: PayloadConstants.tag] == nil {
            if self.responds(to: #selector(pushEngageUserNotificationCenter(_:didReceive:withCompletionHandler:))) {
                self.pushEngageUserNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
            } else {
                completionHandler()
            }
            return
        }
        Self.viewModel.processiOS10Open(response: response)
        if self.responds(to: #selector(pushEngageUserNotificationCenter(_:didReceive:withCompletionHandler:))) {
            self.pushEngageUserNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
        } else if !Utility.isDismissEvent(response: response) {
            if let classValue = NSClassFromString("UNTextInputNotificationResponse") {
                let isTextReply = response.isKind(of: classValue)
                let userText: String? = isTextReply ? response.value(forKey: "userText") as? String : nil
                self.oldAppDelegateSelector(notification: response.notification,
                                                   isTextReply: isTextReply,
                                                   actionIdentifier: response.actionIdentifier,
                                                   userText: userText,
                                                   fromPresentNotification: false,
                                                   withCompletionHandler: completionHandler)
            }
        } else {
            completionHandler()
        }
    }
    
    // MARK: - OldAppDelegate selector calling method to achive backward compatiblity.
    
    @available(iOS, deprecated: 9.0)
    private func oldAppDelegateSelector(notification: UNNotification,
                                        isTextReply: Bool,
                                        actionIdentifier: String?,
                                        userText: String?,
                                        fromPresentNotification: Bool,
                                        withCompletionHandler completionHandler: @escaping () -> Void) {
        
        let sharedApp = UIApplication.shared
        guard let delegate = sharedApp.delegate else {
            completionHandler()
            return
        }
        let isCustomAction = actionIdentifier
                            != nil && ("com.apple.UNNotificationDefaultActionIdentifier"
                            != actionIdentifier)
        guard let kindOfClass = NSClassFromString("UNPushNotificationTrigger") else {
            completionHandler()
            return
        }
        let isRemote = notification.request.trigger?.isKind(of: kindOfClass) ?? false
        if isRemote {
            let remoteUserInfo = notification.request.content.userInfo
            if isTextReply
                && delegate
            .responds(to: #selector(delegate
                        .application(
                        _:handleActionWithIdentifier:forRemoteNotification:withResponseInfo:completionHandler:))) {
                let responseInfo = [
                    UIUserNotificationActionResponseTypedTextKey: userText
                ]
                delegate.application?(sharedApp,
                                      handleActionWithIdentifier: actionIdentifier,
                                      forRemoteNotification: remoteUserInfo,
                                      withResponseInfo: responseInfo as [AnyHashable: Any],
                                      completionHandler: {
                    completionHandler()
                })
            } else if isCustomAction && delegate
                         .responds(to: #selector(delegate
                                                .application(
                                                _:handleActionWithIdentifier
                                                 :forRemoteNotification
                                                 :withResponseInfo
                                                 :completionHandler:))) {
                delegate
                .application?(sharedApp,
                                  handleActionWithIdentifier: actionIdentifier,
                                  forRemoteNotification: remoteUserInfo,
                                  completionHandler: {
                    completionHandler()
                })
            } else if delegate
                     .responds(to: #selector(UIApplicationDelegate
                                    .application(_:didReceiveRemoteNotification:fetchCompletionHandler:)))
                        && (!fromPresentNotification
                        || !((notification.request.trigger?.value(forKey: "isContentAvailable") as? NSNumber)?
                        .boolValue ?? false) ) {
                delegate.application?(sharedApp,
                                      didReceiveRemoteNotification:
                                        remoteUserInfo,
                                      fetchCompletionHandler: { _ in
                    completionHandler()
                })
            } else {
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }
    
}
