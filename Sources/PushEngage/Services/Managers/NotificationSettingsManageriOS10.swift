//
//  NotificationDataManager.swift
//  PushEngage
//
//  Created by Abhishek on 25/01/21.
//

import UserNotifications
import UIKit
import PushEngageExtension

@available(iOS 10.0, *)
final class NotificationSettingsManageriOS10: NotificationServiceType {
    
    private enum StartRemoteNotifyStatus {
        case isCalled
        case notCalled
        case canCallForeground
    }
        
    private (set) var notificationPermissionStatus = Variable<PermissionStatus>(.notYetRequested)
    
    // MARK: - Private varibles.
    private let notificationDefault = NotificationCenter.default
    private let serialQueue: DispatchQueue
    private let nativeNotificattionInstance: UNUserNotificationCenterProtocol
    private var userDefaultService: UserDefaultsType
    private var isStartNotificationCalled: StartRemoteNotifyStatus = .notCalled

    init(userDefaultService: UserDefaultsType,
         notificationCenter: UNUserNotificationCenterProtocol? = nil) {
        self.userDefaultService = userDefaultService
        // Resolve lazily — UNUserNotificationCenter.current() reads the bundle proxy
        // and is unavailable in some unit-test contexts. Tests inject a mock instead.
        self.nativeNotificattionInstance = notificationCenter ?? UNUserNotificationCenter.current()
        self.serialQueue = DispatchQueue(label: "com.pushengage.notification.settings.iOS10")
        notificationDefault.addObserver(self,
                                        selector: #selector(willEnterForeground),
                                        name: UIApplication.willEnterForegroundNotification,
                                        object: nil)
    }
    
    @objc private func willEnterForeground() {
        if isStartNotificationCalled == .isCalled {
            isStartNotificationCalled = .canCallForeground
        }

        if isStartNotificationCalled == .canCallForeground {
            checkPermissionStatus { _, _ in }
        } else {
            // Always check permission status when app enters foreground, regardless of SDK state
            // This ensures we detect permission changes made in iOS Settings
            getNotificationPermissionState { [weak self] currentStatus in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if currentStatus != self.notificationPermissionStatus.value {
                        self.notificationPermissionStatus.value = currentStatus
                    }
                }
            }
        }
    }

    // provides the notification permission in completion block
    func getNotificationPermissionState(completionHandler:@escaping ((PermissionStatus) -> Void)) {
        serialQueue.async { [weak self] in
            self?.nativeNotificattionInstance.peGetAuthorizationStatus { status in
                let permission: PermissionStatus
                switch status {
                case .authorized, .provisional:
                    permission = .granted
                case .denied:
                    permission = .denied
                case .notDetermined:
                    permission = .notYetRequested
                @unknown default:
                    permission = .notYetRequested
                }
                completionHandler(permission)
            }
        }
    }

    /// method prompt's the alert to subcriber weather they want notifications or not and register app
    /// to the enable to get notification's
    func promptAuthorizationForNotification(with application: UIApplication,
                                            completionHandler: ((_ accepted: Bool) -> Void)?) {
        let responseBlock = { (granted: Bool, _ : Error?) in
            DispatchQueue.main.async {
                if completionHandler != nil {
                    completionHandler?(granted)
                }
            }
        }
        let option: UNAuthorizationOptions = [.alert, .badge, .sound]
        nativeNotificattionInstance.requestAuthorization(options: option, completionHandler: responseBlock)
        PELogger.debug(className: String(describing: NotificationSettingsManageriOS10.self),
                       message: "promted Notification authorization request alert.")
    }
    
    /// Reports, via `completion` on the main queue, whether the caller should act:
    /// `response == true` the first time a .granted/.denied status is observed while
    /// `ispermissionAlerted == false`. For .granted the caller registers for remote
    /// notifications silently (no alert); for .denied the caller shows the custom
    /// "enable notifications in Settings" alert.
    private func checkPermissionStatus(completion: @escaping (_ response: Bool, _ status: PermissionStatus) -> Void) {
        getNotificationPermissionState { [weak self] status in
            DispatchQueue.main.async {
                guard let self = self else {
                    completion(false, status)
                    return
                }
                // Always update the observable to ensure permission changes are detected
                if status != self.notificationPermissionStatus.value {
                    self.notificationPermissionStatus.value = status
                }

                switch status {
                case .denied, .granted:
                    completion(self.userDefaultService.ispermissionAlerted == false, status)
                case .notYetRequested:
                    completion(false, status)
                }
            }
        }
    }
    
    /// This method is responsible to start the remote notification services for the application
    func handleNotificationPermission(for application: UIApplication, completion: @escaping (_ response: Bool, _ error: PEError?) -> Void) {
        if isStartNotificationCalled == .notCalled {
            isStartNotificationCalled = .isCalled
        }
        checkPermissionStatus { [weak self] response, status in
            guard let self = self else {
                completion(false, .permissionNotDetermined)
                return
            }

            if response == true {

                self.userDefaultService.ispermissionAlerted = true

                // Permission has already been decided at the OS level — do not show any
                // SDK-drawn UI. For granted, register for remote notifications silently (the
                // device token then arrives via didRegisterForRemoteNotificationsWithDeviceToken
                // and the subscriber is registered). For denied, report the status back through
                // the completion handler so the host can decide how to respond.
                if status == .granted {
                    self.registerToApns(for: application)
                    PELogger.debug(className: String(describing: NotificationSettingsManageriOS10.self),
                                   message: "Notification permission already granted — registering for remote notifications.")
                } else {
                    PELogger.debug(className: String(describing: NotificationSettingsManageriOS10.self),
                                   message: "Notification permission denied.")
                }
                completion(status == .granted, nil)
                return
            }

            switch self.notificationPermissionStatus.value {
            case .notYetRequested:
                self.promptAuthorizationForNotification(with: application) { [weak self] response in
                    if self?.userDefaultService.isSwizzled == false {
                        self?.notificationPermissionStatus.value = response ? .granted : .denied
                    }
                    self?.registerToApns(for: application)
                    completion(response, nil)
                    self?.userDefaultService.ispermissionAlerted = true
                    PELogger.debug(className: String(describing: NotificationSettingsManageriOS10.self),
                                   message: "subscriber responded to the prompted alert.")
                }

            case .denied, .granted:
                let rawValue = self.notificationPermissionStatus.value.rawValue
                PELogger.debug(className: String(describing: NotificationSettingsManageriOS10.self),
                               message: "\(rawValue)")
                completion(self.notificationPermissionStatus.value == .granted, nil)
            }
        }
    }
    
    /// Uses the injected `application` parameter only (not `UIApplication.shared`),
    /// so the body compiles in extension-safe mode without a `#if` guard.
    func registerToApns(for application: UIApplication?) {
        if Utility.isBackgroundFetchEnable() {
            DispatchQueue.main.async {
                application?.registerForRemoteNotifications()
                PELogger.debug(className: String(describing: NotificationSettingsManageriOS10.self),
                               message: "Device Successfully asked user to Register with the APNS Server.")
            }
        } else {
            PELogger.error(className: String(describing: NotificationSettingsManageriOS10.self),
                           message: "Skipping remote notification registration: the 'remote-notification' " +
                                    "background mode is missing from UIBackgroundModes. It is required by the " +
                                    "PushEngage integration — enable it so the device can register with APNs.")
        }
    }

    
    // hanlded for notificationSetting iOS 9.
    func onNotificationPromptResponse(notification type: Int) { }
    
    deinit {
        notificationDefault.removeObserver(UIApplication.willEnterForegroundNotification)
    }
 }
