//
//  EndPointType.swift
//  PushEngage
//
//  Created by Abhishek on 17/02/21.
//

import Foundation

enum NotificationAction {
    case viewed
    case clicked
}

public typealias Parameters = [String: Any]
typealias NotificationCycleStatus = (hash: String,
                                     notificationId: String,
                                     action: NotificationAction,
                                     id: String?)
typealias UpdateSubcriberInfoList = (hash: String,
                                     info: SubscriptionInfo,
                                     parms: [String: Any])

enum PERouter {
    case addSubscriber((object: SubscriptionInfo, params: [String: Any]))
    case getImage(String)
    case getSubscriberForfields((hash: String, fields: [String]?))
    case checkSubscriberHash(String)
    case setSubscriberAttributes((hash: String, attributes: [String: Any]))
    case addSubscriberAttributes((hash: String, attributes: [String: Any]))
    case getSubscriberAttribute(String)
    case updateSubscriberStatus(SubscriberDetails)
    case addProfile(SubscriberDetails)
    case deleteAttributes((hash: String, attributes: [String]))
    case subscriberUpgrade(SubscriberUpgrade)
    case addTimeZone(SubscriberDetails)
    case addSegments(SubscriberDetails)
    case removeSegment(SubscriberDetails)
    case dynamicSegment(SubscriberDetails)
    case segmentHashArray(SubscriberDetails)
    case removeDynamicSegment(SubscriberDetails)
    case updateSubsciber(UpdateSubcriberInfoList)
    case notificationCycleStatus(NotificationCycleStatus)
    case sponseredNotification(SponsoredPush)
    case subscriberSync(siteKey: String)
    
    // MARK: - Trigger campaign
    case automatedNotification(SubscriberDetails)
    case sendTriggerEvent(TriggerModel)
    case addAlert([String: Any])
    
    // MARK: - Error logging  event
    case errorLogging(SDKServerLogger)
    case sendGoal(SubscriberDetails)
    case none
    
    public func asURLRequest() throws -> URLRequest {
        
        // MARK: - HTTPMethod
        
        var method: HTTPMethod {
             httpMethod()
        }
        
        // MARK: - Parameters
        
        let params: Parameters? = {
             getParameters()
        }()
        
        // MARK: - URL
        
        let url: URL = {
            getURL()
        }()
        
        // MARK: - HTTPHeader
        
        let header: HTTPHeaders = {
            getHeader()
        }()
        
        var urlRequest = URLRequest(url: url, cachePolicy:
                                        .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10.0)
        urlRequest.httpMethod = method.rawValue
        urlRequest.allHTTPHeaderFields = header
        
        // MARK: - HttpBody into JSON.
        
        switch self {
        
        // MARK: - Subscriber APIs.
        
        case .addSubscriber(let value):
            try JSONParameterEncoder.encode(urlRequest: &urlRequest, with: value.object)
            try URLParameterEncoder.encode(urlRequest: &urlRequest, with: value.params)
        case .getSubscriberForfields:
            try URLParameterEncoder.encode(urlRequest: &urlRequest, with: params ?? [:])
        case .setSubscriberAttributes:
            try JSONParameterEncoder.encode(urlRequest: &urlRequest, for: params ?? [:])
        case .addSubscriberAttributes:
            try JSONParameterEncoder.encode(urlRequest: &urlRequest, for: params ?? [:])
        case .deleteAttributes(let info):
            let data = try JSONSerialization.data(withJSONObject: info.attributes)
            urlRequest.httpBody = data
        case .updateSubscriberStatus(let status):
            try JSONParameterEncoder.encode(urlRequest: &urlRequest, with: status)
        case .addProfile(let profileDetails):
            try JSONParameterEncoder.encode(urlRequest: &urlRequest, with: profileDetails)
        case .subscriberUpgrade(let upgradeObject):
            try JSONParameterEncoder.encode(urlRequest: &urlRequest, with: upgradeObject)
        case .addTimeZone(let timeZone):
            try JSONParameterEncoder.encode(urlRequest: &urlRequest, with: timeZone)
        case .addSegments(let segmentInfo):
            try JSONParameterEncoder.encode(urlRequest: &urlRequest, with: segmentInfo)
            try URLParameterEncoder.encode(urlRequest: &urlRequest, with: params ?? [:], isSortedDesc: true)
        case .removeSegment(let removingSegment):
            try JSONParameterEncoder.encode(urlRequest: &urlRequest, with: removingSegment)
            try URLParameterEncoder.encode(urlRequest: &urlRequest, with: params ?? [:], isSortedDesc: true)
        case .dynamicSegment(let segments):
            try JSONParameterEncoder.encode(urlRequest: &urlRequest, with: segments)
        case .segmentHashArray(let segmentArrayHash):
            try JSONParameterEncoder.encode(urlRequest: &urlRequest, with: segmentArrayHash)
        case .removeDynamicSegment(let removeSegment):
            try JSONParameterEncoder.encode(urlRequest: &urlRequest, with: removeSegment)
        case .updateSubsciber(let updatedInfo):
            try JSONParameterEncoder.encode(urlRequest: &urlRequest, with: updatedInfo.info)
            try URLParameterEncoder.encode(urlRequest: &urlRequest, with: updatedInfo.parms)
            
            // MARK: - Notification cycle APIs.
            
        case .notificationCycleStatus:
            try URLParameterEncoder.encode(urlRequest: &urlRequest, with: params ?? [:])
        case .sponseredNotification(let sponserPostBack):
            try JSONParameterEncoder.encode(urlRequest: &urlRequest, with: sponserPostBack)
        
            // MARK: - Trigger Campaign
        case .automatedNotification(let triggerInfo):
            try JSONParameterEncoder.encode(urlRequest: &urlRequest, with: triggerInfo)
            try URLParameterEncoder.encode(urlRequest: &urlRequest, with: params ?? [:], isSortedDesc: true)
        case .sendTriggerEvent(let trigger):
            try JSONParameterEncoder.encode(urlRequest: &urlRequest, with: trigger)
        case .addAlert(let alert):
            try JSONParameterEncoder.encode(urlRequest: &urlRequest, for: alert)
            try URLParameterEncoder.encode(urlRequest: &urlRequest, with: params ?? [:], isSortedDesc: true)

            // MARK: - Error logging
        case .errorLogging(let errorLoggingRequest):
            try JSONParameterEncoder.encode(urlRequest: &urlRequest, with: errorLoggingRequest)
        case .sendGoal(let goal):
            try JSONParameterEncoder.encode(urlRequest: &urlRequest, with: goal)
            try URLParameterEncoder.encode(urlRequest: &urlRequest, with: params ?? [:], isSortedDesc: true)
        default:
            break
        }
        return urlRequest
    }
    
    private func httpMethod() -> HTTPMethod {
        switch self {
        case .addSubscriber,
             .setSubscriberAttributes,
             .updateSubscriberStatus,
             .addProfile,
             .addTimeZone,
             .addSegments,
             .removeSegment,
             .dynamicSegment,
             .segmentHashArray,
             .removeDynamicSegment,
             .automatedNotification,
             .sponseredNotification,
             .sendGoal,
             .addAlert,
             .errorLogging:
            return .post
        case .getImage,
             .getSubscriberForfields,
             .checkSubscriberHash,
             .getSubscriberAttribute,
             .notificationCycleStatus,
             .subscriberSync:
            return .get
        case .deleteAttributes:
            return .delete
        case .updateSubsciber,
             .addSubscriberAttributes,
             .subscriberUpgrade,
             .sendTriggerEvent:
            return .put
        default:
            return .get
        }
    }
    
    private func getParameters() -> Parameters? {
        switch self {
        case .getSubscriberForfields(let fields):
            guard let fields = fields.fields else {
                return nil
            }
            let queryParameterValue = fields.joined(separator: ",")
            let parameter = ["fields": queryParameterValue]
            return parameter
        case .addSubscriberAttributes(let value):
            return value.attributes
        case .setSubscriberAttributes(let value):
            return value.attributes
        case .subscriberUpgrade(let value):
            let parameter = ["subscription": value]
            return parameter
//        case .automatedNotification, .addSegments, .removeSegment, .sendGoal, .addAlert:
//            let parameter = ["swv": NetworkConstants.sdkVersion,
//                             "bv": Utility.getOSInfo]
//            return parameter
        case .notificationCycleStatus(let notificationInfo):
            var parameter: [String: Any] = ["device_token_hash": notificationInfo.hash,
                                            "tag": notificationInfo.notificationId,
                                            "device_type": Utility.getOSInfo,
                                            "swv": NetworkConstants.sdkVersion,
                                            "timezone": Utility.timeZone]
            if let deviceValue = Utility.getDevice {
                parameter.updateValue(deviceValue,
                                      forKey: "device")
            }
            
            if let action = notificationInfo.id {
                parameter.updateValue(action,
                                      forKey: "action")
            }
            return parameter
        default:
            return nil
        }
    }
    
    private func getURL() -> URL {
        var relativePath: String?
        var url = URL(string: NetworkConstants.baseURL)!
        
        switch self {
        case .sendTriggerEvent:
            let url = URL(string: NetworkConstants.triggerCampaignBaseURL)!
            return url
        case .addAlert:
            relativePath = NetworkConstants.addAlert
        case .getImage(let path):
            do {
                let url = try Utility.urlUnWrapper(for: path)
                return url
            } catch let error {
                let userDefaults = DependencyInitialize.getUserDefaults()
                switch userDefaults.environment {
                case .staging:
                    fatalError("URL missing please check in debuging")
                case .production:
                    let error = error as? PEError
                    PELogger.error(className: String(describing: PERouter.self),
                                   message: error?.errorDescription ?? "")
                }
            }
            
        case .addSubscriber:
            relativePath = NetworkConstants.addSubscriberPath
        case .getSubscriberForfields(let fields):
            relativePath = String(format: NetworkConstants.getHashPath, fields.hash)
        case .checkSubscriberHash(let hash):
            relativePath = String(format: NetworkConstants.checkSubscriberHash, hash)
        case .addSubscriberAttributes(let attributeHash):
            relativePath = String(format: NetworkConstants.subscriberAttribute, attributeHash.hash)
        case .setSubscriberAttributes(let attributeHash):
            relativePath = String(format: NetworkConstants.subscriberAttribute, attributeHash.hash)
        case .getSubscriberAttribute(let hash):
            relativePath = String(format: NetworkConstants.getSubscriberAttribute, hash)
        case .updateSubscriberStatus:
            relativePath = NetworkConstants.updateSubscriberStatus
        case .addProfile:
            relativePath = NetworkConstants.addProfileId
        case .deleteAttributes(let deleteInfo):
            relativePath = String(format: NetworkConstants.subscriberAttribute, deleteInfo.hash)
        case .subscriberUpgrade:
            relativePath = NetworkConstants.subscriberUpgrade
        case .addTimeZone:
            relativePath = NetworkConstants.timeZone
        case .addSegments:
            relativePath = NetworkConstants.addSegment
        case .removeSegment:
            relativePath = NetworkConstants.removeSegment
        case .dynamicSegment:
            relativePath = NetworkConstants.dynamicAddSegment
        case .segmentHashArray:
            relativePath = NetworkConstants.segmentHashArray
        case .removeDynamicSegment:
            relativePath = NetworkConstants.dynamicRemoveSegment
        case .automatedNotification:
            relativePath = NetworkConstants.updateTrigger
        case .updateSubsciber(let hash):
            relativePath = String(format: NetworkConstants.updateSubscriber, hash.hash)
        case .subscriberSync(let siteKey):
            url = URL(string: NetworkConstants.cdnurl)!
            relativePath = String(format: NetworkConstants.syncSubscriber, siteKey)
            
            // MARK: - Notification Cycle
            
        case .notificationCycleStatus(let action):
            url = URL(string: NetworkConstants.notifAnalyticURL)!
            if case .viewed = action.action {
                relativePath = NetworkConstants.notificationView
            } else {
                relativePath = NetworkConstants.notificationClicked
            }
        case .sponseredNotification:
            relativePath = NetworkConstants.sponsoreFetch
            
        case .sendGoal:
            relativePath = NetworkConstants.sendGoal
        case .errorLogging:
            url = URL(string: NetworkConstants.errorLoggingBaseURL)!
            relativePath = NetworkConstants.logs
            
        default :
            break
        }
        if let relativePath = relativePath {
            url.appendPathComponent(relativePath)
        }
        return url
    }
    
    private func getHeader() -> HTTPHeaders {
        let userDefaults = DependencyInitialize.getUserDefaults()
        var requestHeaders: HTTPHeaders = Dictionary()

        requestHeaders[NetworkConstants.requestHeaderContentTypeKey] = NetworkConstants.requestHeaderContentTypeValue
        requestHeaders[NetworkConstants.requestHeaderClientKey] = NetworkConstants.requestHeaderClientValue
        requestHeaders[NetworkConstants.requestHeaderClientVersionKey] = Utility.getOSInfo
        requestHeaders[NetworkConstants.requestHeaderSdkVersionKey] = NetworkConstants.sdkVersion
        requestHeaders[NetworkConstants.requestHeaderAppIdKey] = userDefaults.siteKey
        requestHeaders[NetworkConstants.requestHeaderUserAgentKey] = "iOS-\(Utility.getOSInfo)/sdk-\(NetworkConstants.sdkVersion)/app-\(userDefaults.siteKey ?? "")"
        switch self {
        case .getImage,
             .addSubscriber,
             .getSubscriberForfields,
             .checkSubscriberHash,
             .setSubscriberAttributes,
             .addSubscriberAttributes,
             .getSubscriberAttribute,
             .updateSubscriberStatus,
             .addProfile,
             .deleteAttributes,
             .subscriberUpgrade,
             .addTimeZone,
             .addSegments,
             .removeSegment,
             .dynamicSegment,
             .segmentHashArray,
             .removeDynamicSegment,
             .updateSubsciber,
             .notificationCycleStatus,
             .sendGoal,
             .automatedNotification,
             .addAlert,
             .sendTriggerEvent:
            return requestHeaders
        case .sponseredNotification:
            return requestHeaders
        default:
            return Dictionary()
        }
    }
    
}
