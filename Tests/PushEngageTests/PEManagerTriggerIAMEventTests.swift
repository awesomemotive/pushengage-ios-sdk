import XCTest
@testable import PushEngage
@testable import PushEngageExtension

/// Input validation for `PEManager.triggerEvent(...)`, behind the public
/// `PushEngage.triggerIAMEvent(eventName:parameters:completionHandler:)`.
///
/// A blank event name matches no campaign, so before this guard the call reported
/// success and a typo'd event name failed silently. The message is pinned because
/// it is shared across every SDK — the Android SDK and the React Native / Flutter
/// bridges all report this failure identically ("Event name is required", 400).
final class PEManagerTriggerIAMEventTests: XCTestCase {

    private var applicationService: MockApplicationService!
    private var notificationService: MockNotificationService!
    private var subscriberService: MockSubscriberService!
    private var userDefaults: MockUserDefaultsService!
    private var lifecycle: MockNotificationLifeCycleService!
    private var triggerCampaign: MockTriggerCampaignManager!
    private var sut: PEManager!

    override func setUp() {
        super.setUp()
        applicationService = MockApplicationService()
        notificationService = MockNotificationService()
        subscriberService = MockSubscriberService()
        userDefaults = MockUserDefaultsService()
        lifecycle = MockNotificationLifeCycleService()
        triggerCampaign = MockTriggerCampaignManager()

        sut = PEManager(applicationService: applicationService,
                        notificationService: notificationService,
                        subscriberService: subscriberService,
                        userDefaultService: userDefaults,
                        notificationLifeCycleService: lifecycle,
                        triggerCamapaiginService: triggerCampaign)
    }

    override func tearDown() {
        sut = nil
        triggerCampaign = nil
        lifecycle = nil
        userDefaults = nil
        subscriberService = nil
        notificationService = nil
        applicationService = nil
        super.tearDown()
    }

    func test_triggerEvent_emptyName_failsCallbackWithSharedMessage() {
        var response: Bool? = nil
        var error: PEError? = nil

        sut.triggerEvent(name: "", parameters: nil) { ok, err in
            response = ok
            error = err
        }

        XCTAssertEqual(response, false)
        XCTAssertEqual(error?.localizedDescription, "Event name is required")
    }

    func test_triggerEvent_emptyName_withParameters_stillFails() {
        var response: Bool? = nil

        sut.triggerEvent(name: "", parameters: ["cart_value": 120]) { ok, _ in
            response = ok
        }

        XCTAssertEqual(response, false)
    }

    func test_triggerEvent_emptyName_nilCompletion_doesNotCrash() {
        sut.triggerEvent(name: "", parameters: nil, completionHandler: nil)
    }

    func test_triggerEvent_nonEmptyName_reportsSuccess() {
        var response: Bool? = nil
        var error: PEError? = nil

        sut.triggerEvent(name: "cart_abandoned", parameters: nil) { ok, err in
            response = ok
            error = err
        }

        XCTAssertEqual(response, true)
        XCTAssertNil(error)
    }
}
