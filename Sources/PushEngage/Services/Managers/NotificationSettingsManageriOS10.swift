//
//  NotificationDataManager.swift
//  PushEngage
//
//  Created by Abhishek on 25/01/21.
//

import UserNotifications
import UIKit

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
    private let nativeNotificattionInstance = UNUserNotificationCenter.current()
    private var userDefaultService: UserDefaultsType
    private var isStartNotificationCalled: StartRemoteNotifyStatus = .notCalled

    init(userDefaultService: UserDefaultsType) {
        self.userDefaultService = userDefaultService
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
            checkPermissionStatus()
        } else {
            // Always check permission status when app enters foreground, regardless of SDK state
            // This ensures we detect permission changes made in iOS Settings
            let currentStatus = getNotificationPermissionState()
            if currentStatus != self.notificationPermissionStatus.value {
                self.notificationPermissionStatus.value = currentStatus
            }
        }
    }

    /// method provide the permission status Syncronysly.
    /// - Returns: enum PermissionStatus.
    func getNotificationPermissionState() -> PermissionStatus {
        var returnStatus: PermissionStatus =  .notYetRequested
        let semaphore = DispatchSemaphore(value: 0)
        serialQueue.sync { [weak self] in
            self?.getNotificationPermissionState { (status) in
                returnStatus = status
                semaphore.signal()
            }
        }
        _ = semaphore.wait(timeout: DispatchTime.now() + Double(Int64(100 * NSEC_PER_MSEC)))
        return returnStatus
    }

    // provides the notification permission in completion block
    func getNotificationPermissionState(completionHandler:@escaping ((PermissionStatus) -> Void)) {
        var permission: PermissionStatus = .notYetRequested
        
        serialQueue.async { [weak self] in
            self?.nativeNotificattionInstance.getNotificationSettings { [weak self] (settings) in
                switch settings.authorizationStatus {
                case .authorized:
                    permission = .granted
                case .denied:
                    permission = .denied
                case .notDetermined:
                    permission = .notYetRequested
                default:
                    break
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
    
    /// this method handled the senerio where our sdk goes as the update to the application
    /// that time we are trying to prompt the alert even if notification is already allowed so that
    /// our SDK also know the status of permission and register the user so this will be custom alert will be
    /// shown if func return response value as true.
    @discardableResult
    private func checkPermissionStatus() -> (response: Bool, status: PermissionStatus) {
        let status = getNotificationPermissionState()
        
        // Always update the observable to ensure permission changes are detected
        if status != self.notificationPermissionStatus.value {
            self.notificationPermissionStatus.value = status
        }
        
        switch status {
        case .denied, .granted:
            if self.userDefaultService.ispermissionAlerted == false {
                return (true, status)
            } else {
                return (false, status)
            }
        case .notYetRequested:
            return (false, status)
        }
    }
    
    /// This method is responsible to start the remote notification services for the application
    func handleNotificationPermission(for application: UIApplication, completion: @escaping (_ response: Bool, _ error: PEError?) -> Void) {
        if isStartNotificationCalled == .notCalled {
            isStartNotificationCalled = .isCalled
        }
        let permissionResult = self.checkPermissionStatus()
        DispatchQueue.main.async { [weak self] in
            
            if permissionResult.response == true {
                
                // show the custom permission alert to user case
                // when SDK goes as update to the pre existing Application or already installed.
                
                self?.showPermissionAlert(custom: "Notification may include alerts, sound and icon badges.",
                                          for: permissionResult.status)
                self?.userDefaultService.ispermissionAlerted = true
                PELogger.debug(className: String(describing: NotificationSettingsManageriOS10.self),
                               message: "Added custom alert for the case where user already granted permission" +
                                        " but device token is not available to sdk because sdk come to app as update.")
                completion(permissionResult.status == .granted, nil)
                return
            }
            
            switch self?.notificationPermissionStatus.value {
            case .notYetRequested :
                self?.promptAuthorizationForNotification(with: application) { [weak self] response in
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
                let rawValue = self?.notificationPermissionStatus.value.rawValue ?? ""
                PELogger.debug(className: String(describing: NotificationSettingsManageriOS10.self),
                               message: "\(rawValue)")
                completion(self?.notificationPermissionStatus.value == .granted, nil)
            default:
                PELogger.debug(className: String(describing: NotificationSettingsManageriOS10.self),
                               message: "Notification status is nil")
                completion(false, .permissionNotDetermined)
            }
        }
    }
    
    /// method is responsible for registering the device for the remote notifications.
    func registerToApns(for application: UIApplication?) {
        
        if Utility.isBackgroundFetchEnable() {
            DispatchQueue.main.async {
                application?.registerForRemoteNotifications()
                PELogger.debug(className: String(describing: NotificationSettingsManageriOS10.self),
                               message: "Device Successfully asked user to Register with the APNS Server.")
            }
        } else {
            PELogger.debug(className: String(describing: NotificationSettingsManageriOS10.self),
                             message: "User didn't allow the notificaion. or background fetch" +
                                      "\(Utility.isBackgroundFetchEnable())")
        }
    }
    
    /// Show the custom alert to the subcribers.
    func showPermissionAlert(custom message: String, for permissionStatus: PermissionStatus) {
        let alert = UIAlertController(title: "\(Utility.getApplicationName) Would like to send you " +
                                      "Notifications", message: message, preferredStyle: .alert)
        let allowButton = UIAlertAction(title: "Allow", style: .default) { [weak self] _ in
            self?.notificationPermissionStatus.value = .granted
            self?.registerToApns(for: UIApplication.shared)
        }
        let cancel = UIAlertAction(title: "Don't Allow", style: .destructive) { [weak self] _ in
            self?.notificationPermissionStatus.value = .denied
            self?.registerToApns(for: UIApplication.shared)
        }
        
        let dismiss = UIAlertAction(title: "Dismiss", style: .cancel)
         
        if case .denied = permissionStatus {
            // only available for iOS 10+
            alert.addAction(self.settingsButton())
            alert.title = "Notifications are not allowed"
            alert.message = "Please go to Settings and enable the notification permission."
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
    
    private func settingsButton() -> UIAlertAction {
        return UIAlertAction(title: "Settings", style: .default) { (_) in
            guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
                return
            }
            if UIApplication.shared.canOpenURL(settingsUrl) {
                UIApplication.shared.open(settingsUrl)
            }
        }
    }
    
    // hanlded for notificationSetting iOS 9.
    func onNotificationPromptResponse(notification type: Int) { }
    
    deinit {
        notificationDefault.removeObserver(UIApplication.willEnterForegroundNotification)
    }
 }
