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
        self.window?.rootViewController = UINavigationController(rootViewController: HomeViewController())
        self.window?.makeKeyAndVisible()

        if #available(iOSApplicationExtension 10.0, *) {
            UNUserNotificationCenter.current().delegate = self
        }
        
        PushEngage.setBadgeCount(count: 0)
        
        PushEngage.setAppID(id: "Your_App_ID")
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
            if result.notificationAction.actionID == "Trigger" {
                let triggerViewController = TriggerViewController()
                let navcontroller = application.windows.first?.rootViewController as? UINavigationController
                navcontroller?.pushViewController(triggerViewController, animated: true)
            }
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
        print("HOST didRegisterForRemoteNotificationsWithDeviceToken is implemented device Token: -, \(deviceToken.description)")
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print(token)
        //        Uncomment below line if swizzling is not used
        //        PushEngage.registerDeviceToServer(with: deviceToken)
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        //    Uncomment below line if swizzling is not used
        //    PushEngage.receivedRemoteNotification(application: application, userInfo: userInfo, completionHandler: completionHandler)
    }
}
