//
//  NotificationLifeCycleService.swift
//  PushEngage
//
//  Created by Abhishek on 18/03/21.
//

import Foundation

package typealias NotificationCallResponse<T: Codable> = (Result<T, PEError>) -> Void

package protocol NotificationLifeCycleServiceType {
    func withRetrynotificationLifecycleUpdate(with action: NotificationAction,
                                              deviceHash: String,
                                              notificationId: String,
                                              actionid: String?,
                                              completionHandler: NotificationCallResponse<Bool>?)
    func withRetrysponseredNotification(with notification: PENotification,
                                        completionHandler: @escaping NotificationCallResponse<SponsoredData>)
    
    func cancelled() 
}
