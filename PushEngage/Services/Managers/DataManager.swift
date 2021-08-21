//
//  DataManager.swift
//  PushEngage
//
//  Created by Abhishek on 25/02/21.
//

import Foundation
import UIKit


class DataManager: DataSourceProtocol {
    
    var userDefault: UserDefaultProtocol
    
    init(userDefault: UserDefaultProtocol) {
        self.userDefault = userDefault
    }
    
    func getSubscriptionData() -> SubscriptionInfo {
        
        let locationCoordinates = userDefault.getObject(for: LocationCoordinates.self,
                                                        key: UserDefaultConstant.locationCoordinates)
        let permisionStatus = userDefault.notificationPermissionState
        let result = permisionStatus == .denied ? (userDefault.isDeleteSubscriberOnDisable ?? false ? 1 : 0) : nil
        var env: String?
        if let certEnv = UIApplication.shared.entitlements.value(forKey: .apsEnvironment)  as? String {
            if certEnv == "development" {
                env = "dev"
            } else if certEnv == "production" {
                env = "prod"
            }
        }
        let subcriptionInfo = SubscriptionInfo(siteID: userDefault.appId,
                                               subscription: Subscription(endpoint: userDefault.deviceToken,
                                                                          projectID: Utility.getBundleIdentifier),
                                               deviceType: "ios",
                                               device: Utility.getDevice,
                                               deviceVersion: Utility.getOSInfo,
                                               deviceModel: Utility.getPhoneName,
                                               deviceManufacturer: "Apple",
                                               latitude: String(format: "%.2f",
                                                                locationCoordinates?.latitude ?? 0),
                                               longitude: String(format: "%.2f",
                                                                 locationCoordinates?.longitude ?? 0),
                                               timezone: Utility.timeOffSet,
                                               language: Locale.current.languageCode,
                                               userAgent: "Apple \(Utility.getPhoneName)",
                                               totalScrWidthHeight: Utility.totalScrWidthHeight,
                                               host: Utility.getBundleIdentifier,
                                               profileID: userDefault.profileID,
                                               isNotificationEnable: result,
                                               certEnv: env)
                                               
        return subcriptionInfo
    }
    
    func getSubscriptionStatus() -> SubscriberDetails {
        let status = SubscriberDetails(siteID: userDefault.appId,
                                      deviceTokenHash: userDefault.subscriberHash)
        return status
    }
    
    func getPostBackSubscriptionData(for notification: PENotification) -> SponsoredPush {
        let sponsoredPush = SponsoredPush(tag: notification.tag,
                                          postback: notification.postback)
        return sponsoredPush
    }
    
    func getSubsriberUpgradeData() -> SubscriberUpgrade {
        let subscription = Subscription(endpoint: userDefault.deviceToken,
                                        projectID: Utility.getBundleIdentifier)
        return SubscriberUpgrade(deviceTokenHash: userDefault.subscriberHash,
                                 subscription: subscription,
                                 siteId: userDefault.appId ?? -100)
    }
}
