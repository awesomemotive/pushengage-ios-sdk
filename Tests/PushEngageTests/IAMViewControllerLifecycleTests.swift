import XCTest
import CoreData
import WebKit
@testable import PushEngage

/// Teardown of the message view controller. `WKUserContentController` retains its
/// script message handler strongly, and the controller owns the `WKWebView` whose
/// configuration shares that same user content controller — so a controller that is
/// dismissed without detaching the bridge is kept alive by the cycle it sits in,
/// along with its `WKWebView` and its orientation observer.
final class IAMViewControllerLifecycleTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        try super.setUpWithError()

        let model = try XCTUnwrap(IAMCoreDataManager.managedObjectModel)
        container = NSPersistentContainer(name: "InAppMessaging", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]

        let expectation = expectation(description: "store loaded")
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        XCTAssertNil(loadError)
        context = container.viewContext
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    /// The load-bearing property: once the bridge is detached, nothing holds the
    /// controller and it deallocates. Before `detachBridge()` existed, the only path
    /// that removed the handler was `dismissMessage()`, so every other teardown route
    /// leaked the controller and its `WKWebView`.
    func testDetachingTheBridgeLetsTheControllerDeallocate() throws {
        weak var weakController: IAMViewController?

        try autoreleasepool {
            let controller = IAMViewController(message: try makeMessage())
            controller.loadViewIfNeeded()
            weakController = controller
            XCTAssertNotNil(weakController, "precondition: the controller is alive here")

            controller.detachBridge()
        }

        XCTAssertNil(weakController,
                     "the controller must not outlive its last owner once the bridge is detached")
    }

    /// Detaching twice is what production does on the background path followed by a
    /// normal dismissal, so it must stay a no-op rather than trapping.
    func testDetachingTheBridgeTwiceIsSafe() throws {
        let controller = IAMViewController(message: try makeMessage())
        controller.loadViewIfNeeded()

        controller.detachBridge()
        controller.detachBridge()
    }

    /// A controller that is never shown still registers the handler in `viewDidLoad`,
    /// so the same detach has to work without a presentation having happened.
    func testDetachingWorksWithoutEverBeingPresented() throws {
        weak var weakController: IAMViewController?

        try autoreleasepool {
            let controller = IAMViewController(message: try makeMessage())
            controller.loadViewIfNeeded()
            weakController = controller
            controller.detachBridge()
        }

        XCTAssertNil(weakController)
    }

    // MARK: - Helpers

    private func makeMessage(id: String = "m1") throws -> IAMMessage {
        let response = IAMMessageResponse(
            id: id,
            position: .top,
            htmlContent: "<html><body>hi</body></html>",
            displayDuration: 0,
            shouldDismissOnTap: false,
            actions: [:],
            startDate: nil,
            endDate: nil,
            priority: 1,
            audience: nil,
            frequency: nil,
            trigger: IAMTriggerCondition(type: "custom", event: "evt", parameters: ["k": "v"])
        )
        let message = try IAMMessage.create(from: response, in: context)
        try context.save()
        return message
    }
}
