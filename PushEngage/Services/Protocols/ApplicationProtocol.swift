//
//  ApplicationProtocol.swift
//  PushEngage
//
//  Created by Abhishek on 03/02/21.
//

import Foundation
import UIKit

protocol ApplicationProtocol {
    func registerDeviceToServer(with deviceToken: Data)
    func recivedRemoteNotification(application: UIApplication,
                                   userInfo: [AnyHashable: Any],
                                   completionHandler: ((UIBackgroundFetchResult) -> Void)?) -> Bool
    var notifydelegate: LastNotificationSetDelagate? { get set }

}


