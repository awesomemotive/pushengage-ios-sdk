import XCTest
import CoreData
@testable import PushEngage

/// The analytics-event entity lost its `metadata` blob and gained typed `btn_*`
/// columns. Anyone holding a store written by the previous build must be able to
/// open it — the change is add/remove of optional attributes, which Core Data
/// resolves by lightweight migration.
///
/// The old model is rebuilt in code rather than kept as a second `.xcdatamodel`,
/// so this test still describes the shape it is migrating *from* once that shape
/// exists nowhere else.
final class IAMStoreMigrationTests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("IAMMigration-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        let url: URL = storeURL
        for url in [url, url.appendingPathExtension("shm"), url.appendingPathExtension("wal")] {
            try? FileManager.default.removeItem(at: url)
        }
        storeURL = nil
        try super.tearDownWithError()
    }

    /// The pre-change analytics entity: a `metadata` binary blob, no `btn_*`.
    private func legacyModel() -> NSManagedObjectModel {
        let event = NSEntityDescription()
        event.name = "IAMAnalyticsEvent"
        event.managedObjectClassName = "NSManagedObject"

        let eventDate = NSAttributeDescription()
        eventDate.name = "eventDate"
        eventDate.attributeType = .dateAttributeType

        let eventType = NSAttributeDescription()
        eventType.name = "eventType"
        eventType.attributeType = .stringAttributeType

        let identifier = NSAttributeDescription()
        identifier.name = "id"
        identifier.attributeType = .UUIDAttributeType

        let messageId = NSAttributeDescription()
        messageId.name = "messageId"
        messageId.attributeType = .stringAttributeType

        let metadata = NSAttributeDescription()
        metadata.name = "metadata"
        metadata.attributeType = .binaryDataAttributeType
        metadata.isOptional = true

        event.properties = [eventDate, eventType, identifier, messageId, metadata]

        let model = NSManagedObjectModel()
        model.entities = [event]
        return model
    }

    private func loadStore(model: NSManagedObjectModel) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "InAppMessaging", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        let loaded = expectation(description: "store loaded")
        container.loadPersistentStores { _, error in
            loadError = error
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 10)
        if let loadError = loadError { throw loadError }
        return container
    }

    func testAStoreWrittenByThePreviousBuildOpensUnderTheCurrentModel() throws {
        // Write a legacy analytics row, metadata blob and all.
        let legacy = try loadStore(model: legacyModel())
        let legacyContext = legacy.viewContext
        let entity = try XCTUnwrap(legacy.managedObjectModel.entitiesByName["IAMAnalyticsEvent"])
        let row = NSManagedObject(entity: entity, insertInto: legacyContext)
        row.setValue(UUID(), forKey: "id")
        row.setValue("click", forKey: "eventType")
        row.setValue("legacy-campaign", forKey: "messageId")
        row.setValue(Date(), forKey: "eventDate")
        row.setValue(try JSONSerialization.data(withJSONObject: ["elementId": "cta"]),
                     forKey: "metadata")
        try legacyContext.save()
        for store in legacy.persistentStoreCoordinator.persistentStores {
            try legacy.persistentStoreCoordinator.remove(store)
        }

        // Reopen the same file with the shipping model.
        let current = try loadStore(model: try XCTUnwrap(IAMCoreDataManager.managedObjectModel))
        let migrated = try current.viewContext.fetch(IAMAnalyticsEvent.fetchRequest())

        XCTAssertEqual(migrated.count, 1, "the queued click must survive the migration")
        let event = try XCTUnwrap(migrated.first)
        XCTAssertEqual(event.messageId, "legacy-campaign")
        XCTAssertEqual(event.eventType, "click")
        // The button payload was in the dropped blob, so it comes back empty rather
        // than wrong. Acceptable: IAM has never shipped, so no real queued click
        // exists, and an absent btn_* is simply an unattributed click.
        XCTAssertNil(event.btnId)
        XCTAssertNil(event.btnText)
        XCTAssertNil(event.btnType)
    }

    func testTheCurrentModelDeclaresTheButtonColumnsAndNoMetadataBlob() throws {
        let model = try XCTUnwrap(IAMCoreDataManager.managedObjectModel)
        let attributes = try XCTUnwrap(model.entitiesByName["IAMAnalyticsEvent"]?.attributesByName)

        for column in ["btnId", "btnText", "btnType"] {
            let attribute = try XCTUnwrap(attributes[column], "\(column) must exist")
            XCTAssertEqual(attribute.attributeType, .stringAttributeType)
            XCTAssertTrue(attribute.isOptional, "\(column) is absent on impressions")
        }
        XCTAssertNil(attributes["metadata"], "the JSON blob is gone")
        // Retained deliberately: a second event type then needs no migration.
        XCTAssertNotNil(attributes["eventType"])
    }

    func testANewlyWrittenEventRoundTripsThroughAFreshStore() throws {
        let container = try loadStore(model: try XCTUnwrap(IAMCoreDataManager.managedObjectModel))
        let context = container.viewContext

        _ = try IAMAnalyticsEvent.create(type: .click,
                                         messageId: "c-1",
                                         btnId: "close",
                                         btnText: "Not Now",
                                         btnType: "dismiss",
                                         in: context)
        try context.save()

        let stored = try XCTUnwrap(try context.fetch(IAMAnalyticsEvent.fetchRequest()).first)
        XCTAssertEqual(stored.btnId, "close")
        XCTAssertEqual(stored.btnText, "Not Now")
        XCTAssertEqual(stored.btnType, "dismiss")
    }
}
