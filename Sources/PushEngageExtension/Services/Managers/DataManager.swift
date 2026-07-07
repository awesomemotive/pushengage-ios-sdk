//
//  DataManager.swift
//  PushEngage
//
//  Created by Abhishek on 25/02/21.
//

import Foundation

/// `DataManager` class provides methods to retrieve subscription and subscriber details, as well as handling sponsored push notifications.
package final class DataManager: DataSourceType {
    
    /// The UserDefaults manager responsible for handling data persistence.
    private let userDefaults: UserDefaultsType

    /// Supplies the host app's code-signing entitlements (source of the APNs aps-environment).
    private let entitlementsProvider: () -> Entitlements
    
    /// Initializes the `DataManager` with the provided `UserDefaultsType` instance.
    /// - Parameter userDefault: An instance conforming to `UserDefaultsType` used for data storage and retrieval.
    package init(userDefault: UserDefaultsType,
                entitlementsProvider: @escaping () -> Entitlements = { Bundle.main.entitlements }) {
        self.userDefaults = userDefault
        self.entitlementsProvider = entitlementsProvider
    }
    
    package func getSubscriptionData() -> SubscriptionInfo {
        
        let permisionStatus = userDefaults.notificationPermissionState
        let result = permisionStatus == .denied ? (userDefaults.isDeleteSubscriberOnDisable ?? false ? 1 : 0) : nil
        var env: String?
        if let certEnv = entitlementsProvider().value(forKey: .apsEnvironment) as? String {
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
    
    package func getSubscriptionStatus() -> SubscriberDetails {
        let status = SubscriberDetails(siteID: userDefaults.appId,
                                      deviceTokenHash: userDefaults.subscriberHash)
        return status
    }
    
    package func getPostBackSubscriptionData(for notification: PENotification) -> SponsoredPush {
        let sponsoredPush = SponsoredPush(tag: notification.tag,
                                          postback: notification.postback)
        return sponsoredPush
    }
    
    package func getSubsriberUpgradeData() -> SubscriberUpgrade {
        let subscription = Subscription(endpoint: userDefaults.deviceToken,
                                        projectID: Utility.getBundleIdentifier)
        return SubscriberUpgrade(deviceTokenHash: userDefaults.subscriberHash,
                                 subscription: subscription,
                                 siteId: userDefaults.appId ?? -100)
    }
}
