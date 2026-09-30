import XCTest
@testable import PushEngage

/// Out-of-foreground campaign refresh. The load-bearing property is the **opt-in gate**:
/// `BGTaskScheduler` refuses an identifier the host app has not declared, and the test
/// bundle does not declare one — so these tests exercise the un-opted-in path, which is
/// exactly the path every existing integrator is on until they add the Info.plist key.
/// Nothing here may crash, and nothing may submit a request that can only fail.
final class IAMBackgroundRefreshTests: XCTestCase {

    /// Registration must not throw, raise or crash when the host has not opted in. The
    /// real hazard is `BGTaskScheduler.register` being called for an undeclared
    /// identifier, which the system refuses — so the identifier is checked against the
    /// bundle first and registration is skipped entirely.
    func testRegistrationIsASafeNoOpWhenTheHostHasNotOptedIn() {
        let refresh = IAMBackgroundRefresh()

        // The assertion is that this returns at all: an unguarded register() against an
        // undeclared identifier terminates the process.
        refresh.registerIfPermitted()
        refresh.registerIfPermitted() // idempotent

        XCTAssertFalse(Self.bundleDeclaresIdentifier,
                       "precondition: the test bundle must not declare the identifier, "
                        + "otherwise this suite is testing the opposite path")
    }

    /// Scheduling must be gated on successful registration. Submitting a request for an
    /// unregistered identifier can only fail, and doing it on every background would log
    /// an error on every background for every host that has not opted in.
    func testSchedulingIsASafeNoOpWithoutRegistration() {
        let refresh = IAMBackgroundRefresh()

        refresh.scheduleNext()
        refresh.scheduleNext()
    }

    /// Reaching it through the shared instance is what production does (the controller's
    /// initialiser), so the singleton path must be as safe as a fresh instance.
    func testTheSharedInstanceIsSafeToRegisterAndScheduleRepeatedly() {
        IAMBackgroundRefresh.shared.registerIfPermitted()
        IAMBackgroundRefresh.shared.scheduleNext()
        IAMBackgroundRefresh.shared.registerIfPermitted()
        IAMBackgroundRefresh.shared.scheduleNext()
    }

    /// The identifier is part of the integration contract: a host declares this exact
    /// string in its Info.plist. Changing it silently breaks background refresh for every
    /// integrator who already did, with no error on either side — so it is pinned here.
    func testTheTaskIdentifierIsTheDocumentedOne() {
        XCTAssertEqual(IAMBackgroundRefresh.taskIdentifier, "com.pushengage.iam.refresh",
                       "this string is published integration documentation — changing it "
                        + "is a breaking change for every host that declared it")
    }

    /// Building the controller must NOT register: `setAppId` also builds this singleton,
    /// and wrappers call that after the app is already active, where registering a launch
    /// handler is too late. Registration is an explicit call from `setInitialInfo`.
    func testBuildingTheControllerDoesNotCrashWithoutHostOptIn() {
        XCTAssertNotNil(IAMController.shared)
    }

    /// The explicit registration entry point carries the same no-op guarantee as
    /// `registerIfPermitted`, and stays idempotent for hosts that configure twice.
    func testExplicitRegistrationIsASafeNoOpAndIdempotent() {
        IAMController.shared.registerBackgroundRefresh()
        IAMController.shared.registerBackgroundRefresh()
    }

    private static var bundleDeclaresIdentifier: Bool {
        let declared = Bundle.main.object(
            forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers"
        ) as? [String]
        return declared?.contains(IAMBackgroundRefresh.taskIdentifier) ?? false
    }
}
