import XCTest
import UserNotifications
@testable import PushEngageExtension
final class CoreWiringTests: XCTestCase {

    func test_notificationExtensionFactory_buildsNotificationExtensionManager() {
        XCTAssertTrue(NotificationExtensionFactory.make() is NotificationExtensionManager,
                      "Factory must wire up a NotificationExtensionManager for the extension facade")
    }

    func test_coreServices_provideConcreteImplementations() {
        XCTAssertTrue(PECoreServices.getUserDefaults() is UserDefaultManager)
        XCTAssertTrue(PECoreServices.getRouter() is Router)
    }

    // Exercises the production default `entitlementsProvider` (Bundle.main).
    // The expectation derives from the host bundle's actual entitlements, so
    // the test holds in unsigned SPM runs and signed app-hosted runs alike.
    func test_dataManager_defaultEntitlementsProvider_readsHostBundle() {
        let sut = DataManager(userDefault: MockUserDefaultsService())

        let expected: String?
        switch Bundle.main.entitlements.value(forKey: .apsEnvironment) as? String {
        case "development": expected = "dev"
        case "production": expected = "prod"
        default: expected = nil
        }

        XCTAssertEqual(sut.getSubscriptionData().certEnv, expected)
    }

    func test_pushEngageExtensionFacade_getCustomUIPayLoad_routesToManager() {
        let content = UNMutableNotificationContent()
        content.userInfo = Fixtures.basicAlertPayload
        let request = UNNotificationRequest(identifier: "pe-facade", content: content, trigger: nil)

        let model = PushEngageExtension.getCustomUIPayLoad(for: request)

        XCTAssertEqual(model.title, PENotification(userInfo: Fixtures.basicAlertPayload).title ?? "")
    }

    // The attachment download and the viewed-tracking POST must not share a
    // Router: its in-flight `task` slot is unsynchronized, so a shared instance
    // lets overlapping notifications clobber each other's requests.
    func test_factoryMake_routesDownloadsAndLifecycleThroughDistinctRouters() {
        let downloadRouter = MockNetworkRouter()
        let lifecycleRouter = MockNetworkRouter()
        lifecycleRouter.enqueueSuccess(#"{"error_code":0,"error_message":null}"#)

        let manager = NotificationExtensionFactory.make(userDefaults: MockUserDefaultsService(),
                                                        downloadRouter: downloadRouter,
                                                        lifecycleRouter: lifecycleRouter)

        var payload = Fixtures.basicAlertPayload
        var pe = payload["pe"] as? [String: Any] ?? [:]
        pe["att"] = "https://example.test/image.png"
        payload["pe"] = pe
        let content = UNMutableNotificationContent()
        content.userInfo = payload
        let request = UNNotificationRequest(identifier: "router-wiring", content: content, trigger: nil)

        manager.didReceiveNotificationExtensionRequest(request, bestContentHandler: content)

        XCTAssertEqual(downloadRouter.downloadCallCount, 1)
        XCTAssertEqual(downloadRouter.requestCallCount, 0)
        XCTAssertEqual(lifecycleRouter.requestCallCount, 1)
        XCTAssertEqual(lifecycleRouter.downloadCallCount, 0)
    }
}
