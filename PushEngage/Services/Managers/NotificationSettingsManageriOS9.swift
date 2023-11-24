//
//  NotificationSettingManageriOS10.swift
//  PushEngage
//
//  Created by Abhishek on 24/05/21.
//

import Foundation
import UIKit

@available(iOS, deprecated: 9.0)
final class NotificationSettingsManageriOS9: NotificationServiceType {
    
    // MARK: - private  Enum.
    
    private enum StartRemoteNotifyStatus {
        case isCalled
        case notCalled
        case canCallForground
    }
    
    // MARK: - private handler.
    
    private (set) var notificationPermissionStatus = Variable<PermissionStatus>(.notYetRequested)
    
    // MARK: - private static handler.
    
    static private var notifiationPromptResponseBlock: ((Bool) -> Void)?
    
    // MARK: - private variables
    
    private var notificationDefault = NotificationCenter.default
    private var application: UIApplication?
    private let settings: UIUserNotificationSettings
    private var isStartNotificationCalled: StartRemoteNotifyStatus = .notCalled
    private var userDefaultService: UserDefaultsType
    
    // MARK: - initialization
    
    init(userDefaultService: UserDefaultsType) {
        self.settings = UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
        self.userDefaultService = userDefaultService
        notificationDefault.addObserver(self,
                                        selector: #selector(willEnterForeground),
                                        name: UIApplication.willEnterForegroundNotification,
                                        object: nil)
    }
    
    @objc func willEnterForeground() {
        if isStartNotificationCalled == .isCalled {
            isStartNotificationCalled = .canCallForground
        }
        
        if isStartNotificationCalled == .canCallForground {
            checkPermissionStatus()
        }
    }
    
    @discardableResult
    private func checkPermissionStatus() -> (response: Bool, status: PermissionStatus) {
        let status = self.getNotificationPermissionState()
        switch status {
        case .denied, .granted:
            if self.userDefaultService.ispermissionAlerted == false {
                return (true, status)
            } else {
                self.notificationPermissionStatus.value = status
                return (false, status)
            }
        case .notYetRequested:
            self.notificationPermissionStatus.value = .notYetRequested
            return (false, status)
        }
    }
    
    func handleNotificationPermission(for application: UIApplication) {
        self.application = application
        if isStartNotificationCalled == .notCalled {
            isStartNotificationCalled = .isCalled
        }
        let permissionResult = self.checkPermissionStatus()
        DispatchQueue.main.async { [weak self] in
            
            if permissionResult.response == true {
                self?.showPermissionAlert(custom: "Notification may include alerts, sound and icon badges.",
                                          for: permissionResult.status)
                self?.userDefaultService.ispermissionAlerted = true
                PELogger.debug(className: String(describing: NotificationSettingsManageriOS9.self),
                               message: "Added custom alert for the case where user already granted permission" +
                                        "but device token is not available to sdk because sdk come to app as update.")
                return
            }
            
            switch self?.notificationPermissionStatus.value {
            case .notYetRequested:
                self?.promptForNotification(application) { [weak self] (response: Bool) -> Void in
                    self?.notificationPermissionStatus.value = response ? .granted : .denied
                    self?.registerToApns(for: application)
                }
                self?.userDefaultService.ispermissionAlerted = true
                PELogger.debug(className: String(describing: NotificationSettingsManageriOS9.self),
                               message: "promtedNotification authorization request.")
            case .denied, .granted:
                let rawValue = self?.notificationPermissionStatus.value.rawValue ?? ""
                PELogger.debug(className: String(describing: NotificationSettingsManageriOS9.self),
                               message: "\(rawValue)")
            default:
                PELogger.debug(className: String(describing: NotificationSettingsManageriOS9.self),
                               message: "Notification status is nil")
            }
        }
    }
    
    func getNotificationPermissionState() -> PermissionStatus {
            
        if application?.currentUserNotificationSettings?.types.contains(.alert) == true {
            return .granted
        } else if application?.currentUserNotificationSettings?.types.contains(.alert) == nil {
            return .notYetRequested
        } else {
           return .denied
        }
    }
    
    func registerToApns(for application: UIApplication?) {
        
        if notificationPermissionStatus.value == .granted
           && Utility.isBackgroundFetchEnable() {
            DispatchQueue.main.async {
                application?.registerForRemoteNotifications()
                PELogger.debug(className: String(describing: NotificationSettingsManageriOS9.self),
                               message: "Device Successfully asked user to Register with the APNS Server.")
            }
        } else {
            PELogger.debug(className: String(describing: NotificationSettingsManageriOS9.self),
                             message: "User didn't allow the notificaion. or background fetch" +
                                      "\(Utility.isBackgroundFetchEnable())")
        }
    }
    
    func onNotificationPromptResponse(notification type: Int) {
        let accepted = type > 0
        if Self.notifiationPromptResponseBlock != nil {
            Self.notifiationPromptResponseBlock?(accepted)
            Self.notifiationPromptResponseBlock = nil
        }
    }
    
    private func promptForNotification(_ application: UIApplication,
                                       completionHandler: ((Bool) -> Void)?) {
        let categories = application.currentUserNotificationSettings?.categories
        let setting = UIUserNotificationSettings(types: UIUserNotificationType(rawValue: 7),
                                                 categories: categories)
        application.registerUserNotificationSettings(setting)
        Self.notifiationPromptResponseBlock = completionHandler
    }
    
    func showPermissionAlert(custom message: String, for permissionStatus: PermissionStatus) {
        let alert = UIAlertController(title: "PushNotificationDemo would like to send you " +
                                      "Notifications", message: message, preferredStyle: .alert)
        let allowButton = UIAlertAction(title: "Allow", style: .default) { [weak self] _ in
            self?.notificationPermissionStatus.value = .granted
        }
        let cancel = UIAlertAction(title: "Don't Allow", style: .destructive) { [weak self] _ in
            self?.notificationPermissionStatus.value = .denied
        }
        
        let dismiss = UIAlertAction(title: "Dismiss", style: .cancel)
         
        if case .denied = permissionStatus {
            alert.title = "Notifications are not allowed"
            alert.message = "please go -> to settings and enable the notification to enjoy our updates."
            alert.addAction(dismiss)
            
        } else {
            alert.addAction(allowButton)
            alert.addAction(cancel)
        }
        DispatchQueue.main.async {
            UIApplication.shared.windows.first?
                         .rootViewController?.present(alert, animated: true, completion: nil)
        }
    }
    
    deinit {
        notificationDefault.removeObserver(UIApplication.willEnterForegroundNotification)
    }
    
}
