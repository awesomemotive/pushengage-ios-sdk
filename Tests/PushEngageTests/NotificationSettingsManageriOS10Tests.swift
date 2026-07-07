import XCTest
import UIKit
import UserNotifications
@testable import PushEngage
@testable import PushEngageExtension
/// Tier 4 — `NotificationSettingsManageriOS10` permission state machine.
///
/// Uses an injected `UNUserNotificationCenterProtocol` mock (see
/// `MockUNUserNotificationCenter`) so the full authorization-status matrix
/// can be exercised — including the early-return path where, for an
/// already-decided OS permission, the SDK registers silently on `.granted`
/// (no UI) or reports `.denied` back to the host, without showing any alert.
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

    /// Regression for the deadlock fix: the getter must return BEFORE the authorization
    /// callback runs — i.e. it must not block waiting on it. Delivery is gated behind a
    /// suspended queue so the ordering is deterministic: if the getter blocked on the
    /// callback (the old semaphore behaviour), `callbackRan` would be true at the assert.
    func test_getNotificationPermissionState_async_returnsBeforeCallback_doesNotBlock() {
        notificationCenter.stubbedAuthorizationStatus = .authorized
        let gate = DispatchQueue(label: "test.gated.delivery")
        gate.suspend()
        notificationCenter.completionQueue = gate

        var callbackRan = false
        let exp = expectation(description: "callback")
        sut.getNotificationPermissionState { status in
            callbackRan = true
            XCTAssertEqual(status, .granted)
            exp.fulfill()
        }

        XCTAssertFalse(callbackRan,
                       "Getter must return without waiting on the callback (non-blocking)")
        gate.resume()
        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(callbackRan)
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

    /// Already-granted + `ispermissionAlerted == false`: the SDK registers for remote
    /// notifications silently (no custom in-app alert) and fires completion(true, nil)
    /// immediately. It must not trigger the system authorization prompt.
    func test_handleNotificationPermission_alreadyGrantedAndNotAlerted_registersSilently() {
        notificationCenter.stubbedAuthorizationStatus = .authorized
        userDefaults.ispermissionAlerted = false

        var receivedGranted: Bool?
        var receivedError: PEError?
        let exp = expectation(description: "completion")
        sut.handleNotificationPermission(for: UIApplication.shared) { granted, error in
            receivedGranted = granted
            receivedError = error
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(receivedGranted, true)
        XCTAssertNil(receivedError)
        XCTAssertTrue(userDefaults.ispermissionAlerted,
                      "Silent-register path must mark ispermissionAlerted=true")
        XCTAssertEqual(notificationCenter.requestAuthorizationCallCount, 0,
                       "Silent-register path must NOT trigger the system request")
    }

    /// Already-denied + `ispermissionAlerted == false`: the SDK reports denied to the host
    /// (completion(false, nil)) without showing any custom alert, and must not trigger the
    /// system authorization prompt.
    func test_handleNotificationPermission_alreadyDeniedAndNotAlerted_reportsDeniedToHost() {
        notificationCenter.stubbedAuthorizationStatus = .denied
        userDefaults.ispermissionAlerted = false

        var receivedGranted: Bool?
        var receivedError: PEError?
        let exp = expectation(description: "completion")
        sut.handleNotificationPermission(for: UIApplication.shared) { granted, error in
            receivedGranted = granted
            receivedError = error
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(receivedGranted, false)
        XCTAssertNil(receivedError)
        XCTAssertTrue(userDefaults.ispermissionAlerted)
        XCTAssertEqual(notificationCenter.requestAuthorizationCallCount, 0,
                       "Already-denied path must NOT trigger the system request")
    }

    /// When the user has already been alerted, the early-return path is skipped
    /// and the manager hits the `.denied/.granted` switch branch — fires completion
    /// immediately with the cached value.
    func test_handleNotificationPermission_alreadyGrantedAndAlerted_firesCompletionWithGranted() {
        notificationCenter.stubbedAuthorizationStatus = .authorized
        userDefaults.ispermissionAlerted = true

        var receivedGranted: Bool?
        let exp = expectation(description: "completion")
        sut.handleNotificationPermission(for: UIApplication.shared) { granted, _ in
            receivedGranted = granted
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(receivedGranted, true)
        XCTAssertEqual(notificationCenter.requestAuthorizationCallCount, 0,
                       "Already-alerted path must NOT re-prompt the system")
    }

    func test_handleNotificationPermission_alreadyDeniedAndAlerted_firesCompletionWithDenied() {
        notificationCenter.stubbedAuthorizationStatus = .denied
        userDefaults.ispermissionAlerted = true

        var receivedGranted: Bool?
        let exp = expectation(description: "completion")
        sut.handleNotificationPermission(for: UIApplication.shared) { granted, _ in
            receivedGranted = granted
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(receivedGranted, false)
    }

    /// Regression for the deadlock fix: the entire permission flow must complete even when
    /// the authorization callback is delivered asynchronously on a background queue (the
    /// real `getNotificationSettings` behaviour). Previously this path blocked the caller on
    /// a semaphore; it must now be fully non-blocking.
    func test_handleNotificationPermission_backgroundDelivery_completesWithoutBlocking() {
        notificationCenter.stubbedAuthorizationStatus = .authorized
        notificationCenter.completionQueue = DispatchQueue(label: "test.bg.delivery")
        userDefaults.ispermissionAlerted = true

        var receivedGranted: Bool?
        var completedOnMain = false
        let exp = expectation(description: "completion")
        sut.handleNotificationPermission(for: UIApplication.shared) { granted, _ in
            receivedGranted = granted
            completedOnMain = Thread.isMainThread
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(receivedGranted, true)
        XCTAssertTrue(completedOnMain,
                      "completion must be delivered on the main queue even for background-delivered callbacks")
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

        // The foreground handler reads the status asynchronously and updates the observable
        // on the main queue; wait on the value change rather than an arbitrary delay.
        let exp = expectation(description: "observable updates to granted")
        let token = sut.notificationPermissionStatus.subscribe { status in
            if status == .granted { exp.fulfill() }
        }

        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification,
                                        object: nil)

        wait(for: [exp], timeout: 1.0)
        token.dispose()
        XCTAssertEqual(sut.notificationPermissionStatus.value, .granted,
                       "willEnterForeground must sync the observable to the live system state")
    }

    /// After `handleNotificationPermission` has run (state == .isCalled), a foreground event
    /// transitions to .canCallForeground and routes through `checkPermissionStatus`, which
    /// must sync the observable to the live system state.
    func test_willEnterForeground_afterStartCalled_syncsObservableViaCheckPermissionStatus() {
        notificationCenter.stubbedAuthorizationStatus = .authorized
        userDefaults.ispermissionAlerted = true
        let started = expectation(description: "handleNotificationPermission completes")
        sut.handleNotificationPermission(for: UIApplication.shared) { _, _ in started.fulfill() }
        wait(for: [started], timeout: 2.0)

        // System permission now changed to denied (e.g. via iOS Settings).
        notificationCenter.stubbedAuthorizationStatus = .denied
        let exp = expectation(description: "observable updates to denied")
        let token = sut.notificationPermissionStatus.subscribe { status in
            if status == .denied { exp.fulfill() }
        }

        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification,
                                        object: nil)

        wait(for: [exp], timeout: 1.0)
        token.dispose()
        XCTAssertEqual(sut.notificationPermissionStatus.value, .denied)
    }
}
