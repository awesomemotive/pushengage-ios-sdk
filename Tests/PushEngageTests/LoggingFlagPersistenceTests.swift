import XCTest
@testable import PushEngage
@testable import PushEngageExtension

/// One customer-facing flag (`PushEngage.enableLogging`) must control SDK
/// logging in both processes: the app persists it into the shared app-group
/// suite, and the extension factory applies the persisted value when the
/// NSE process builds its graph.
final class LoggingFlagPersistenceTests: XCTestCase {

    private var savedFlag = false

    override func setUp() {
        super.setUp()
        savedFlag = PELogger.isLoggingEnable
        PELogger.isLoggingEnable = false
    }

    override func tearDown() {
        PELogger.isLoggingEnable = savedFlag
        super.tearDown()
    }

    private func makeManager(userDefaults: MockUserDefaultsService) -> PEManager {
        PEManager(applicationService: MockApplicationService(),
                  notificationService: MockNotificationService(),
                  subscriberService: MockSubscriberService(),
                  userDefaultService: userDefaults,
                  notificationLifeCycleService: MockNotificationLifeCycleService(),
                  triggerCamapaiginService: MockTriggerCampaignManager())
    }

    // MARK: - Storage (UserDefaultManager over the shared suite)

    func test_userDefaultManager_persistsLoggingFlagAcrossInstances() {
        let suite = makeSuite("pe-logging-tests-shared")

        let appProcess = UserDefaultManager(userDefaults: suite)
        appProcess.isSdkLoggingEnabled = true

        let extensionProcess = UserDefaultManager(userDefaults: suite)
        XCTAssertTrue(extensionProcess.isSdkLoggingEnabled)
    }

    func test_userDefaultManager_loggingFlagDefaultsToFalse() {
        let suite = makeSuite("pe-logging-tests-default")
        XCTAssertFalse(UserDefaultManager(userDefaults: suite).isSdkLoggingEnabled)
    }

    func test_userDefaultManager_nilContainer_readsFalseAndSetDoesNotCrash() {
        let sut = UserDefaultManager(userDefaults: nil)
        sut.isSdkLoggingEnabled = true
        XCTAssertFalse(sut.isSdkLoggingEnabled)
    }

    // MARK: - App side (PEManager)

    func test_setLoggingEnabled_true_flipsLoggerAndPersists() {
        let defaults = MockUserDefaultsService()
        let sut = makeManager(userDefaults: defaults)

        sut.setLoggingEnabled(true)

        XCTAssertTrue(PELogger.isLoggingEnable)
        XCTAssertTrue(defaults.isSdkLoggingEnabled)
    }

    func test_setLoggingEnabled_false_flipsLoggerOffAndPersists() {
        let defaults = MockUserDefaultsService()
        let sut = makeManager(userDefaults: defaults)
        sut.setLoggingEnabled(true)

        sut.setLoggingEnabled(false)

        XCTAssertFalse(PELogger.isLoggingEnable)
        XCTAssertFalse(defaults.isSdkLoggingEnabled)
    }

    func test_managerInit_resyncsStalePersistedFlagToCodeTruth() {
        let defaults = MockUserDefaultsService()
        defaults.isSdkLoggingEnabled = true

        _ = makeManager(userDefaults: defaults)

        XCTAssertFalse(defaults.isSdkLoggingEnabled)
    }

    func test_managerInit_preservesFlagWhenSetBeforeInit() {
        let defaults = MockUserDefaultsService()
        PELogger.isLoggingEnable = true

        _ = makeManager(userDefaults: defaults)

        XCTAssertTrue(defaults.isSdkLoggingEnabled)
    }

    // MARK: - Extension side (factory applies the persisted value)

    func test_factoryMake_appliesPersistedLoggingFlag() {
        let defaults = MockUserDefaultsService()
        defaults.isSdkLoggingEnabled = true

        _ = NotificationExtensionFactory.make(userDefaults: defaults)

        XCTAssertTrue(PELogger.isLoggingEnable)
    }

    func test_factoryMake_turnsLoggingOffWhenNothingPersisted() {
        PELogger.isLoggingEnable = true
        let defaults = MockUserDefaultsService()

        _ = NotificationExtensionFactory.make(userDefaults: defaults)

        XCTAssertFalse(PELogger.isLoggingEnable)
    }
}
