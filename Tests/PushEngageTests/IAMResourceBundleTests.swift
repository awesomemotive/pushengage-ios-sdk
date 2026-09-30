import XCTest
import CoreData
@testable import PushEngage

final class IAMResourceBundleTests: XCTestCase {

    func testResourceBundleContainsCompiledCoreDataModel() {
        let url = PEResources.bundle.url(forResource: "InAppMessaging", withExtension: "momd")
        XCTAssertNotNil(url, "InAppMessaging.momd must ship in the resource bundle")
    }

    func testCoreDataModelLoadsWithExpectedEntities() throws {
        let model = try XCTUnwrap(IAMCoreDataManager.managedObjectModel)
        let entityNames = Set(model.entities.compactMap { $0.name })
        XCTAssertTrue(entityNames.contains("IAMMessage"))
        XCTAssertTrue(entityNames.contains("IAMDisplayRecord"))
        XCTAssertTrue(entityNames.contains("IAMAnalyticsEvent"))
    }

    func testCoreDataManagerRoundTripsWithoutCrashing() throws {
        let manager = IAMCoreDataManager.shared
        XCTAssertTrue(manager.isStoreAvailable)

        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "IAMMessage")
        XCTAssertNoThrow(try manager.executeFetchRequest(request))
    }
}
