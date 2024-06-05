//
//  SubscriberDatamanager.swift
//  PushEngage
//
//  Created by Abhishek on 25/02/21.
//

import Foundation
import UIKit

@objc public enum SegmentActions: Int {
    case add
    case remove
    case none
}

final class SubscriberServiceManager: SubscriberServiceType {
    private let datasourceProtocol: DataSourceType
    private let networkRouter: NetworkRouterType
    private var userDefault: UserDefaultsType
    
    init(datasourceProtocol: DataSourceType,
         networkRouter: NetworkRouterType,
         userDefault: UserDefaultsType) {
        self.datasourceProtocol = datasourceProtocol
        self.networkRouter = networkRouter
        self.userDefault = userDefault
    }
    
    private var queryParms: [String: Any] {
        return [.swvKey: NetworkConstants.sdkVersion,
                .isEuKey: userDefault.isGDPR,
                .geoFetch: userDefault.isLocationEnabled]
    }
    
    func sendGoal(goal: Goal, completionHandler: ((_ response: Bool,
                                                   _ error: PEError?) -> Void)?) {
        if goal.name.isEmpty {
            completionHandler?(false, PEError.invalidInput)
            return
        }
        
        var subscriptionData = datasourceProtocol.getSubscriptionStatus()
        subscriptionData.goalName = goal.name
        subscriptionData.goalValue = goal.value
        subscriptionData.goalCount = goal.count
        
        networkRouter.request(.sendGoal(subscriptionData)) { result in
            switch result {
            case .success(let data):
                do {
                    let decodedData = try JSONDecoder().decode(NetworkResponse.self, from: data)
                    if decodedData.error == nil && decodedData.errorCode == 0 && (decodedData.data?.success ?? true) {
                        completionHandler?(true, nil)
                    } else {
                        completionHandler?(false, PEError.networkResponseFailure(decodedData.errorCode,
                                                                                 decodedData.errorMessage))
                    }
                } catch {
                    completionHandler?(false, PEError.parsingError)
                }
            case .failure(let error):
                PELogger.error(className: String(describing: SubscriberServiceManager.self), message: error.errorDescription ?? "")
            }
        }
    }
    
    func addSubscriber(completionHandler: ServiceCallBackObjects<AddSubscriberData>?) {
        let data = (object: datasourceProtocol.getSubscriptionData(),
                    params: queryParms)
        networkRouter.request(.addSubscriber(data)) { [weak self] result in
            switch result {
            case .success(let data) :
                do {
                    let decodedData = try JSONDecoder().decode(AddSubscriberResponse.self, from: data)
                    if let addSubsciberData = decodedData.data, decodedData.errorCode == 0 {
                        self?.userDefault.subscriberHash = addSubsciberData.subscriberHash ?? ""
                        self?.userDefault.isSubscriberDeleted = false
                        self?.userDefault.lastSmartSubscribeDate = Date()
                        completionHandler?(addSubsciberData, nil)
                    } else {
                        self?.userDefault.isSubscriberDeleted = true
                        completionHandler?(nil, .networkResponseFailure(decodedData.errorCode,
                                                                        decodedData.errorMessage))
                    }
                } catch {
                    self?.userDefault.isSubscriberDeleted = true
                    PELogger.error(className: String(describing: SubscriberServiceManager.self),
                                   message: PEError.parsingError.errorDescription ?? "")
                    completionHandler?(nil, .parsingError)
                }
            case .failure(let error):
                self?.userDefault.isSubscriberDeleted = true
                PELogger.error(className: String(describing: SubscriberServiceManager.self),
                               message: error.errorDescription ?? "")
                completionHandler?(nil, error)
            }
        }
    }
    
    func updateSubscriber(completionHandler: ServiceCallBackObjects<NetworkResponse>?) {
        var data = datasourceProtocol.getSubscriptionData()
        data.subscription = nil
        let value = (userDefault.subscriberHash, data, queryParms)
        networkRouter.request(.updateSubsciber(value)) { [weak self] result in
            switch result {
            case .success(let data):
                do {
                    let decodedData = try JSONDecoder().decode(NetworkResponse.self, from: data)
                    decodedData.error == nil && decodedData.errorCode == 0 ? completionHandler?(decodedData, nil)
                        : completionHandler?(nil, .networkResponseFailure(decodedData.errorCode,
                                                                          decodedData.errorMessage))
                } catch {
                    PELogger.error(className: String(describing: SubscriberServiceManager.self),
                                   message: PEError.parsingError.errorDescription ?? "")
                    completionHandler?(nil, .parsingError)
                }
            case .failure(let error):
                PELogger.error(className: String(describing: SubscriberServiceManager.self),
                               message: error.errorDescription ?? "")
                self?.retryFor404(error: error, completion: nil)
            }
        }
    }
    
    func checkSubscriber(completionHandler: ServiceCallBackObjects<CheckSubscriberData>?) {
        networkRouter.request(.checkSubscriberHash(userDefault.subscriberHash)) { [weak self] result in
            switch result {
            case .success(let data):
                PELogger.debug(className: String(describing: SubscriberServiceManager.self), data: data)
                do {
                    let decodedData = try JSONDecoder().decode(CheckSubscriberResponse.self, from: data)
                    decodedData.errorCode == 0 ? completionHandler?(decodedData.data, nil)
                    : completionHandler?(nil, .networkResponseFailure(decodedData.errorCode,
                                                                      decodedData.errorMessage))
                } catch {
                    completionHandler?(nil, .parsingError)
                }
            case .failure(let error):
                PELogger.error(className: String(describing: SubscriberServiceManager.self),
                               message: error.errorDescription ?? "")
                self?.retryFor404(error: error, completion: { result, error in
                    result ? self?.checkSubscriber(completionHandler: completionHandler)
                     : completionHandler?(nil, error)
                })
            }
        }
    }
    
    func getSubscriber(for fields: [String]?, completionHandler: ServiceCallBackObjects<SubscriberDetailsData>?) {
        networkRouter.request(.getSubscriberForfields((userDefault.subscriberHash, fields))) { [weak self] result in
            switch result {
            case .success(let data):
                PELogger.debug(className: String(describing: SubscriberServiceManager.self), data: data)
                do {
                    let decodedObject = try JSONDecoder().decode(SubsciberDetailsResponse.self, from: data)
                    decodedObject.errorCode == 0 ? completionHandler?(decodedObject.data, nil)
                    : completionHandler?(nil, .networkResponseFailure(decodedObject.errorCode,
                                                                      decodedObject.errorMessage))
                } catch {
                    completionHandler?(nil, .parsingError)
                }
            case .failure(let error):
                PELogger.error(className: String(describing: SubscriberServiceManager.self),
                               message: error.errorDescription ?? "")
                self?.retryFor404(error: error, completion: { result, error in
                    result ? self?.getSubscriber(for: fields, completionHandler: completionHandler)
                        : completionHandler?(nil, error)
                })
            }
        }
    }
    
    func setSubscriberAttributes(attributes: Parameters, completionHandler: SubscriberBoolCallBack?) {
        networkRouter.request(.setSubscriberAttributes((userDefault.subscriberHash, attributes))) { [weak self] (result) in
            switch result {
            case .success(let data):
                do {
                    let decodedData = try JSONDecoder().decode(NetworkResponse.self, from: data)
                    decodedData.error == nil && decodedData.errorCode == 0 ?
                    completionHandler?(true, nil) :
                    completionHandler?(false, PEError.networkResponseFailure(decodedData.errorCode,
                                                                             decodedData.errorMessage))
                } catch {
                    completionHandler?(false, PEError.parsingError)
                }
            case .failure(let error):
                self?.retryFor404(error: error, completion: { result, error in
                    result ? self?.setSubscriberAttributes(attributes: attributes, completionHandler: completionHandler)
                        : completionHandler?(false, error)
                })
            }
        }
    }
    
    func addSubscriberAttributes(attributes: Parameters, completionHandler: SubscriberBoolCallBack?) {
        networkRouter.request(.addSubscriberAttributes((userDefault.subscriberHash, attributes))) { [weak self] (result) in
            switch result {
            case .success(let data):
                do {
                    let decodedData = try JSONDecoder().decode(NetworkResponse.self, from: data)
                    decodedData.error == nil && decodedData.errorCode == 0 ?
                    completionHandler?(true, nil) :
                    completionHandler?(false, PEError.networkResponseFailure(decodedData.errorCode,
                                                                             decodedData.errorMessage))
                } catch {
                    completionHandler?(false, PEError.parsingError)
                }
            case .failure(let error):
                self?.retryFor404(error: error, completion: { result, error in
                    result ? self?.addSubscriberAttributes(attributes: attributes, completionHandler: completionHandler)
                        : completionHandler?(false, error)
                })
            }
        }
    }

    func getAttribute(completionHandler: @escaping ServiceCallBack) {
        networkRouter.request(.getSubscriberAttribute(userDefault.subscriberHash)) { [weak self] (result) in
            switch result {
            case .success(let data):
                do {
                    let jsonDic = try Utility.convert(data: data)
                    if let data = jsonDic?[ParsingConstants.data] as? Parameters,
                       jsonDic?["error_code"] as? Int == 0 {
                        completionHandler(data, nil)
                    } else {
                        let errorCode = jsonDic?["error_code"] as? Int
                        let errorMessage = jsonDic?["error_message"] as? String
                        completionHandler(nil, .networkResponseFailure(errorCode,
                                                                       errorMessage ?? "attribute not available"))
                    }
                    PELogger.debug(className: String(describing: SubscriberServiceManager.self),
                                   message: "\(String(describing: jsonDic))")
                } catch {
                    completionHandler(nil, .parsingError)
                }
                
            case .failure(let error):
                PELogger.error(className: String(describing: SubscriberServiceManager.self),
                               message: error.errorDescription ?? "")
                self?.retryFor404(error: error, completion: { result, error in
                    result ? self?.getAttribute(completionHandler: completionHandler)
                        : completionHandler(nil, error)
                })
            }
        }
    }
    
    func updateSubscriberStatus(status: Int,
                                completionHandler: SubscriberBoolCallBack?) {
        var bodyData = datasourceProtocol.getSubscriptionStatus()
        bodyData.isUnSubscribed = status
        if status == 1 {
            bodyData.notificationDisabled =  userDefault.isDeleteSubscriberOnDisable ?? false
        }
        networkRouter.request(.updateSubscriberStatus(bodyData)) { (result) in
            switch result {
            case .success(let data):
                do {
                    let decodedData = try JSONDecoder().decode(NetworkResponse.self, from: data)
                    decodedData.error == nil && decodedData.errorCode == 0 ?
                        completionHandler?(true, nil) :
                        completionHandler?(false, .networkResponseFailure(decodedData.errorCode,
                                                                          decodedData.errorMessage))
                } catch {
                    PELogger.error(className: String(describing: SubscriberServiceManager.self),
                                   message: PEError.parsingError.errorDescription ?? "")
                    completionHandler?(false, .parsingError)
                }
            case .failure(let error):
                PELogger.error(className: String(describing: SubscriberServiceManager.self),
                               message: error.errorDescription ?? "")
                completionHandler?(false, error)
            }
        }
        
    }
    
    func addProfile(id: String,
                    completionHandler: SubscriberBoolCallBack?) {
        var profileDetails = datasourceProtocol.getSubscriptionStatus()
        profileDetails.profileId = id
        networkRouter.request(.addProfile(profileDetails)) { [weak self] (result) in
            switch result {
            case .success(let data):
                do {
                    let decodedData = try JSONDecoder().decode(NetworkResponse.self, from: data)
                    decodedData.error == nil && decodedData.errorCode == 0 ?
                    completionHandler?(true, nil)
                    : completionHandler?(false, .networkResponseFailure(decodedData.errorCode,
                                                                        decodedData.errorMessage))
                } catch {
                    PELogger.error(className: String(describing: SubscriberServiceManager.self),
                                   message: PEError.parsingError.errorDescription ?? "")
                    completionHandler?(false, .parsingError)
                }
            case .failure(let error):
                PELogger.error(className: String(describing: SubscriberServiceManager.self),
                               message: error.errorDescription ?? "")
                self?.retryFor404(error: error, completion: { result, error in
                    result ? self?.addProfile(id: id, completionHandler: completionHandler)
                        : completionHandler?(false, error)
                })
            }
        }
    }
    
    func deleteAttribute(with values: [String],
                         completionHandler: SubscriberBoolCallBack?) {
        networkRouter.request(.deleteAttributes((userDefault.subscriberHash, values))) { [weak self] (result) in
            switch result {
            case .success(let data):
                do {
                    let decodedData = try JSONDecoder().decode(NetworkResponse.self, from: data)
                    decodedData.error == nil && decodedData.errorCode == 0
                    ? completionHandler?(true, nil)
                    : completionHandler?(false, .networkResponseFailure(decodedData.errorCode,
                                                                        decodedData.errorMessage))
                } catch {
                    PELogger.error(className: String(describing: SubscriberServiceManager.self),
                                   message: PEError.parsingError.errorDescription ?? "")
                    completionHandler?(false, .parsingError)
                }
            case .failure(let error):
                PELogger.error(className: String(describing: SubscriberServiceManager.self),
                               message: error.errorDescription ?? "")
                self?.retryFor404(error: error, completion: { result, error in
                    result ? self?.deleteAttribute(with: values, completionHandler: completionHandler)
                        : completionHandler?(false, error)
                })
            }
        }
    }
    
    
    func upgradeSubscription(completion: SubscriberBoolCallBack?) {
        
        let value = datasourceProtocol.getSubsriberUpgradeData()
        networkRouter.request(.subscriberUpgrade(value)) { [weak self] (result) in
            switch result {
            case .success(let data) :
                do {
                    let decodedData = try JSONDecoder().decode(NetworkResponse.self, from: data)
                    decodedData.errorCode == 0 ? completion?(true, nil)
                        : completion?(false, .networkResponseFailure(decodedData.errorCode,
                                                                     decodedData.errorMessage))
                } catch {
                    PELogger.error(className: String(describing: SubscriberServiceManager.self),
                                   message: PEError.parsingError.errorDescription ?? "")
                    completion?(false, .parsingError)
                }
            case .failure(let error):
                PELogger.error(className: String(describing: SubscriberServiceManager.self),
                               message: error.errorDescription ?? "")
                self?.retryFor404(error: error, completion: nil)
            }
        }
    }
    
    func update(segments: [String], action: SegmentActions ,
                completionHandler: SubscriberBoolCallBack?) {
        var subscriberInfo = datasourceProtocol.getSubscriptionStatus()
        subscriberInfo.deviceType = "ios"
        subscriberInfo.segment = segments
        var route = PERouter.none
        switch action {
        case .remove:
            route = .removeSegment(subscriberInfo)
        case .add:
            route = .addSegments(subscriberInfo)
        default:
            break
        }
        networkRouter.request(route) { [weak self] (result) in
            switch result {
            case .success(let data):
                do {
                    let decodedData = try JSONDecoder().decode(NetworkResponse.self, from: data)
                    decodedData.error == nil && decodedData.errorCode == 0 ?
                    completionHandler?(true, nil)
                    : completionHandler?(false, .networkResponseFailure(decodedData.errorCode,
                                                                        decodedData.errorMessage))
                } catch {
                    PELogger.error(className: String(describing: SubscriberServiceManager.self),
                                   message: PEError.parsingError.errorDescription ?? "")
                    completionHandler?(false, .parsingError)
                }
            case .failure(let error):
                PELogger.error(className: String(describing: SubscriberServiceManager.self),
                               message: error.errorDescription ?? "")
                self?.retryFor404(error: error) { result, error in
                    result ? self?.update(segments: segments,
                                          action: action,
                                          completionHandler: completionHandler) :
                         completionHandler?(false, error)
                }
            }
        }
    }
    
    func update(dynamic segmentInfo: [Parameters],
                completionHandler: SubscriberBoolCallBack?) {
        do {
            let data = try JSONSerialization.data(withJSONObject: segmentInfo, options: .prettyPrinted)
            let encodedSegment = try JSONDecoder().decode([Segment].self, from: data)
            var dynamicInfo = datasourceProtocol.getSubscriptionStatus()
            dynamicInfo.segments = encodedSegment
            dynamicInfo.deviceToken = nil
            dynamicInfo.deviceTokenHash = userDefault.subscriberHash
            networkRouter.request(.dynamicSegment(dynamicInfo)) { [weak self] (result) in
                switch result {
                case .success(let data):
                    do {
                        let decodedData = try JSONDecoder().decode(NetworkResponse.self, from: data)
                        decodedData.error == nil && decodedData.errorCode == 0 ?
                        completionHandler?(true, nil)
                        : completionHandler?(false, .networkResponseFailure(decodedData.errorCode,
                                                                            decodedData.errorMessage))
                    } catch {
                        PELogger.error(className: String(describing: SubscriberServiceManager.self),
                                       message: PEError.parsingError.errorDescription ?? "")
                        completionHandler?(false, .parsingError)
                    }
                case .failure(let error):
                    PELogger.error(className: String(describing: SubscriberServiceManager.self),
                                   message: error.errorDescription ?? "")
                    self?.retryFor404(error: error) { result, error in
                        result ? self?.update(dynamic: segmentInfo,
                                              completionHandler: completionHandler)
                            : completionHandler?(false, error)
                    }
                }
            }
        } catch let error {
            PELogger.error(className: String(describing: SubscriberServiceManager.self),
                           message: error.localizedDescription)
            completionHandler?(false, .parsingError)
        }
        
    }
    
    func segmentHashArray(for segmentId: Int,
                          completionHandler: SubscriberBoolCallBack?) {
        var segmentHashArrayInfo = datasourceProtocol.getSubscriptionStatus()
        segmentHashArrayInfo.segmentId = segmentId
        networkRouter.request(.segmentHashArray(segmentHashArrayInfo)) { [weak self] (result) in
            switch result {
            case .success(let data):
                do {
                    let decodedData = try JSONDecoder().decode(NetworkResponse.self, from: data)
                    decodedData.error == nil && decodedData.errorCode == 0 ?
                    completionHandler?(true, nil) :
                    completionHandler?(false, .networkResponseFailure(decodedData.errorCode,
                                                                      decodedData.errorMessage))

                } catch {
                    PELogger.error(className: String(describing: SubscriberServiceManager.self),
                                   message: PEError.parsingError.errorDescription ?? "")
                    completionHandler?(false, .parsingError)
                }
            case .failure(let error):
                PELogger.error(className: String(describing: SubscriberServiceManager.self),
                               message: error.errorDescription ?? "")
                self?.retryFor404(error: error) { result, error in
                    result ? self?.segmentHashArray(for: segmentId,
                                                    completionHandler: completionHandler)
                        : completionHandler?(false, error)
                }
            }
        }
    }
    
    func automatedNotification(status: TriggerStatusType,
                       completionHandler: SubscriberBoolCallBack?) {
        var triggerStatusInfo = datasourceProtocol.getSubscriptionStatus()
        triggerStatusInfo.triggerStatus = status.rawValue
        networkRouter.request(.automatedNotification(triggerStatusInfo)) { [weak self] (result) in
            switch result {
            case .success(let data):
                do {
                    let decodedData = try JSONDecoder().decode(NetworkResponse.self, from: data)
                    decodedData.error == nil && decodedData.errorCode == 0 ?
                    completionHandler?(true, nil)
                    : completionHandler?(false, .networkResponseFailure(decodedData.errorCode,
                                                                      decodedData.errorMessage))
                } catch {
                    PELogger.error(className: String(describing: SubscriberServiceManager.self),
                                   message: PEError.parsingError.errorDescription ?? "")
                    completionHandler?(false, .parsingError)
                }
            case .failure(let error):
                PELogger.error(className: String(describing: SubscriberServiceManager.self),
                               message: error.errorDescription ?? "")
                self?.retryFor404(error: error) { result, error in
                    result ? self?.automatedNotification(status: status, completionHandler: completionHandler)
                        : completionHandler?(false, error)
                }
            }
        }
    }
}

extension SubscriberServiceManager {
    
    func syncSiteInfo(for siteKey: String,
                      completionHandler: ServiceCallBackObjects<SyncAPIData>?) {
        networkRouter.request(.subscriberSync(siteKey: siteKey)) { [weak self] result in
            switch result {
            case .success(let data):
                do {
                    let object = try JSONDecoder().decode(SyncAPIResponse.self, from: data)
                    if object.errorCode == 0 {
                        PELogger.debug(className: String(describing: SubscriberServiceManager.self),
                                       message: "successfully api call for sync.")
                        self?.userDefault.save(object: object.data,
                                               for: UserDefaultConstant.pushEngageSyncApi)
                        completionHandler?(object.data, nil)
                    } else {
                        completionHandler?(nil, .networkResponseFailure(object.errorCode,
                                                                        object.errorMessage))
                    }
                } catch {
                    completionHandler?(nil, .parsingError)
                }
            case .failure(let error):
                completionHandler?(nil, error)
            }
        }
    }
    
    private func retryFor404(error: PEError,
                             completion: ((Bool, PEError?) -> Void)?) {
        if case .invalidStatusCode(_, let code) = error, code == 404 {
            
            self.addSubscriberToServer { [weak self] error in
                if let error = error {
                    completion?(false, error)
                    if Utility.retryCheck(error: error) == .allow {
                        BackgroundTaskExpirationHandler.run(application: UIApplication.shared) { background in
                            DispatchQueue.global(qos: .background).async {
                                self?.retry(3, delay: 300) { [weak self] result in
                                    self?.addSubscriberToServer(completion: result)
                                } completion: { error in
                                    PELogger.debug(className: String(describing: SubscriberServiceManager.self),
                                                   message: error != nil ? "failed to add subcriber" : "successfull added")
                                    background.end()
                                }
                            }
                        }
                    } else {
                        PELogger.debug(className: String(describing: SubscriberServiceManager.self),
                                       message: "add subscriber retry api is not requried.")
                    }
                } else {
                    completion?(true, nil)
                }
            }
        } else {
            completion?(false, error)
        }
    }
    
    func retry(_ attempts: Int = 3, delay: Double,
               task: @escaping (_ completion: @escaping ((PEError?) -> Void)) -> Void,
               completion: @escaping ((PEError?) -> Void)) {
        task { [weak self] (error) in
            if let error = error {
                PELogger.debug(className: String(describing: SubscriberServiceManager.self),
                               message: "retrying attempt count:- \(attempts)")
                Utility.retryCheck(error: error) == .allow ?
                    attempts > 1 ? DispatchQueue.global(qos: .utility).asyncAfter(deadline: DispatchTime.now() + delay) {
                        self?.retry(attempts - 1, delay: delay,
                                    task: task, completion: completion) }
                    : completion(error) :  completion(error)
            } else {
                completion(nil)
            }
        }
    }
}

extension SubscriberServiceManager {
    
    func retryAddSubscriberProcess(completion: ((PEError?) -> Void)?) {
        BackgroundTaskExpirationHandler.run(application: UIApplication.shared) { [weak self] background in
            retry(3, delay: 300) { [weak self] result in
                self?.addSubscriberToServer(completion: result)
            } completion: { error in
                completion?(error)
                background.end()
            }
        }
    }
    
    private func addSubscriberToServer(completion: ((PEError?) -> Void)?) {
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            if self?.userDefault.getObject(for: SyncAPIData.self,
                                           key: UserDefaultConstant.pushEngageSyncApi) == nil {
                guard let key = self?.userDefault.siteKey else {
                    self?.userDefault.isSubscriberDeleted = true
                    completion?(.siteKeyNotAvailable)
                    return
                }
                
                self?.syncSiteInfo(for: key) { _, error in
                    error != nil ? completion?(error)
                        :  self?.startAddSubscriberOperation(completion: completion)
                }
            } else {
                self?.startAddSubscriberOperation(completion: completion)
            }
        }
    }
    
    private func startAddSubscriberOperation(completion: ((PEError?) -> Void)? ) {
        let siteStatus = SiteStatus(rawValue: userDefault.siteStatus)
        if siteStatus != .active {
            userDefault.isSubscriberDeleted = true
            PELogger.debug(className: String(describing: SubscriberServiceType.self),
                           message: "site status is not active.")
            completion?(.stiteStatusNotActive)
            return
        }
        if userDefault.notificationPermissionState == .notYetRequested {
            PELogger.debug(className: String(describing: SubscriberServiceType.self),
                           message: "permission is not determined.")
            completion?(.permissionNotDetermined)
            return
        }
        let permissionStatus = userDefault.notificationPermissionState
        if permissionStatus == .granted {
            self.addSubscriber(completionHandler: { response, error in
                completion?(response != nil ? nil : error)
            })
            PELogger.debug(className: String(describing: SubscriberServiceManager.self),
                           message: "subscriber add process is initiated.....")
            return
        }
        if userDefault.isDeleteSubscriberOnDisable == false {

            self.addSubscriber(completionHandler: { response, error in
                completion?(response != nil ? nil : error)
            })
        } else {
            self.userDefault.isSubscriberDeleted = true
            completion?(nil)
        }
    }
    
    func updateSettingPermission(status: PermissionStatus) {
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        self.syncSiteInfo(for: userDefault.siteKey ?? "") { _, _ in
            dispatchGroup.leave()
        }
        _ = dispatchGroup.wait(timeout: DispatchTime.now() + NetworkConstants.requestTimeout)
        let permissionStatus = status == .granted ? 0 : 1
        self.updateSubscriberStatus(status: permissionStatus) { [weak self] (_, error) in
            if let error = error {
                self?.retryFor404(error: error, completion: nil)
            } else {
                self?.updateSubsciberDeleteStatus()
            }
        }
    }
    
    private func updateSubsciberDeleteStatus() {
        let status = userDefault.notificationPermissionState
        let result = status == .denied && userDefault.isDeleteSubscriberOnDisable == true
        userDefault.isSubscriberDeleted = result ? true : false
    }
}
