import Foundation
import UserNotifications
@testable import PushEngage

@available(iOS 10.0, *)
final class MockUNUserNotificationCenter: UNUserNotificationCenterProtocol {

    // MARK: - peGetAuthorizationStatus
    var stubbedAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var getAuthorizationStatusCallCount = 0

    func peGetAuthorizationStatus(completionHandler: @escaping (UNAuthorizationStatus) -> Void) {
        getAuthorizationStatusCallCount += 1
        completionHandler(stubbedAuthorizationStatus)
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
