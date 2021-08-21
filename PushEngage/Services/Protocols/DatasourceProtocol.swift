//
//  DatasourceProtocol.swift
//  PushEngage
//
//  Created by Abhishek on 25/02/21.
//

import Foundation

protocol DataSourceProtocol {
    
    func getSubscriptionData() -> SubscriptionInfo
    func getSubscriptionStatus() -> SubscriberDetails
    func getPostBackSubscriptionData(for notification: PENotification) -> SponsoredPush
    func getSubsriberUpgradeData() -> SubscriberUpgrade
}
