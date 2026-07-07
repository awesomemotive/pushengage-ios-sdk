import Foundation
@testable import PushEngage
@testable import PushEngageExtension
final class MockNotificationLifeCycleService: NotificationLifeCycleServiceType {

    // MARK: - withRetrynotificationLifecycleUpdate
    struct LifecycleCall: Equatable {
        let action: String
        let deviceHash: String
        let notificationId: String
        let actionId: String?
    }
    private(set) var lifecycleCalls: [LifecycleCall] = []
    var lifecycleResult: Result<Bool, PEError> = .success(true)

    func withRetrynotificationLifecycleUpdate(with action: NotificationAction,
                                              deviceHash: String,
                                              notificationId: String,
                                              actionid: String?,
                                              completionHandler: NotificationCallResponse<Bool>?) {
        lifecycleCalls.append(.init(action: "\(action)",
                                    deviceHash: deviceHash,
                                    notificationId: notificationId,
                                    actionId: actionid))
        completionHandler?(lifecycleResult)
    }

    // MARK: - withRetrysponseredNotification
    private(set) var sponseredCallCount = 0
    private(set) var lastSponseredNotification: PENotification?
    var sponseredResult: Result<SponsoredData, PEError> = .failure(.contentNotFound)

    func withRetrysponseredNotification(with notification: PENotification,
                                        completionHandler: @escaping NotificationCallResponse<SponsoredData>) {
        sponseredCallCount += 1
        lastSponseredNotification = notification
        completionHandler(sponseredResult)
    }

    // MARK: - cancelled
    private(set) var cancelledCallCount = 0
    func cancelled() {
        cancelledCallCount += 1
    }
}
