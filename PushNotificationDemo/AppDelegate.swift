//
//  AppDelegate.swift
//  PushNotificationDemo
//
//  Created by Abhishek on 20/04/21.
//

import UIKit
import UserNotifications
import PushEngage

@available(iOS 13.0, *)
@available(iOS 13.0, *)
@available(iOS 13.0, *)
@available(iOS 13.0, *)
@available(iOS 13.0, *)
@available(iOS 13.0, *)
@main

// swiftlint:disable all
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    
    override init() {
        super.init()
        // method Swizzing enable for the application.
        PushEngage.swizzleInjection(isEnabled: true)
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        window = UIWindow()
        self.window?.rootViewController = storyboard.instantiateInitialViewController()
        self.window?.makeKeyAndVisible()

        UNUserNotificationCenter.current().delegate = self
        
        application.applicationIconBadgeNumber = 0
        PushEngage.setAppId(key: "2d1b475e-cc73-42a1-8f13-58c944e3")
        PushEngage.startNotificationServices(for: application,
                                             with: launchOptions)
        
        // Notification handler when notification deliver's and app is in foreground.
        
        PushEngage.setNotificationWillShowInForgroundHandler { notification, completion in
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
        
        PushEngage.silentPushHandler { notification , completion  in
            // in case developer failed to set completion handler. After 25 sec handler will call and set.
            completion?(.newData)
        }
        
        PushEngage.enableLogs = true
        
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}

@available(iOSApplicationExtension 13.0, *)
extension AppDelegate : UNUserNotificationCenterDelegate {

    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        print("HOST implemented the notification didRecive notification.")
//        PushEngage.didRecivedRemoteNotification(with: response)
        completionHandler()
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("HOST didRegisterForRemoteNotificationsWithDeviceToken is implemented device Token: -, \(deviceToken)")
//        PushEngage.registerDeviceToServer(with: deviceToken)
    }
}
