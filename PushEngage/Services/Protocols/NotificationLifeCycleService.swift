//
//  NotificationLifeCycleService.swift
//  PushEngage
//
//  Created by Abhishek on 18/03/21.
//

import Foundation

typealias NotificationCallResponse<T: Codable> = (Result<T, PEError>) -> Void

protocol NotificationLifeCycleService {
    func withRetrynotificationLifecycleUpdate(with action: NotificationLifeAction,
                                              deviceHash: String,
                                              notificationId: String,
                                              actionid: String?,
                                              completionHandler: NotificationCallResponse<Bool>?)
    func withRetrysponseredNotification(with notification: PENotification,
                                        completionHandler: @escaping NotificationCallResponse<SponsoredData>)
    
    func canceled() 
}
