//
//  AppDelegate.swift
//  PushNotificationDemo
//
//  Created by Abhishek on 20/04/21.
//

import UIKit
import UserNotifications
import PushEngage

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    var window: UIWindow?
    
    override init() {
        super.init()
        // enable method swizzling for the application.
        PushEngage.swizzleInjection(isEnabled: true)
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        self.window = UIWindow()
        // First-launch flow: no App ID configured yet → force the user into
        // SettingsViewController. Once they save and force-quit, the next
        // launch takes the normal Home root path below.
        if !DemoPrefs.shared.isConfigured {
            let settings = SettingsViewController()
            settings.isInitialSetup = true
            self.window?.rootViewController = UINavigationController(rootViewController: settings)
            self.window?.makeKeyAndVisible()
            return true
        }
        self.window?.rootViewController = UINavigationController(rootViewController: HomeViewController())
        self.window?.makeKeyAndVisible()

        if #available(iOSApplicationExtension 10.0, *) {
            UNUserNotificationCenter.current().delegate = self
        }

        PushEngage.setBadgeCount(count: 0)

        // Demo configuration is sourced from DemoPrefs so the user can switch
        // sites/environments at runtime via SettingsViewController. Order
        // matters: setEnvironment must run before setAppID so the SDK picks
        // the right base URLs when it registers.
        PushEngage.setEnvironment(environment: DemoPrefs.shared.environment)
        PushEngage.setAppID(id: DemoPrefs.shared.appId)
        PushEngage.setInitialInfo(for: application,
                                             with: launchOptions)
        
        // Notification handler when notification delivers and app is in foreground.
        PushEngage.setNotificationWillShowInForegroundHandler { notification, completion in
            if notification.contentAvailable == 1 {
                // in case developer failed to set completion handler. After 25 sec handler will call.
                completion(nil)
            } else {
                completion(notification)
            }
        }
        
        // Notification open handler.
        // deeplinking screen
        PushEngage.setNotificationOpenHandler { (result) in
            let additionData = result.notification.additionalData
            print(additionData ?? [:])
            // actionID is nil when the SDK already opened the URL itself
            // (PushEngageAutoHandleDeeplinkURL = YES in Info.plist).
            guard let actionId = result.notificationAction.actionID else {
                return
            }
            if actionId == "Trigger" {
                let triggerViewController = TriggerViewController()
                let navcontroller = application.windows.first?.rootViewController as? UINavigationController
                navcontroller?.pushViewController(triggerViewController, animated: true)
            } else {
                let landingViewController = LandingViewController()
                landingViewController.linkText = actionId
                let navcontroller = application.windows.first?.rootViewController as? UINavigationController
                navcontroller?.pushViewController(landingViewController, animated: true)
            }
        }
        
        PushEngage.enableLogging = true
        
        return true
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
//        Uncomment below line if swizzling is not used
//        PushEngage.willPresentNotification(center: center, notification: notification, completionHandler: completionHandler)
    }

    
    @available(iOSApplicationExtension 10.0, *)
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        print("HOST implemented the notification didRecive notification.")
//        Uncomment below line if swizzling is not used
//        PushEngage.didReceiveRemoteNotification(with: response)
        completionHandler()
    }


    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("HOST didRegisterForRemoteNotificationsWithDeviceToken is implemented device Token: -, \(deviceToken.description)")
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print(token)
//        Uncomment below line if swizzling is not used
//        PushEngage.registerDeviceToServer(with: deviceToken)
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
//    Uncomment below line if swizzling is not used
//        PushEngage.receivedRemoteNotification(application: application, userInfo: userInfo, completionHandler: completionHandler)
    }
}
