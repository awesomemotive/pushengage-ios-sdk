//
//  ApplicationProtocol.swift
//  PushEngage
//
//  Created by Abhishek on 03/02/21.
//

import Foundation
import UIKit

protocol ApplicationServiceType {
    func registerDeviceToServer(with deviceToken: Data)
    func receivedRemoteNotification(application: UIApplication,
                                    userInfo: [AnyHashable: Any],
                                    completionHandler: ((UIBackgroundFetchResult) -> Void)?) -> Bool
    func willPresentNotification(center: UNUserNotificationCenter,
                                 notification: UNNotification,
                                 completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    var notifydelegate: LastNotificationSetDelegate? { get set }
}


