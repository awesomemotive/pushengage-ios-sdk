import Foundation
import UserNotifications
@testable import PushEngage
@testable import PushEngageExtension
@available(iOS 10.0, *)
final class MockUNUserNotificationCenter: UNUserNotificationCenterProtocol {

    // MARK: - peGetAuthorizationStatus
    var stubbedAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var getAuthorizationStatusCallCount = 0
    /// When set, the authorization-status callback is delivered asynchronously on this
    /// queue (mirrors the real `getNotificationSettings`, which calls back on an arbitrary
    /// background queue). `nil` delivers synchronously on the calling thread.
    var completionQueue: DispatchQueue?

    func peGetAuthorizationStatus(completionHandler: @escaping (UNAuthorizationStatus) -> Void) {
        getAuthorizationStatusCallCount += 1
        let status = stubbedAuthorizationStatus
        if let queue = completionQueue {
            queue.async { completionHandler(status) }
        } else {
            completionHandler(status)
        }
    }

    // MARK: - requestAuthorization
    var stubbedAuthorizationResult: (Bool, Error?) = (false, nil)
    private(set) var requestAuthorizationCallCount = 0
    private(set) var lastRequestedOptions: UNAuthorizationOptions?

    func requestAuthorization(options: UNAuthorizationOptions,
                              completionHandler: @escaping (Bool, Error?) -> Void) {
        requestAuthorizationCallCount += 1
        lastRequestedOptions = options
        completionHandler(stubbedAuthorizationResult.0, stubbedAuthorizationResult.1)
    }
}
