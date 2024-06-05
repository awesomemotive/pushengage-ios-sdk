//
//  DataManager.swift
//  PushEngage
//
//  Created by Abhishek on 25/02/21.
//

import Foundation
import UIKit

/// `DataManager` class provides methods to retrieve subscription and subscriber details, as well as handling sponsored push notifications.
final class DataManager: DataSourceType {
    
    /// The UserDefaults manager responsible for handling data persistence.
    private let userDefaults: UserDefaultsType
    
    /// Initializes the `DataManager` with the provided `UserDefaultsType` instance.
    /// - Parameter userDefault: An instance conforming to `UserDefaultsType` used for data storage and retrieval.
    init(userDefault: UserDefaultsType) {
        self.userDefaults = userDefault
    }
    
    func getSubscriptionData() -> SubscriptionInfo {
        
        let permisionStatus = userDefaults.notificationPermissionState
        let result = permisionStatus == .denied ? (userDefaults.isDeleteSubscriberOnDisable ?? false ? 1 : 0) : nil
        var env: String?
        if let certEnv = UIApplication.shared.entitlements.value(forKey: .apsEnvironment) as? String {
            if certEnv == "development" {
                env = "dev"
            } else if certEnv == "production" {
                env = "prod"
            }
        }
        let subscriptionInfo = SubscriptionInfo(siteID: userDefaults.appId,
                                               subscription: Subscription(endpoint: userDefaults.deviceToken,
                                                                          projectID: Utility.getBundleIdentifier),
                                               deviceType: "ios",
                                               device: Utility.getDevice,
                                               deviceVersion: Utility.getOSInfo,
                                               deviceModel: Utility.getPhoneName,
                                               deviceManufacturer: "Apple",
                                               timezone: Utility.timeZone,
                                               language: Locale.current.languageCode,
                                               userAgent: "Apple \(Utility.getPhoneName)",
                                               totalScreenWidthHeight: Utility.totalScrWidthHeight,
                                               host: Utility.getBundleIdentifier,
                                               profileID: userDefaults.profileID,
                                               isNotificationEnable: result,
                                               certEnv: env)
                                               
        return subscriptionInfo
    }
    
    func getSubscriptionStatus() -> SubscriberDetails {
        let status = SubscriberDetails(siteID: userDefaults.appId,
                                      deviceTokenHash: userDefaults.subscriberHash)
        return status
    }
    
    func getPostBackSubscriptionData(for notification: PENotification) -> SponsoredPush {
        let sponsoredPush = SponsoredPush(tag: notification.tag,
                                          postback: notification.postback)
        return sponsoredPush
    }
    
    func getSubsriberUpgradeData() -> SubscriberUpgrade {
        let subscription = Subscription(endpoint: userDefaults.deviceToken,
                                        projectID: Utility.getBundleIdentifier)
        return SubscriberUpgrade(deviceTokenHash: userDefaults.subscriberHash,
                                 subscription: subscription,
                                 siteId: userDefaults.appId ?? -100)
    }
}
