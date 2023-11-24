//
//  PushEngageAppdelegate.swift
//  PushEngage
//
//  Created by Abhishek on 05/05/21.
//

import Foundation
import UIKit

/*
 * This class is PushEngageAppdelegate which is swizzled with the UIApplicationDelegate so that
 we can reduce the the integration steps for the host application.
 */

// This class hooks into the UIApplicationDelegate selectors to receive iOS 9.
//   - UNUserNotificationCenter is used for iOS 10
//   - Orignal implementations are called so other plugins and the developers AppDelegate is still called.

class PushEngageAppDelegate: NSObject {
    
    private static var delegateClass: AnyClass?

    // Store an array of all UIApplicationDelegate subclasses to iterate over in cases
    // where UIApplicationDelegate swizzled methods are not overriden in main AppDelegate
    // But rather in one of the subclasses
    private static var delegateSubclasses: [AnyClass]?
    
    private static let manager = PushEngage.manager
    
    private let selectorHelper = PESelectorHelper.shared
    
    class func getDelegateClass() -> AnyClass? {
        return delegateClass
    }
    
    // Check Selector tag so the SDK would know that Swizzling happened already or not.
    
    @objc dynamic public func pushEngageSELTag() {}
    
    /// this method selector do the first step by swizzling the UIApplication
    /// Delegate selectors with the PushEngageAppDelegate selector.
    /// - Parameter delegate: provide the delegate
    /// you want to swizzle the methods and as this is specifc designed for the UIApplicationDelegate only.

     @objc dynamic public func setPushEngageDelegate(_ delegate: UIApplicationDelegate) {
        PELogger.debug(className: String(describing: PushEngageAppDelegate.self),
                       message: "PushEngageDelegate called: \(delegate)")
        if Self.delegateClass != nil {
            self.setPushEngageDelegate(delegate)
            return
        }
        let newClass = PushEngageAppDelegate.self
        Self.delegateClass = selectorHelper.getClassWithProtocolInHierarchy(type(of: delegate),
                                                                      UIApplicationDelegate.self)
        guard let unWrappedDelegateClass = Self.delegateClass else {
            return
        }
        Self.delegateSubclasses = selectorHelper.getSubclasses(of: unWrappedDelegateClass)
        
        // inject selector for pushEngageApplication(_:didReceiveRemoteNotification:fetchCompletionHandler:)
        selectorHelper
            .injectToActualClassAtRuntime(#selector(self
                                            .pushEngageApplication(_:didReceiveRemoteNotification:fetchCompletionHandler:)),
                                          #selector(delegate
                                            .application(_:didReceiveRemoteNotification:fetchCompletionHandler:)),
                                          Self.delegateSubclasses ?? [], newClass, unWrappedDelegateClass)

        if Utility.lesserThaniOS(version: "10.0") {
            self.swizzleMethodBeforeiOS10(delegate)
        }
        
        // inject selector for pushEngageApplication(_:didRegisterForRemoteNotificationsWithDeviceToken:)
        selectorHelper
            .injectToActualClassAtRuntime(#selector(self
                                            .pushEngageApplication(_:didRegisterForRemoteNotificationsWithDeviceToken:)),
                                          #selector(delegate
                                            .application(_:didRegisterForRemoteNotificationsWithDeviceToken:)),
                                          Self.delegateSubclasses ?? [], newClass, unWrappedDelegateClass)
        
        // inject selector for pushEngageApplication(_:didFailToRegisterForRemoteNotificationsWithError:)
        selectorHelper
            .injectToActualClassAtRuntime(#selector(self
                                            .pushEngageApplication(_:didFailToRegisterForRemoteNotificationsWithError:)),
                                          #selector(delegate
                                            .application(_:didFailToRegisterForRemoteNotificationsWithError:)),
                                          Self.delegateSubclasses ?? [], newClass, unWrappedDelegateClass)
        
        if Utility.lesserThaniOS(version: "10.0") {
            self.swizzleForiOS9(delegate)
        }
        
        self.setPushEngageDelegate(delegate)
    }
    
    @objc dynamic private func pushEngageApplication(_ application: UIApplication,
                                                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PELogger.debug(className: String(describing: ApplicationService.self), message: error.localizedDescription)
    }
    
    /// Selector is fired when Alert has the response from the subscriber either allow or denied.
    /// And that time device gets device token from the APNS and we register to the PushEngage server.
    @objc dynamic private func pushEngageApplication(_ application: UIApplication,
                                                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Self.manager.registerDeviceToServer(with: deviceToken)
        if self.responds(to: #selector(pushEngageApplication(_:didRegisterForRemoteNotificationsWithDeviceToken:))) {
            pushEngageApplication(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
        }
    }
    
    /// Fires when a notification is opened or received while the app is in focus.
    ///   - Also fires when the app is in the background and a notificaiton with content-available=1 is received.
    @objc dynamic private func pushEngageApplication(_ application: UIApplication,
                                                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                                                     fetchCompletionHandler
                                                     completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        let firedExistingSelector = self.responds(to:
                                     #selector(
                                     pushEngageApplication(_:didReceiveRemoteNotification:fetchCompletionHandler:)))
        var initiateBackgroundtask = false
        
        if Self.manager.getAppId() != nil {
            let isAlertNotification = userInfo[userInfo: "aps"]?[userInfo: "alert"] != nil
            let appState = application.applicationState
            
            if Utility.lesserThaniOS(version: "10.0") && appState == .inactive && isAlertNotification {
                Self.manager.receivedNotification(with: userInfo, isOpened: true)
            } else if appState == .active && isAlertNotification {
                Self.manager.receivedNotification(with: userInfo, isOpened: false)
            } else {
                initiateBackgroundtask = Self.manager
                                             .receivedRemoteNotification(application: application,
                                                                        userInfo: userInfo,
                                                                        completionHandler:
                                                                        firedExistingSelector ? nil : completionHandler)
            }
        }
        
        if firedExistingSelector {
            self.pushEngageApplication(application,
                                       didReceiveRemoteNotification: userInfo,
                                       fetchCompletionHandler: completionHandler)
            return
        }
        
        if !initiateBackgroundtask {
            completionHandler(.newData)
        }
    }
   
    // Back work compatiblity
    @available(iOS, deprecated: 9.0)
    func swizzleMethodBeforeiOS10(_ delegate: UIApplicationDelegate) {

        if Self.delegateClass == nil {
            PELogger.debug(className: String(describing: PushEngageAppDelegate.self), message: "delegate class is nil")
        } else {
            selectorHelper
                .injectToActualClassAtRuntime(#selector(
                                              pushEngageLocalNotificationOpend(
                                                _:handleActionWithIdentifier:for:completionHandler:)),
                                              #selector(
                                                delegate.application(_:handleActionWithIdentifier:for:completionHandler:)),
                                              Self.delegateSubclasses ?? [],
                                              PushEngageAppDelegate.self, Self.delegateClass!)
            selectorHelper
                .injectToActualClassAtRuntime(#selector(pushEngageDidRegisterUserNotifications(_:didRegister:)),
                                              #selector(delegate.application(_:didRegister:)),
                                              Self.delegateSubclasses ?? [],
                                              PushEngageAppDelegate.self,
                                              Self.delegateClass!)
        }
    }

    @available(iOS, deprecated: 9.0)
    @objc dynamic func pushEngageLocalNotificationOpend(_ application: UIApplication,
                                                        handleActionWithIdentifier identifier: String?,
                                                        for notification: UILocalNotification,
                                                        completionHandler: @escaping () -> Void) {
        if Self.manager.getAppId() != nil {
            self.operationForLocalActionBased(notification: notification, with: identifier ?? "")
        }
        
        if self
            .responds(to: #selector(pushEngageLocalNotificationOpend(_:handleActionWithIdentifier:for:completionHandler:))) {
            self.pushEngageLocalNotificationOpend(application,
                                                  handleActionWithIdentifier: identifier,
                                                  for: notification,
                                                  completionHandler: completionHandler)
        }
        completionHandler()
    }
    
    @available(iOS, deprecated: 9.0)
    private func operationForLocalActionBased(notification: UILocalNotification,
                                              with identifier: String) {
        
        guard var userInfo = notification.userInfo else {
            return
        }
        
        userInfo[userInfo: PayloadConstants.custom]?[userInfo: "ad"]?
        .updateValue(identifier, forKey: "actionSelected")
        
//        let applicationStateisActive = UIApplication.shared.applicationState == .active
        Self.manager.receivedNotification(with: userInfo, isOpened: true)
        
        // commented just because of the reference
        
//        if !applicationStateisActive {
//            Self.viewModel.handleNotificationOpened(userInfo, with: .taken)
//        }
    }
    
    
//  implemented for the iOS 9 compatible notification settings
    @available(iOS, deprecated: 9.0)
    @objc dynamic func pushEngageDidRegisterUserNotifications(_ application: UIApplication,
                                                              didRegister
                                                              notificationSettings: UIUserNotificationSettings) {
        if Self.manager.getAppId() != nil {
            Self.manager.update(notificationType: Int(notificationSettings.types.rawValue))
        }

        if self.responds(to: #selector(pushEngageDidRegisterUserNotifications(_:didRegister:))) {
            self.pushEngageDidRegisterUserNotifications(application, didRegister: notificationSettings)
        }
    }
    
    @available(iOS, deprecated: 9.0)
    private func swizzleForiOS9(_ delegate: UIApplicationDelegate) {
        if Self.delegateClass == nil {
            PELogger.debug(className: String(describing: PushEngageAppDelegate.self), message: "delegate class is nil")
        } else {
            selectorHelper
                .injectToActualClassAtRuntime(#selector(pushEngageReciveRemoteNotification(_:didReceiveRemoteNotification:)),
                                              #selector(delegate
                                              .application(_:didReceiveRemoteNotification:)),
                                              Self.delegateSubclasses ?? [],
                                              PushEngageAppDelegate.self, Self.delegateClass!)
            selectorHelper
                .injectToActualClassAtRuntime(#selector(pushEngageLocalNotificationOpened(_:didReceive:)),
                                              #selector(delegate.application(_:didReceive:)),
                                              Self.delegateSubclasses ?? [],
                                              PushEngageAppDelegate.self, Self.delegateClass!)

        }
    }
    
    @available(iOS, deprecated: 9.0)
    @objc dynamic func pushEngageLocalNotificationOpened(_ application: UIApplication,
                                                         didReceive notification: UILocalNotification) {
        if Self.manager.getAppId() != nil {
            self.operationForLocalActionBased(notification: notification, with: "__DEFAULT__")
        }
        
        if self.responds(to: #selector(pushEngageLocalNotificationOpened(_:didReceive:))) {
            self.pushEngageLocalNotificationOpened(application, didReceive: notification)
        }
    }
    
    @objc dynamic func pushEngageReciveRemoteNotification(_ application: UIApplication,
                                                          didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
        if Self.manager.getAppId() != nil {
            Self.manager.receivedNotification(with: userInfo, isOpened: true)
        }
        
        if self.responds(to: #selector(pushEngageReciveRemoteNotification(_:didReceiveRemoteNotification:))) {
            self.pushEngageReciveRemoteNotification(application, didReceiveRemoteNotification: userInfo)
        }
    }
}


