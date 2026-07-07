//
//  PushEngageAppdelegate.swift
//  PushEngage
//
//  Created by Abhishek on 05/05/21.
//

import Foundation
import UIKit
import PushEngageExtension

/*
 * This class is PushEngageAppdelegate which is swizzled with the UIApplicationDelegate so that
 we can reduce the the integration steps for the host application.
 */

// Hooks into UIApplicationDelegate selectors so the host app doesn't need manual
// integration. The actual notification delivery is handled via UNUserNotificationCenter
// (iOS 10+); these hooks cover token registration, silent pushes, and forwarding to
// the host AppDelegate's original implementations.

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
            
            if appState == .active && isAlertNotification {
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
   
}


