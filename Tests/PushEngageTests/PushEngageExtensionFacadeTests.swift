import XCTest
import UserNotifications
@testable import PushEngageExtension

private final class StubNotificationExtensionManager: NotificationExtensionType {
    private(set) var didReceiveRequests: [UNNotificationRequest] = []
    private(set) var didReceiveContents: [UNMutableNotificationContent] = []
    private(set) var expireRequests: [UNNotificationRequest] = []
    private(set) var customUIRequests: [UNNotificationRequest] = []
    var stubbedExpireContent: UNMutableNotificationContent?
    var stubbedCustomUIModel = CustomUIModel(title: "stub-title", body: "stub-body", image: nil, buttons: nil)

    func didReceiveNotificationExtensionRequest(_ request: UNNotificationRequest,
                                                bestContentHandler: UNMutableNotificationContent) {
        didReceiveRequests.append(request)
        didReceiveContents.append(bestContentHandler)
    }

    func serviceExtensionTimeWillExpire(_ request: UNNotificationRequest,
                                        content: UNMutableNotificationContent?) -> UNMutableNotificationContent? {
        expireRequests.append(request)
        return stubbedExpireContent
    }

    func getContentExtensionInfo(for request: UNNotificationRequest) -> CustomUIModel {
        customUIRequests.append(request)
        return stubbedCustomUIModel
    }
}

/// The facade's three statics are the extension-target customer API; these
/// tests pin the routing to the manager (design locked decision #2 / Task 7).
final class PushEngageExtensionFacadeTests: XCTestCase {

    private var stub: StubNotificationExtensionManager!
    private var originalManager: NotificationExtensionType!

    override func setUp() {
        super.setUp()
        stub = StubNotificationExtensionManager()
        originalManager = PushEngageExtension.manager
        PushEngageExtension.manager = stub
    }

    override func tearDown() {
        PushEngageExtension.manager = originalManager
        originalManager = nil
        stub = nil
        super.tearDown()
    }

    private func makeRequest() -> (UNNotificationRequest, UNMutableNotificationContent) {
        let content = UNMutableNotificationContent()
        content.userInfo = ["probe": "facade"]
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        return (request, content)
    }

    func test_didReceiveNotificationExtensionRequest_forwardsToManager() {
        let (request, content) = makeRequest()

        PushEngageExtension.didReceiveNotificationExtensionRequest(request, bestContentHandler: content)

        XCTAssertEqual(stub.didReceiveRequests.map(\.identifier), [request.identifier])
        XCTAssertTrue(stub.didReceiveContents.first === content)
    }

    func test_serviceExtensionTimeWillExpire_forwardsAndReturnsManagerValue() {
        let (request, content) = makeRequest()
        let marker = UNMutableNotificationContent()
        marker.title = "from-stub"
        stub.stubbedExpireContent = marker

        let result = PushEngageExtension.serviceExtensionTimeWillExpire(request, content: content)

        XCTAssertEqual(stub.expireRequests.map(\.identifier), [request.identifier])
        XCTAssertTrue(result === marker)
    }

    func test_getCustomUIPayLoad_forwardsAndReturnsManagerValue() {
        let (request, _) = makeRequest()

        let model = PushEngageExtension.getCustomUIPayLoad(for: request)

        XCTAssertEqual(stub.customUIRequests.map(\.identifier), [request.identifier])
        XCTAssertEqual(model.title, "stub-title")
    }
}
