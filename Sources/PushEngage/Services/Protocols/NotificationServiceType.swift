//
//  NotificationDataSource.swift
//  PushEngage
//
//  Created by Abhishek on 25/01/21.
//

import Foundation
import UserNotifications
import UIKit

protocol NotificationServiceType {
    func handleNotificationPermission(for application: UIApplication)
    func getNotificationPermissionState() -> PermissionStatus
    func registerToApns(for application: UIApplication?)
    func onNotificationPromptResponse(notification type: Int)
    var notificationPermissionStatus: Variable<PermissionStatus> { get }
}
