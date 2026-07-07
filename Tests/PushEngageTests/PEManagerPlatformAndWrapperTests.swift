import XCTest
@testable import PushEngage
@testable import PushEngageExtension
/// Unit tests for `PEManager.setPlatform(_:)` and `PEManager.setWrapperVersion(_:)`.
/// Both are thin pass-throughs to the userDefaults service — the contract is
/// (a) round-trip, (b) empty-string clears. Setters are intentionally safe to
/// call before any other PushEngage configuration (no `setAppId` required)
/// because the lazy-init manager static and direct UserDefaults write don't
/// depend on app-id state — wrappers init themselves before the host app does.
final class PEManagerPlatformAndWrapperTests: XCTestCase {

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

    // MARK: - setPlatform

    func test_setPlatform_writesThroughToUserDefaults() {
        sut.setPlatform(PEPlatform.flutterIOS)
        XCTAssertEqual(userDefaults.platform, PEPlatform.flutterIOS)
    }

    func test_setPlatform_acceptsArbitraryString_doesNotGatekeepWrapperName() {
        // Android contract: "the field accepts any sanitized string — the SDK
        // does not gatekeep new wrappers." Mirror that on iOS.
        sut.setPlatform("UnityIOS")
        XCTAssertEqual(userDefaults.platform, "UnityIOS")
    }

    func test_setPlatform_emptyString_clearsStoredValue() {
        userDefaults.platform = PEPlatform.reactNativeIOS
        sut.setPlatform("")
        XCTAssertNil(userDefaults.platform,
                     "Empty string must clear the stored platform — UA composition then falls back to the default")
    }

    func test_setPlatform_overwritesPreviousValue() {
        sut.setPlatform(PEPlatform.flutterIOS)
        sut.setPlatform(PEPlatform.reactNativeIOS)
        XCTAssertEqual(userDefaults.platform, PEPlatform.reactNativeIOS)
    }

    // MARK: - setWrapperVersion

    func test_setWrapperVersion_writesThroughToUserDefaults() {
        sut.setWrapperVersion("2.3.0")
        XCTAssertEqual(userDefaults.wrapperVersion, "2.3.0")
    }

    func test_setWrapperVersion_emptyString_clearsStoredValue() {
        userDefaults.wrapperVersion = "1.0.0"
        sut.setWrapperVersion("")
        XCTAssertNil(userDefaults.wrapperVersion,
                     "Empty string must clear the stored wrapper version — UA composition then omits the wrapper-version slot")
    }

    func test_setWrapperVersion_overwritesPreviousValue() {
        sut.setWrapperVersion("1.0.0")
        sut.setWrapperVersion("1.0.1")
        XCTAssertEqual(userDefaults.wrapperVersion, "1.0.1")
    }

    // MARK: - Composed flow → UA reflects setter calls

    func test_setPlatformAndSetWrapperVersion_appearInBuiltUserAgent() {
        sut.setPlatform(PEPlatform.flutterIOS)
        sut.setWrapperVersion("9.9.9")
        let ua = Utility.buildUserAgent(userDefaults: userDefaults)
        XCTAssertTrue(ua.hasSuffix("/\(PEPlatform.flutterIOS)/9.9.9"),
                      "Setters must round-trip through to the UA builder — got \(ua)")
    }
}
