//
//  TriggerCampaignManager.swift
//  PushEngage
//
//  Created by Abhishek on 07/04/21.
//

import Foundation

class TriggerCampaignManager: TriggerCampaignProtocol {
    
    enum CampaignKeys: String {
        case title = "title"
        case message = "message"
        case notificationUrl = "notification_url"
        case notificationImage = "notification_image"
        case bigImage = "big_image"
        case actions = "actions"
        case data = "data"
        case deviceTokenHash = "device_token_hash"
        case siteId = "site_id"
    }
    
    let userDefaultService: UserDefaultProtocol
    let networkService: NetworkRouter
    
    init(userDefaultService: UserDefaultProtocol,
         networkService: NetworkRouter) {
        self.userDefaultService = userDefaultService
        self.networkService = networkService
    }
    
    func createCampaign(for tigger: TriggerCampaign, completionHandler: TiggerWithBoolCallBack?) {
        var data = [String: Any]()
        
        let titles = tigger.notificationDetails?.compactMap { $0.title?.dict }
        if let titlesValue = titles, titlesValue.count != 0 {
            data[CampaignKeys.title.rawValue] = Utility.getFlatValue(for: titlesValue)
        }
        
        let messages = tigger.notificationDetails?.compactMap { $0.message?.dict }
        if let messagesValue = messages, messagesValue.count != 0 {
            data[CampaignKeys.message.rawValue] = Utility.getFlatValue(for: messagesValue)
        }
        
        let notifiationurls = tigger.notificationDetails?.compactMap { $0.notificationURL.dict }
        if let notificationurlsValue = notifiationurls, notificationurlsValue.count != 0 {
            data[CampaignKeys.notificationUrl.rawValue] = Utility.getFlatValue(for: notificationurlsValue)
        }
        
        let notificationImages = tigger.notificationDetails?.compactMap { $0.notificationImage?.dict }
        if let notificationImagesValue = notificationImages, notificationImagesValue.count != 0 {
            data[CampaignKeys.notificationImage.rawValue] = Utility.getFlatValue(for: notificationImagesValue)
        }
        
        let bigImages = tigger.notificationDetails?.compactMap { $0.bigImage?.dict }
        if let bigImageValue = bigImages, bigImageValue.count != 0 {
            data[CampaignKeys.bigImage.rawValue] = Utility.getFlatValue(for: bigImageValue)
        }
        
        let actions = tigger.notificationDetails?.compactMap { $0.actions?.dict }
        if let actionsValue = actions, actionsValue.count != 0 {
            data[CampaignKeys.actions.rawValue] = Utility.getFlatValue(for: actionsValue)
        }
        
        if let dataValue = tigger.data {
            data[CampaignKeys.data.rawValue] = dataValue
        }
        
        data[CampaignKeys.deviceTokenHash.rawValue] = userDefaultService.subscriberHash
        
        data[CampaignKeys.siteId.rawValue] =  userDefaultService.appId
        
        let finalData: [String: Any] = ["Data": data, "PartitionKey": userDefaultService.subscriberHash]
        
        networkService.request(.triggerCampaigning(eventInfo: finalData)) { (result) in
            switch result {
            case .success(let data):
                do {
                    let triggerResponse = try JSONDecoder().decode(TriggerResponse.self,
                                                                   from: data)
                    PELogger.debug(className: String(describing: TriggerCampaignManager.self),
                                   message: "trigger sequenceNumber: - \(triggerResponse.sequenceNumber) \n " +
                                   "trigger ShardId:- \(triggerResponse.shardID)")
                    completionHandler?(true)
                    
                } catch {
                    PELogger.error(className: String(describing: TriggerCampaignManager.self),
                                   message: PEError.parsingError.errorDescription ?? "")
                    completionHandler?(false)
                }
            case .failure(let error):
                PELogger.error(className: String(describing: TriggerCampaignManager.self),
                               message: error.errorDescription ?? "")
            }
        }
    }
    
}
