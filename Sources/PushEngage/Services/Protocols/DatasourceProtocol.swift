//
//  DatasourceProtocol.swift
//  PushEngage
//
//  Created by Abhishek on 25/02/21.
//

import Foundation

protocol DataSourceType {
    /// Retrieves subscription data including device information and user preferences.
    /// - Returns: A `SubscriptionInfo` object containing user subscription data and device details.
    func getSubscriptionData() -> SubscriptionInfo
    /// Retrieves subscriber details such as site ID and device token hash.
    /// - Returns: A `SubscriberDetails` object containing site ID and subscriber information.
    func getSubscriptionStatus() -> SubscriberDetails
    /// Prepares sponsored push notification data for postback.
    /// - Parameter notification: The `PENotification` object representing the received push notification.
    /// - Returns: A `SponsoredPush` object containing tag and postback information for sponsored push.
    func getPostBackSubscriptionData(for notification: PENotification) -> SponsoredPush
    /// Retrieves subscriber upgrade data including device token and site ID.
    /// - Returns: A `SubscriberUpgrade` object containing device token hash, subscription details, and site ID.
    func getSubsriberUpgradeData() -> SubscriberUpgrade
}
