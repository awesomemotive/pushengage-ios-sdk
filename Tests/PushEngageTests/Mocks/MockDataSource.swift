import Foundation
@testable import PushEngage

final class MockDataSource: DataSourceType {

    private(set) var getSubscriptionDataCallCount = 0
    private(set) var getSubscriptionStatusCallCount = 0
    private(set) var getPostBackSubscriptionDataCallCount = 0
    private(set) var lastPostbackNotification: PENotification?
    private(set) var getSubsriberUpgradeDataCallCount = 0

    var stubbedSubscriptionInfo: SubscriptionInfo!
    var stubbedSubscriberDetails: SubscriberDetails!
    var stubbedSponsoredPush: SponsoredPush!
    var stubbedSubscriberUpgrade: SubscriberUpgrade!

    func getSubscriptionData() -> SubscriptionInfo {
        getSubscriptionDataCallCount += 1
        return stubbedSubscriptionInfo
    }

    func getSubscriptionStatus() -> SubscriberDetails {
        getSubscriptionStatusCallCount += 1
        return stubbedSubscriberDetails
    }

    func getPostBackSubscriptionData(for notification: PENotification) -> SponsoredPush {
        getPostBackSubscriptionDataCallCount += 1
        lastPostbackNotification = notification
        return stubbedSponsoredPush
    }

    func getSubsriberUpgradeData() -> SubscriberUpgrade {
        getSubsriberUpgradeDataCallCount += 1
        return stubbedSubscriberUpgrade
    }
}
