import XCTest
import UIKit
import UserNotifications
@testable import PushEngage

/// Tier 4 — `NotificationSettingsManageriOS10` permission state machine.
///
/// Uses an injected `UNUserNotificationCenterProtocol` mock (see
/// `MockUNUserNotificationCenter`) so the full authorization-status matrix
/// can be exercised — including the **Issue #2 early-return path** where the
/// SDK fires its custom alert and resolves the completion immediately while
/// the OS dialog is still in flight.
@available(iOS 10.0, *)
final class NotificationSettingsManageriOS10Tests: XCTestCase {

    private var userDefaults: MockUserDefaultsService!
    private var notificationCenter: MockUNUserNotificationCenter!
    private var sut: NotificationSettingsManageriOS10!

    override func setUp() {
        super.setUp()
        userDefaults = MockUserDefaultsService()
        notificationCenter = MockUNUserNotificationCenter()
        sut = NotificationSettingsManageriOS10(userDefaultService: userDefaults,
                                               notificationCenter: notificationCenter)
    }

    override func tearDown() {
        sut = nil
        notificationCenter = nil
        userDefaults = nil
        super.tearDown()
    }

    // MARK: - Initial state

    func test_init_observableSeededToNotYetRequested() {
        XCTAssertEqual(sut.notificationPermissionStatus.value, .notYetRequested)
    }

    // MARK: - getNotificationPermissionState — authorization-status mapping

    func test_getNotificationPermissionState_async_mapsAuthorizedToGranted() {
        notificationCenter.stubbedAuthorizationStatus = .authorized
        let exp = expectation(description: "callback")
        sut.getNotificationPermissionState { status in
            XCTAssertEqual(status, .granted)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_getNotificationPermissionState_async_mapsDeniedToDenied() {
        notificationCenter.stubbedAuthorizationStatus = .denied
        let exp = expectation(description: "callback")
        sut.getNotificationPermissionState { status in
            XCTAssertEqual(status, .denied)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_getNotificationPermissionState_async_mapsNotDeterminedToNotYetRequested() {
        notificationCenter.stubbedAuthorizationStatus = .notDetermined
        let exp = expectation(description: "callback")
        sut.getNotificationPermissionState { status in
            XCTAssertEqual(status, .notYetRequested)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    /// Apple's `.provisional` (iOS 12+) is full authorization for quiet
    /// delivery — the OS will not re-prompt and notifications reach the
    /// Notification Center. Must be reported as `.granted`, not as
    /// "not yet requested".
    func test_getNotificationPermissionState_async_mapsProvisionalToGranted() {
        notificationCenter.stubbedAuthorizationStatus = .provisional
        let exp = expectation(description: "callback")
        sut.getNotificationPermissionState { status in
            XCTAssertEqual(status, .granted)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func test_getNotificationPermissionState_sync_returnsCorrectValue() {
        notificationCenter.stubbedAuthorizationStatus = .authorized
        XCTAssertEqual(sut.getNotificationPermissionState(), .granted)
    }

    // MARK: - Observable subscribe / notify

    func test_observable_subscribe_firesOnValueChange() {
        var received: [PermissionStatus] = []
        _ = sut.notificationPermissionStatus.subscribe { received.append($0) }

        sut.notificationPermissionStatus.value = .granted
        sut.notificationPermissionStatus.value = .denied

        XCTAssertEqual(received, [.granted, .denied])
    }

    func test_observable_subscribe_doesNotFireImmediately_forCurrentValue() {
        var received: [PermissionStatus] = []
        _ = sut.notificationPermissionStatus.subscribe { received.append($0) }
        XCTAssertTrue(received.isEmpty)
    }

    // MARK: - onNotificationPromptResponse (iOS 9 leftover — no-op on iOS 10+)

    func test_onNotificationPromptResponse_isNoOp() {
        let before = sut.notificationPermissionStatus.value
        sut.onNotificationPromptResponse(notification: 1)
        sut.onNotificationPromptResponse(notification: 0)
        XCTAssertEqual(sut.notificationPermissionStatus.value, before)
    }

    // MARK: - handleNotificationPermission — branch matrix

    // Helper: wait for the main-queue dispatch inside handleNotificationPermission.
    private func runMainLoop() {
        let exp = expectation(description: "main loop tick")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
    }

    /// Issue #2 reference: system already returned a decision (.authorized) AND
    /// `ispermissionAlerted == false`. The SDK shows its custom in-app alert and
    /// fires completion(true, nil) **immediately** — without waiting for the user.
    func test_handleNotificationPermission_alreadyGrantedAndNotAlerted_firesCompletionImmediately() {
        notificationCenter.stubbedAuthorizationStatus = .authorized
        userDefaults.ispermissionAlerted = false

        var completionCalled = false
        var receivedGranted: Bool?
        var receivedError: PEError?
        sut.handleNotificationPermission(for: UIApplication.shared) { granted, error in
            completionCalled = true
            receivedGranted = granted
            receivedError = error
        }
        runMainLoop()

        XCTAssertTrue(completionCalled)
        XCTAssertEqual(receivedGranted, true)
        XCTAssertNil(receivedError)
        XCTAssertTrue(userDefaults.ispermissionAlerted,
                      "Early-return path must mark ispermissionAlerted=true")
        XCTAssertEqual(notificationCenter.requestAuthorizationCallCount, 0,
                       "Custom-alert path must NOT trigger the system request")
    }

    /// Issue #2 reference: same as above but denied.
    func test_handleNotificationPermission_alreadyDeniedAndNotAlerted_firesCompletionImmediately() {
        notificationCenter.stubbedAuthorizationStatus = .denied
        userDefaults.ispermissionAlerted = false

        var receivedGranted: Bool?
        sut.handleNotificationPermission(for: UIApplication.shared) { granted, _ in
            receivedGranted = granted
        }
        runMainLoop()

        XCTAssertEqual(receivedGranted, false)
        XCTAssertTrue(userDefaults.ispermissionAlerted)
    }

    /// When the user has already been alerted, the early-return path is skipped
    /// and the manager hits the `.denied/.granted` switch branch — fires completion
    /// immediately with the cached value.
    func test_handleNotificationPermission_alreadyGrantedAndAlerted_firesCompletionWithGranted() {
        notificationCenter.stubbedAuthorizationStatus = .authorized
        userDefaults.ispermissionAlerted = true

        var receivedGranted: Bool?
        sut.handleNotificationPermission(for: UIApplication.shared) { granted, _ in
            receivedGranted = granted
        }
        runMainLoop()

        XCTAssertEqual(receivedGranted, true)
        XCTAssertEqual(notificationCenter.requestAuthorizationCallCount, 0,
                       "Already-alerted path must NOT re-prompt the system")
    }

    func test_handleNotificationPermission_alreadyDeniedAndAlerted_firesCompletionWithDenied() {
        notificationCenter.stubbedAuthorizationStatus = .denied
        userDefaults.ispermissionAlerted = true

        var receivedGranted: Bool?
        sut.handleNotificationPermission(for: UIApplication.shared) { granted, _ in
            receivedGranted = granted
        }
        runMainLoop()

        XCTAssertEqual(receivedGranted, false)
    }

    /// Fresh install: status is .notDetermined. SUT calls the system requestAuthorization,
    /// completion fires from there.
    func test_handleNotificationPermission_notYetRequested_triggersSystemPromptAndCompletes() {
        notificationCenter.stubbedAuthorizationStatus = .notDetermined
        notificationCenter.stubbedAuthorizationResult = (true, nil)
        userDefaults.ispermissionAlerted = false

        var receivedGranted: Bool?
        let exp = expectation(description: "system completion")
        sut.handleNotificationPermission(for: UIApplication.shared) { granted, _ in
            receivedGranted = granted
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(receivedGranted, true)
        XCTAssertEqual(notificationCenter.requestAuthorizationCallCount, 1,
                       ".notYetRequested branch must call the system requestAuthorization")
        XCTAssertEqual(notificationCenter.lastRequestedOptions, [.alert, .badge, .sound])
        XCTAssertTrue(userDefaults.ispermissionAlerted,
                      "After the user responds, ispermissionAlerted must be true")
    }

    func test_handleNotificationPermission_notYetRequested_userDenies_completesWithFalse() {
        notificationCenter.stubbedAuthorizationStatus = .notDetermined
        notificationCenter.stubbedAuthorizationResult = (false, nil)

        var receivedGranted: Bool?
        let exp = expectation(description: "system completion")
        sut.handleNotificationPermission(for: UIApplication.shared) { granted, _ in
            receivedGranted = granted
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(receivedGranted, false)
    }

    /// When `isSwizzled == false`, the manager itself sets the observable based on
    /// the response (production code line 159-161). When swizzled == true, the
    /// swizzled requestAuthorization wrapper sets it instead, so the manager skips.
    func test_handleNotificationPermission_notSwizzled_updatesObservableOnResponse() {
        notificationCenter.stubbedAuthorizationStatus = .notDetermined
        notificationCenter.stubbedAuthorizationResult = (true, nil)
        userDefaults.isSwizzled = false

        let exp = expectation(description: "system completion")
        sut.handleNotificationPermission(for: UIApplication.shared) { _, _ in
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(sut.notificationPermissionStatus.value, .granted)
    }

    // MARK: - registerToApns

    func test_registerToApns_withNilApplication_doesNotCrash() {
        sut.registerToApns(for: nil)
    }

    // MARK: - willEnterForeground

    func test_willEnterForeground_updatesObservableWhenSystemStateDiffers() {
        // Initial observable: .notYetRequested. System now reports .authorized.
        notificationCenter.stubbedAuthorizationStatus = .authorized

        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification,
                                        object: nil)

        // The foreground handler calls getNotificationPermissionState which uses
        // a semaphore + 100ms timeout. Give it a moment.
        let exp = expectation(description: "observable updates")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(sut.notificationPermissionStatus.value, .granted,
                       "willEnterForeground must sync the observable to the live system state")
    }
}
