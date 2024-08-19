//
//  TriggerCampaignManager.swift
//  PushEngage
//
//  Created by Abhishek on 07/04/21.
//

import Foundation

final class TriggerCampaignManager: TriggerCampaignManagerType {
    
    private let userDefaultService: UserDefaultsType
    private let networkService: NetworkRouterType
    private let dataSource: DataSourceType
    
    init(userDefaultService: UserDefaultsType,
         networkService: NetworkRouterType,
         dataSource: DataSourceType) {
        self.userDefaultService = userDefaultService
        self.networkService = networkService
        self.dataSource = dataSource
    }
    
    enum TriggerAlertKeys: String {
        case siteId = "site_id"
        case deviceTokenHash = "device_token_hash"
        case type
        case productId = "product_id"
        case link
        case price
        case variantId = "variant_id"
        case expiryTimestamp = "ts_expires"
        case alertPrice = "alert_price"
        case availability
        case profileId = "profile_id"
        case mrp = "mrp"
    }
    
    func sendTriggerEvent(trigger: TriggerCampaign, completion: ((_ response: Bool,
                                                                  _ error: PEError?) -> Void)?) {
        guard !trigger.campaignName.isEmpty && !trigger.eventName.isEmpty else {
            completion?(false, PEError.invalidInput)
            return
        }
        
        let subscriberData = dataSource.getSubscriptionStatus()

        let triggerModelData = TriggerModelData(siteId: subscriberData.siteID ?? 0,
                                                deviceTokenHash: subscriberData.deviceTokenHash ?? "",
                                                campaignName: trigger.campaignName,
                                                eventName: trigger.eventName,
                                                timezone: Utility.timeZone,
                                                referenceId: trigger.referenceId,
                                                profileId: trigger.profileId,
                                                data: trigger.data)
        let triggerCampaign = TriggerModel(partitionKey: subscriberData.deviceTokenHash ?? "",
                                           data: triggerModelData)
        
        networkService.request(.sendTriggerEvent(triggerCampaign)) { result in
            switch result {
            case .success(let data):
                do {
                    let triggerResponse = try JSONDecoder().decode(TriggerResponse.self,
                                                                   from: data)
                    PELogger.debug(className: String(describing: TriggerCampaignManager.self),
                                   message: "trigger sequenceNumber: - \(triggerResponse.sequenceNumber) \n " +
                                   "trigger ShardId:- \(triggerResponse.shardID)")
                    completion?(true, nil)
                    
                } catch {
                    PELogger.error(className: String(describing: TriggerCampaignManager.self),
                                   message: PEError.parsingError.errorDescription ?? "")
                    completion?(false, PEError.parsingError)
                }
            case .failure(let error):
                PELogger.error(className: String(describing: TriggerCampaignManager.self),
                               message: error.errorDescription ?? "")
                completion?(false, error)
            }
        }
    }
    
    func addAlert(triggerAlert: TriggerAlert, completionHandler: ((_ response: Bool,
                                                                   _ error: PEError?) -> Void)?) {
        let subscriberData = dataSource.getSubscriptionStatus()
    
        
        var requestData: [String: Any] = [:]
        
        requestData[TriggerAlertKeys.siteId.rawValue] = subscriberData.siteID
        requestData[TriggerAlertKeys.deviceTokenHash.rawValue] = subscriberData.deviceTokenHash
        requestData[TriggerAlertKeys.type.rawValue] = self.getTriggerAlertTypeName(from: triggerAlert.type)
        requestData[TriggerAlertKeys.productId.rawValue] = triggerAlert.productId
        requestData[TriggerAlertKeys.link.rawValue] = triggerAlert.link
        requestData[TriggerAlertKeys.price.rawValue] = triggerAlert.price
        if let profileId = triggerAlert.profileId, !profileId.isEmpty {
            requestData[TriggerAlertKeys.profileId.rawValue] = profileId
        }
        if let variantId = triggerAlert.variantId, !variantId.isEmpty {
            requestData[TriggerAlertKeys.variantId.rawValue] = variantId
        }
        if let expiryTimestamp = triggerAlert.expiryDateTime {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
            dateFormatter.timeZone = TimeZone(identifier: "UTC")
            let iso8601String = dateFormatter.string(from: expiryTimestamp)
            requestData[TriggerAlertKeys.expiryTimestamp.rawValue] = iso8601String
        }
        if let alertPrice = triggerAlert.alertPrice {
            requestData[TriggerAlertKeys.alertPrice.rawValue] = alertPrice
        }
        if let availability = self.getTriggerAlertAvailabilityName(from: triggerAlert.availability) {
            requestData[TriggerAlertKeys.availability.rawValue] = availability
        }
        if let mrp = triggerAlert.mrp {
            requestData[TriggerAlertKeys.mrp.rawValue] = mrp
        }
        if let data = triggerAlert.data {
            for (key, value) in data {
                requestData[key] = value
            }
        }
        
        networkService.request(.addAlert(requestData)) { result in
            switch result {
            case .success(let data):
                do {
                    let triggerResponse = try JSONDecoder().decode(NetworkResponse.self,
                                                                   from: data)
                    if triggerResponse.errorCode == 0 {
                        completionHandler?(true, nil)
                    } else {
                        if let errorMessage = triggerResponse.error?.details?.message {
                            completionHandler?(false, PEError.custom(errorMessage))
                        } else {
                            completionHandler?(false, PEError.custom(triggerResponse.errorMessage ?? ""))
                        }
                    }
                    
                } catch {
                    PELogger.error(className: String(describing: TriggerCampaignManager.self),
                                   message: PEError.parsingError.errorDescription ?? "")
                    completionHandler?(false, PEError.parsingError)
                }
            case .failure(let error):
                PELogger.error(className: String(describing: TriggerCampaignManager.self),
                               message: error.errorDescription ?? "")
                completionHandler?(false, error)
            }
        }
    }
    
    private func getTriggerAlertTypeName(from type: TriggerAlertType) -> String {
        switch type {
        case .priceDrop:
            return "price_drop"
        case .inventory:
            return "inventory"
        }
    }
    
    private func getTriggerAlertAvailabilityName(from availability: TriggerAlertAvailabilityType?) -> String? {
        switch availability {
        case .inStock:
            return "inStock"
        case .outOfStock:
            return "outOfStock"
        case .none:
            return nil
        }
    }
    
}
