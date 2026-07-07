//
//  NotificationDataSource.swift
//  PushEngage
//
//  Created by Abhishek on 25/01/21.
//

import Foundation
import UserNotifications
import UIKit
import PushEngageExtension

protocol NotificationServiceType {
    func handleNotificationPermission(for application: UIApplication, completion: @escaping (_ response: Bool, _ error: PEError?) -> Void)
    func registerToApns(for application: UIApplication?)
    func onNotificationPromptResponse(notification type: Int)
    var notificationPermissionStatus: Variable<PermissionStatus> { get }
}
