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

    override init() {
        super.init()
        // enable method swizzling for the application.
        PushEngage.swizzleInjection(isEnabled: true)
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // First-launch flow: no App ID configured yet → SceneDelegate shows
        // SettingsViewController and the SDK stays uninitialised. Once the user
        // saves and force-quits, the next launch takes the normal path below.
        guard DemoPrefs.shared.isConfigured else {
            return true
        }

        UNUserNotificationCenter.current().delegate = self

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
        PushEngage.setNotificationOpenHandler { [weak self] (result) in
            guard let self = self else { return }
            let additionData = result.notification.additionalData
            print(additionData ?? [:])
            // actionID is nil when the SDK already opened the URL itself
            // (PushEngageAutoHandleDeeplinkURL = YES in Info.plist).
            guard let actionId = result.notificationAction.actionID else {
                return
            }
            if actionId == "Trigger" {
                let triggerViewController = TriggerViewController()
                self.rootNavigationController?.pushViewController(triggerViewController, animated: true)
            } else {
                let landingViewController = LandingViewController()
                landingViewController.linkText = actionId
                self.rootNavigationController?.pushViewController(landingViewController, animated: true)
            }
        }
        
        // Set up custom action handler for in-app messages
        PushEngage.setIAMCustomActionHandler { actionId, parameters in
            print("Received custom action: \(actionId) with parameters: \(parameters)")
            
            switch actionId {
                
            case "accept_action":
                print("Aceept action triggered: \(parameters)")
                
            default:
                // Handle any custom actions not explicitly defined
                if let url = parameters["url"], let urlObj = URL(string: url) {
                    UIApplication.shared.open(urlObj, options: [:], completionHandler: nil)
                }
            }
        }
        
        PushEngage.enableLogging = true
        
        return true
    }
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    private var rootNavigationController: UINavigationController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController as? UINavigationController
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
