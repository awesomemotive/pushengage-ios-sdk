import XCTest
@testable import PushEngage

/// Unit tests for `PEManager.trackEvent(...)`. Mirrors Android's
/// `PEManager.trackEvent` validation contract:
///   - empty event name → 400-equivalent callback failure, no dispatch
///   - property keys must be non-blank
///   - property values must be String / Number / Bool — arrays, dicts, Date, etc. are rejected
///   - nil/missing `provider` defaults to "PushEngage"
///   - nil/missing `eventType` defaults to "PushEngage.CustomEvent"
///   - request body populated with siteId from userDefaults.appId and deviceTokenHash from userDefaults.subscriberHash
final class PEManagerTrackEventTests: XCTestCase {

    private var applicationService: MockApplicationService!
    private var notificationService: MockNotificationService!
    private var notificationExtensionService: MockNotificationExtensionService!
    private var subscriberService: MockSubscriberService!
    private var userDefaults: MockUserDefaultsService!
    private var lifecycle: MockNotificationLifeCycleService!
    private var triggerCampaign: MockTriggerCampaignManager!
    private var sut: PEManager!

    override func setUp() {
        super.setUp()
        applicationService = MockApplicationService()
        notificationService = MockNotificationService()
        notificationExtensionService = MockNotificationExtensionService()
        subscriberService = MockSubscriberService()
        userDefaults = MockUserDefaultsService()
        lifecycle = MockNotificationLifeCycleService()
        triggerCampaign = MockTriggerCampaignManager()

        // Pass the prerequisite-network-call-check: site active, permission granted,
        // subscriber alive, siteId resolvable.
        userDefaults._setSiteStatus(SiteStatus.active.rawValue)
        userDefaults.notificationPermissionState = .granted
        userDefaults.isSubscriberDeleted = false
        userDefaults.subscriberHash = "device-hash-123"
        userDefaults._setAppId(7777)

        sut = PEManager(applicationService: applicationService,
                        notificationService: notificationService,
                        notificationExtensionService: notificationExtensionService,
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
        notificationExtensionService = nil
        notificationService = nil
        applicationService = nil
        super.tearDown()
    }

    // MARK: - Validation: event name

    func test_trackEvent_emptyName_failsCallbackAndSkipsDispatch() {
        var response: Bool? = nil
        var error: PEError? = nil

        sut.trackEvent(name: "",
                       properties: nil,
                       profileId: nil,
                       provider: nil,
                       eventType: nil) { ok, err in
            response = ok
            error = err as? PEError
        }

        XCTAssertEqual(response, false)
        XCTAssertNotNil(error)
        XCTAssertEqual(subscriberService.trackEventCallCount, 0,
                       "Validation failure must short-circuit before service dispatch")
    }

    // MARK: - Validation: property keys

    func test_trackEvent_blankPropertyKey_failsCallbackAndSkipsDispatch() {
        var response: Bool? = nil
        var error: PEError? = nil

        sut.trackEvent(name: "purchase",
                       properties: ["  ": "value"],
                       profileId: nil,
                       provider: nil,
                       eventType: nil) { ok, err in
            response = ok
            error = err as? PEError
        }

        XCTAssertEqual(response, false)
        XCTAssertNotNil(error)
        XCTAssertEqual(subscriberService.trackEventCallCount, 0)
    }

    // MARK: - Validation: property value types

    func test_trackEvent_acceptsStringNumberBool() {
        sut.trackEvent(name: "purchase",
                       properties: ["plan": "pro", "amount": 19.99, "is_trial": false, "items": 3],
                       profileId: nil,
                       provider: nil,
                       eventType: nil,
                       completionHandler: nil)

        XCTAssertEqual(subscriberService.trackEventCallCount, 1,
                       "String/Number/Bool values must pass validation and reach the service")
    }

    func test_trackEvent_rejectsArrayValue() {
        var response: Bool? = nil
        sut.trackEvent(name: "purchase",
                       properties: ["items": ["a", "b"]],
                       profileId: nil,
                       provider: nil,
                       eventType: nil) { ok, _ in response = ok }

        XCTAssertEqual(response, false)
        XCTAssertEqual(subscriberService.trackEventCallCount, 0)
    }

    func test_trackEvent_rejectsDictValue() {
        var response: Bool? = nil
        sut.trackEvent(name: "purchase",
                       properties: ["nested": ["a": 1]],
                       profileId: nil,
                       provider: nil,
                       eventType: nil) { ok, _ in response = ok }

        XCTAssertEqual(response, false)
        XCTAssertEqual(subscriberService.trackEventCallCount, 0)
    }

    func test_trackEvent_rejectsDateValue() {
        var response: Bool? = nil
        sut.trackEvent(name: "purchase",
                       properties: ["when": Date()],
                       profileId: nil,
                       provider: nil,
                       eventType: nil) { ok, _ in response = ok }

        XCTAssertEqual(response, false)
        XCTAssertEqual(subscriberService.trackEventCallCount, 0)
    }

    // MARK: - Defaults applied

    func test_trackEvent_nilProvider_defaultsToPushEngage() {
        sut.trackEvent(name: "purchase",
                       properties: nil,
                       profileId: nil,
                       provider: nil,
                       eventType: nil,
                       completionHandler: nil)

        XCTAssertEqual(subscriberService.trackEventCallCount, 1)
        XCTAssertEqual(subscriberService.lastTrackEventRequest?.provider, "PushEngage",
                       "nil provider must default to 'PushEngage' at the wire")
    }

    func test_trackEvent_nilEventType_defaultsToCustomEventSend() {
        sut.trackEvent(name: "purchase",
                       properties: nil,
                       profileId: nil,
                       provider: nil,
                       eventType: nil,
                       completionHandler: nil)

        XCTAssertEqual(subscriberService.lastTrackEventRequest?.eventType, "PushEngage.CustomEvent",
                       "nil event type must default to 'PushEngage.CustomEvent'")
    }

    func test_trackEvent_passesUserOverridesThrough() {
        sut.trackEvent(name: "purchase",
                       properties: nil,
                       profileId: "user-42",
                       provider: "MyProvider",
                       eventType: "MyApp.Cart.Purchase",
                       completionHandler: nil)

        let req = subscriberService.lastTrackEventRequest
        XCTAssertEqual(req?.provider, "MyProvider")
        XCTAssertEqual(req?.eventType, "MyApp.Cart.Purchase")
        XCTAssertEqual(req?.profileId, "user-42")
    }

    // MARK: - Request payload

    func test_trackEvent_populatesSiteIdAndSubscriberHashFromUserDefaults() {
        sut.trackEvent(name: "purchase",
                       properties: nil,
                       profileId: nil,
                       provider: nil,
                       eventType: nil,
                       completionHandler: nil)

        XCTAssertEqual(subscriberService.lastTrackEventRequest?.siteId, 7777)
        XCTAssertEqual(subscriberService.lastTrackEventRequest?.deviceTokenHash, "device-hash-123")
    }

    func test_trackEvent_nilProperties_sendsEmptyData() {
        sut.trackEvent(name: "purchase",
                       properties: nil,
                       profileId: nil,
                       provider: nil,
                       eventType: nil,
                       completionHandler: nil)

        XCTAssertEqual(subscriberService.lastTrackEventRequest?.data.count, 0,
                       "nil properties must serialize as an empty map (Android wire-parity)")
    }

    func test_trackEvent_populatesEventName() {
        sut.trackEvent(name: "MySite.AddToCart",
                       properties: nil,
                       profileId: nil,
                       provider: nil,
                       eventType: nil,
                       completionHandler: nil)

        XCTAssertEqual(subscriberService.lastTrackEventRequest?.eventName, "MySite.AddToCart")
    }

    // MARK: - appId guard

    func test_trackEvent_nilAppId_failsCallback_noDispatch() {
        userDefaults._setAppId(nil)
        var response: Bool? = nil
        var error: PEError? = nil
        sut.trackEvent(name: "purchase",
                       properties: nil,
                       profileId: nil,
                       provider: nil,
                       eventType: nil) { ok, err in
            response = ok
            error = err as? PEError
        }
        XCTAssertEqual(response, false)
        XCTAssertEqual(subscriberService.trackEventCallCount, 0,
                       "Must reject locally when appId not yet resolved instead of sending site_id:0")
        if case .siteKeyNotAvailable = error {} else {
            XCTFail("Expected .siteKeyNotAvailable, got \(String(describing: error))")
        }
    }
}
