import Foundation
import UserNotifications
@testable import PushEngage

final class MockNotificationExtensionService: NotificationExtensionType {

    private(set) var didReceiveExtensionCallCount = 0
    private(set) var lastDidReceiveRequest: UNNotificationRequest?
    private(set) var lastBestContent: UNMutableNotificationContent?

    func didReceiveNotificationExtensionRequest(_ request: UNNotificationRequest,
                                                bestContentHandler: UNMutableNotificationContent) {
        didReceiveExtensionCallCount += 1
        lastDidReceiveRequest = request
        lastBestContent = bestContentHandler
    }

    private(set) var serviceExtensionTimeWillExpireCallCount = 0
    private(set) var lastExpireRequest: UNNotificationRequest?
    var expireReturnContent: UNMutableNotificationContent? = nil

    func serviceExtensionTimeWillExpire(_ request: UNNotificationRequest,
                                        content: UNMutableNotificationContent?) -> UNMutableNotificationContent? {
        serviceExtensionTimeWillExpireCallCount += 1
        lastExpireRequest = request
        return expireReturnContent ?? content
    }

    private(set) var getContentExtensionInfoCallCount = 0
    private(set) var lastContentExtensionRequest: UNNotificationRequest?
    var stubbedContentExtensionInfo: CustomUIModel = CustomUIModel(title: "", body: "", image: nil, buttons: nil)

    func getContentExtensionInfo(for request: UNNotificationRequest) -> CustomUIModel {
        getContentExtensionInfoCallCount += 1
        lastContentExtensionRequest = request
        return stubbedContentExtensionInfo
    }
}
