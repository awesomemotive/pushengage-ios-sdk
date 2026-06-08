import Foundation
import UIKit
import UserNotifications
@testable import PushEngage

final class MockApplicationService: ApplicationServiceType {

    weak var notifydelegate: LastNotificationSetDelegate?

    // MARK: - registerDeviceToServer
    private(set) var registerDeviceCallCount = 0
    private(set) var lastDeviceToken: Data?
    func registerDeviceToServer(with deviceToken: Data) {
        registerDeviceCallCount += 1
        lastDeviceToken = deviceToken
    }

    // MARK: - receivedRemoteNotification
    private(set) var receivedRemoteCallCount = 0
    private(set) var lastReceivedUserInfo: [AnyHashable: Any]?
    var receivedRemoteReturn: Bool = false
    var receivedRemoteFetchResult: UIBackgroundFetchResult = .noData

    func receivedRemoteNotification(application: UIApplication,
                                    userInfo: [AnyHashable: Any],
                                    completionHandler: ((UIBackgroundFetchResult) -> Void)?) -> Bool {
        receivedRemoteCallCount += 1
        lastReceivedUserInfo = userInfo
        completionHandler?(receivedRemoteFetchResult)
        return receivedRemoteReturn
    }

    // MARK: - willPresentNotification
    private(set) var willPresentCallCount = 0
    var willPresentOptions: UNNotificationPresentationOptions = []

    func willPresentNotification(center: UNUserNotificationCenter,
                                 notification: UNNotification,
                                 completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        willPresentCallCount += 1
        completionHandler(willPresentOptions)
    }
}
