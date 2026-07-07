import Foundation
import UIKit
@testable import PushEngage
@testable import PushEngageExtension
final class MockNotificationService: NotificationServiceType {

    // MARK: - handleNotificationPermission
    private(set) var handleNotificationPermissionCallCount = 0
    private(set) var lastHandlePermissionApplication: UIApplication?
    var handlePermissionResult: (Bool, PEError?) = (true, nil)
    var handlePermissionShouldDefer = false
    private var deferredCompletion: ((Bool, PEError?) -> Void)?

    func handleNotificationPermission(for application: UIApplication,
                                      completion: @escaping (Bool, PEError?) -> Void) {
        handleNotificationPermissionCallCount += 1
        lastHandlePermissionApplication = application
        if handlePermissionShouldDefer {
            deferredCompletion = completion
        } else {
            completion(handlePermissionResult.0, handlePermissionResult.1)
        }
    }

    /// Test helper: fires the captured completion when `handlePermissionShouldDefer == true`.
    func resolveDeferredPermission(_ granted: Bool, error: PEError? = nil) {
        deferredCompletion?(granted, error)
        deferredCompletion = nil
    }

    // MARK: - registerToApns
    private(set) var registerToApnsCallCount = 0
    private(set) var lastRegisterApplication: UIApplication?

    func registerToApns(for application: UIApplication?) {
        registerToApnsCallCount += 1
        lastRegisterApplication = application
    }

    // MARK: - onNotificationPromptResponse
    private(set) var onNotificationPromptResponseCallCount = 0
    private(set) var lastPromptResponseType: Int?

    func onNotificationPromptResponse(notification type: Int) {
        onNotificationPromptResponseCallCount += 1
        lastPromptResponseType = type
    }

    // MARK: - notificationPermissionStatus
    let notificationPermissionStatus: Variable<PermissionStatus> = Variable(.notYetRequested)
}
