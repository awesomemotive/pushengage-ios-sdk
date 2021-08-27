//
//  NotificationLifeCycleManager.swift
//  PushEngage
//
//  Created by Abhishek on 19/03/21.
//

import Foundation
import  UIKit

class NotificationLifeCycleManager: NotificationLifeCycleService {
    
    
    let networkRouter: NetworkRouter
    let datasource: DataSourceProtocol
    let userDefault: UserDefaultProtocol
    
    init(networkRouter: NetworkRouter,
         datasource: DataSourceProtocol,
         userDefault: UserDefaultProtocol) {
        self.networkRouter = networkRouter
        self.datasource = datasource
        self.userDefault = userDefault
    }
    
    func withRetrynotificationLifecycleUpdate(with action: NotificationLifeAction,
                                              deviceHash: String,
                                              notificationId: String,
                                              actionid: String?,
                                              completionHandler: NotificationCallResponse<Bool>?) {
        BackgroundTaskExpirationHandler.run(application: UIApplication.shared) { background in
            retry(typeOf: Bool.self, 1, delay: 30) { [weak self] result in
                self?.notificationLifecycleUpdate(with: action, deviceHash: deviceHash, notificationId: notificationId,
                                                  actionid: actionid, completionHandler: result)
            } completion: { result in
                switch result {
                case .success(let response):
                    completionHandler?(.success(response))
                    background.end()
                case.failure(let error):
                    completionHandler?(.failure(error))
                    let name: String = action == .clicked ? .clickCountTrackingFailed
                        : .viewCountTrackingFailed
                    PELogger.logError(message: error.localizedDescription,
                                      name: name, tag: notificationId,
                                      subscriberHash: deviceHash)
                    background.end()
                }
            }
        }
    }
    
    func withRetrysponseredNotification(with notification: PENotification,
                                        completionHandler: @escaping NotificationCallResponse<SponsoredData>) {
        BackgroundTaskExpirationHandler.run(application: UIApplication.shared) { background in
            let sponseredData = datasource.getPostBackSubscriptionData(for: notification)
            retry(typeOf: SponsoredData.self, delay: 1) { [weak self] result in
                self?.sponseredNotification(with: notification, completionHandler: result,
                                            sponseredData: sponseredData)
            } completion: { [weak self] result in
                switch result {
                case .success(let result):
                    completionHandler(.success(result))
                    background.end()
                case .failure(let error):
                    completionHandler(.failure(error))
                    PELogger.logError(message: error.localizedDescription,
                                      name: .notificationRefetchFailed,
                                      tag: sponseredData.tag,
                                      subscriberHash: self?.userDefault.subscriberHash ?? "")
                    background.end()
                 
                }
            }
        }
    }
    
    private func notificationLifecycleUpdate(with action: NotificationLifeAction,
                                             deviceHash: String,
                                             notificationId: String,
                                             actionid: String?,
                                             completionHandler: NotificationCallResponse<Bool>?) {
        let fetchNotificationInfo = (hash: deviceHash,
                                     notificationId: notificationId,
                                     action: action,
                                     id: actionid)
       
        networkRouter.request(.notificationCycleStatus(fetchNotificationInfo)) {  result in
            switch result {
            case .success(let data):
                do {
                    let response = try JSONDecoder().decode(NetworkResponse.self, from: data)
                    if response.error == nil, response.errorCode == 0 {
                        PELogger.debug(className: String(describing: NotificationLifeCycleManager.self),
                                       message: "Notification viewed successfully")
                        completionHandler?(.success(true))
                    } else {
                        PELogger.error(className: String(describing: NotificationLifeCycleManager.self),
                                       message: "\(response.errorMessage ?? "")")
                        completionHandler?(.failure(.notificationUserActionFailed(response.errorMessage)))
                    }
                } catch {
                    PELogger.error(className: String(describing: NotificationLifeCycleManager.self),
                                   message: PEError.parsingError.errorDescription ?? "")
                    completionHandler?(.failure(.parsingError))
                }
            case .failure(let error):
                PELogger.error(className: String(describing: NotificationLifeCycleManager.self),
                               message: error.errorDescription ?? "")
                completionHandler?(.failure(error))
            }
        }
    }
    
    private func sponseredNotification(with notification: PENotification,
                                       completionHandler: @escaping NotificationCallResponse<SponsoredData>,
                                       sponseredData: SponsoredPush) {
        networkRouter.request(.sponseredNotification(sponseredData)) { (result) in
            switch result {
            case .success(let data):
                do {
                    let response = try JSONDecoder().decode(SponsoredResponse.self, from: data)
                    if let data = response.data, response.errorCode == 0 {
                        PELogger.debug(className: String(describing: NotificationLifeCycleManager.self),
                                       message: "Sponserded notification successfull.")
                        completionHandler(.success(data))
                    } else {
                        PELogger.error(className: String(describing: NotificationLifeCycleManager.self),
                                       message: "\(response.errorMessage ?? "")")
                        completionHandler(.failure(.networkResponseFaliure(response.errorCode,
                                                                           response.errorMessage)))
                    }
                } catch {
                    PELogger.error(className: String(describing: NotificationLifeCycleManager.self),
                                   message: PEError.parsingError.errorDescription ?? "")
                    completionHandler(.failure(.parsingError))
                }
            case .failure(let error):
                PELogger.error(className: String(describing: NotificationLifeCycleManager.self),
                               message: error.errorDescription ?? "")
                completionHandler(.failure(error))
            }
        }
    }
    
    private func retry<T: Codable>(typeOf object: T.Type, _ attempts: Int = 1, delay: Double,
                                   task: @escaping (_ completion: @escaping NotificationCallResponse<T>) -> Void,
                                   completion: @escaping NotificationCallResponse<T>) {
        task { [weak self] (response) in
            switch response {
            case .success(let object):
                completion(.success(object))
            case .failure(let error):
                PELogger.debug(className: String(describing: SubscriberServiceManager.self),
                               message: "retrying attempt count:- \(attempts)")
                Utility.retryCheck(error: error) == .allow ?
                attempts >= 1 ? DispatchQueue.global(qos: .utility).asyncAfter(deadline: DispatchTime.now() + delay) {
                    self?.retry(typeOf: object, attempts - 1, delay: delay + Double(delay),
                                task: task, completion: completion) }
                    : completion(.failure(error)) :  completion(.failure(error))
            }
        }
    }
    
    func canceled() {
        networkRouter.cancel()
    }
}
