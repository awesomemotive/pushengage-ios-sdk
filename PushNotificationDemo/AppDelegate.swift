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
        self.window?.rootViewController = UINavigationController(rootViewController: PushServiceTestSample())
        self.window?.makeKeyAndVisible()

        if #available(iOSApplicationExtension 10.0, *) {
            UNUserNotificationCenter.current().delegate = self
        }
        
        if #available(iOS 17, *) {
            UNUserNotificationCenter.current().setBadgeCount(0)
        } else {
            application.applicationIconBadgeNumber = 0
        }
        
        PushEngage.setEnvironment(environment: .staging)
        PushEngage.setAppID(id: "3ca8257d-1f40-41e0-88bc-ea28dc6495ef")
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
            if result.notificationAction.actionID == "ShoesScreen" {
                print(additionData ?? [])
                let storyBoard = UIStoryboard(name: "Main", bundle: .main)
                let viewController = storyBoard.instantiateViewController(withIdentifier: "SportViewController")
                let navcontroller = application.windows.first?.rootViewController as? UINavigationController
                navcontroller?.popToRootViewController(animated: true)
                navcontroller?.pushViewController(viewController, animated: true)
            } else if result.notificationAction.actionID == "SalesScreen" {
                let storyBoard = UIStoryboard(name: "Main", bundle: .main)
                let viewController = storyBoard.instantiateViewController(withIdentifier: "NotificationApiTestViewconttoller")
                let navcontroller = application.windows.first?.rootViewController as? UINavigationController
                navcontroller?.popToRootViewController(animated: true)
                navcontroller?.pushViewController(viewController, animated: true)
            } else if result.notificationAction.actionID == "pepay" {
                let storyBoard = UIStoryboard(name: "Main", bundle: .main)
                let viewController = storyBoard.instantiateViewController(withIdentifier: "PEPay")
                let navcontroller = application.windows.first?.rootViewController as? UINavigationController
                navcontroller?.popToRootViewController(animated: true)
                navcontroller?.pushViewController(viewController, animated: true)
            }
        }
        
        // Silent notification Handler.
        PushEngage.silentPushHandler {notification, completion  in
            // in case developer failed to set completion handler. After 25 sec handler will call and set.
            completion?(.newData)
        }
        
        PushEngage.enableLogging = true
        
        return true
    }

    
    @available(iOSApplicationExtension 10.0, *)
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        print("HOST implemented the notification didRecive notification.")
        //        Uncomment below line if swizzling is not used
        //        PushEngage.didReceiveRemoteNotification(with: response)
        completionHandler()
    }


    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("HOST didRegisterForRemoteNotificationsWithDeviceToken is implemented device Token: -, \(deviceToken)")
        //        Uncomment below line if swizzling is not used
        //        PushEngage.registerDeviceToServer(with: deviceToken)
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        //    Uncomment below line if swizzling is not used
        //    PushEngage.receivedRemoteNotification(application: application, userInfo: userInfo, completionHandler: completionHandler)
    }
}
