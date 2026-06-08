//
//  UNUserNotificationCenterProtocol.swift
//  PushEngage
//
//  Minimal protocol wrapper around the subset of UNUserNotificationCenter
//  used by NotificationSettingsManageriOS10. Exists so that the manager can
//  accept an injected center in init for tests, while production code keeps
//  the existing UNUserNotificationCenter.current() default.
//

import UserNotifications

@available(iOS 10.0, *)
protocol UNUserNotificationCenterProtocol: AnyObject {
    /// Returns the system authorization status. Wrapped so tests can return arbitrary
    /// values — `UNNotificationSettings` has no public init.
    func peGetAuthorizationStatus(completionHandler: @escaping (UNAuthorizationStatus) -> Void)
    func requestAuthorization(options: UNAuthorizationOptions,
                              completionHandler: @escaping (Bool, Error?) -> Void)
}

@available(iOS 10.0, *)
extension UNUserNotificationCenter: UNUserNotificationCenterProtocol {
    func peGetAuthorizationStatus(completionHandler: @escaping (UNAuthorizationStatus) -> Void) {
        getNotificationSettings { settings in
            completionHandler(settings.authorizationStatus)
        }
    }
}
