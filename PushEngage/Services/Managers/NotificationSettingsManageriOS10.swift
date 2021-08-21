//
//  NotificationDataManager.swift
//  PushEngage
//
//  Created by Abhishek on 25/01/21.
//

import UserNotifications
import UIKit

@available(iOS 10.0, *)
class NotificationSettingsManageriOS10: NotificationProtocol {
    
    // MARK: - private Enum.
    
    private enum StartRemoteNotifyStatus {
        case isCalled
        case notCalled
        case canCallForground
    }
    
    // MARK: - private handler.
    
    private (set) var notificationPermissionStatus = Variable<PermissonStatus>(.notYetRequested)
    
    // MARK: - private varibale.
    
    private var notificationDefault = NotificationCenter.default
    private var useCachedState: Bool = false
    private var serialQueue: DispatchQueue
    private var nativeNotificatInstance = UNUserNotificationCenter.current()
    private var userDefaultService: UserDefaultProtocol
    private var isStartNotificationCalled: StartRemoteNotifyStatus = .notCalled

    init(userDefaultService: UserDefaultProtocol) {
        self.userDefaultService = userDefaultService
        self.serialQueue = DispatchQueue(label: "com.pushengage.notification.settings.iOS10")
        notificationDefault.addObserver(self,
                                        selector: #selector(willEnterForeground),
                                        name: UIApplication.willEnterForegroundNotification,
                                        object: nil)
    }
    
    deinit {
        notificationDefault.removeObserver(UIApplication.willEnterForegroundNotification)
    }
    
    @objc func willEnterForeground() {
        if isStartNotificationCalled == .isCalled {
            isStartNotificationCalled = .canCallForground
        }
        
        if isStartNotificationCalled == .canCallForground {
            checkPermissionStatus()
        }
    }

    func getNotificationPermissionState() -> PermissonStatus {
        if self.useCachedState {
            return self.notificationPermissionStatus.value
        }
        var returnStatus: PermissonStatus =  .notYetRequested
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

    func getNotificationPermissionState(completionHandler:@escaping ((PermissonStatus) -> Void)) {
        if self.useCachedState {
            completionHandler(self.notificationPermissionStatus.value)
            return
        }
        var permission: PermissonStatus = .notYetRequested
        
        serialQueue.async { [weak self] in
            self?.nativeNotificatInstance.getNotificationSettings { [weak self] (settings) in
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
                self?.useCachedState = true
                completionHandler(permission)
                self?.useCachedState = false
            }
        }
    }

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
        nativeNotificatInstance.requestAuthorization(options: option, completionHandler: responseBlock)
        PELogger.debug(className: String(describing: NotificationSettingsManageriOS10.self),
                       message: "promted Notification authorization request alert.")
    }
    
    @discardableResult
    private func checkPermissionStatus() -> (response: Bool, status: PermissonStatus) {
        let status = getNotificationPermissionState()
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
    
    func startRemoteNotificationService(for application: UIApplication) {
        if isStartNotificationCalled == .notCalled {
            isStartNotificationCalled = .isCalled
        }
        let permissionResult = self.checkPermissionStatus()
        DispatchQueue.main.async { [weak self] in
            
            if permissionResult.response == true {
                self?.showPermissionAlert(custom: "Notification may include alerts, sound and icon badges.",
                                          for: permissionResult.status)
                self?.userDefaultService.ispermissionAlerted = true
                PELogger.debug(className: String(describing: NotificationSettingsManageriOS10.self),
                               message: "Added custom alert for the case where user already granted permission" +
                                        " but device token is not available to sdk because sdk come to app as update.")
                return
            }
            
            switch self?.notificationPermissionStatus.value {
            case .notYetRequested :
                self?.promptAuthorizationForNotification(with: application) { [weak self] response in
                    if self?.userDefaultService.isSwizziled == false {
                        self?.notificationPermissionStatus.value = response ? .granted : .denied
                    }
                    self?.registerToApns(for: application)
                    self?.userDefaultService.ispermissionAlerted = true
                    PELogger.debug(className: String(describing: NotificationSettingsManageriOS10.self),
                                   message: "subscriber responded to the prompted alert.")
                }
                
            case .denied, .granted:
                let rawValue = self?.notificationPermissionStatus.value.rawValue ?? ""
                PELogger.debug(className: String(describing: NotificationSettingsManageriOS10.self),
                               message: "\(rawValue)")
            default:
                PELogger.debug(className: String(describing: NotificationSettingsManageriOS10.self),
                               message: "Notification status is nil")
            }
        }
    }
    
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
    
    func showPermissionAlert(custom message: String, for permissionStatus: PermissonStatus) {
        let alert = UIAlertController(title: "PushNotificationDemo would like to send you " +
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
    
    private func settingsButton() -> UIAlertAction {
        return UIAlertAction(title: "settings", style: .default) { (_) in
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
 }
