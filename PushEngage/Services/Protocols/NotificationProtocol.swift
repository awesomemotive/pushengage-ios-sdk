//
//  NotificationDataSource.swift
//  PushEngage
//
//  Created by Abhishek on 25/01/21.
//

import Foundation
import  UserNotifications
import UIKit

protocol NotificationProtocol {
    func startRemoteNotificationService(for application: UIApplication)
    var notificationPermissionStatus: Variable<PermissonStatus> { get }
    func getNotificationPermissionState() -> PermissonStatus
    func registerToApns(for application: UIApplication?)
    func onNotificationPromptResponse(notification type: Int)
}
