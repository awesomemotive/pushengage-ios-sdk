import XCTest
import CoreData
@testable import PushEngage

/// IAMMessage / IAMAnalyticsEvent / IAMDisplayRecord model behaviour:
/// validity-window boundaries, upsert-in-context semantics, and — critically —
/// that corrupt persisted Data never crashes decoding (returns nil / fails
/// closed instead).
final class IAMMessageModelTests: XCTestCase {

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
        container = nil
        context = nil
        super.tearDown()
    }

    private func makeMessage(id: String = "m1",
                             startDate: Date? = nil,
                             endDate: Date? = nil,
                             actions: [String: IAMAction] = [:],
                             audience: IAMRawJSON? = nil,
                             frequency: IAMFrequency? = nil) throws -> IAMMessage {
        let response = IAMMessageResponse(
            id: id,
            position: .top,
            htmlContent: "<html></html>",
            displayDuration: 0,
            shouldDismissOnTap: false,
            actions: actions,
            startDate: startDate,
            endDate: endDate,
            priority: 1,
            audience: audience,
            frequency: frequency,
            trigger: IAMTriggerCondition(type: "custom", event: "evt", parameters: ["k": "v"])
        )
        let message = try IAMMessage.create(from: response, in: context)
        try context.save()
        return message
    }

    // MARK: - Validity window

    func testMessageWithNoDatesIsAlwaysValid() throws {
        XCTAssertTrue(try makeMessage().isValid)
    }

    func testMessageWithFutureStartDateIsNotValid() throws {
        let message = try makeMessage(startDate: Date().addingTimeInterval(3600))
        XCTAssertFalse(message.isValid)
    }

    func testMessageWithPastEndDateIsNotValid() throws {
        let message = try makeMessage(endDate: Date().addingTimeInterval(-3600))
        XCTAssertFalse(message.isValid)
    }

    func testMessageInsideItsDateWindowIsValid() throws {
        let message = try makeMessage(startDate: Date().addingTimeInterval(-3600),
                                      endDate: Date().addingTimeInterval(3600))
        XCTAssertTrue(message.isValid)
    }

    // MARK: - Upsert in context

    func testCreateWithSameIdReturnsTheSameObjectUpdated() throws {
        let first = try makeMessage(id: "same")
        let response = IAMMessageResponse(
            id: "same",
            position: .bottom,
            htmlContent: "<p>v2</p>",
            displayDuration: 5,
            shouldDismissOnTap: true,
            actions: [:],
            startDate: nil,
            endDate: nil,
            priority: 7,
            audience: nil,
            frequency: nil,
            trigger: IAMTriggerCondition(type: "auto", event: nil, parameters: nil)
        )
        let second = try IAMMessage.create(from: response, in: context)
        try context.save()

        XCTAssertEqual(first.objectID, second.objectID)
        XCTAssertEqual(second.position, "bottom")
        XCTAssertEqual(second.priority, 7)

        let request = IAMMessage.fetchRequest()
        XCTAssertEqual(try context.fetch(request).count, 1)
    }

    // MARK: - Decoding round trips

    func testDecodedFieldsRoundTripThroughPersistence() throws {
        let action = IAMAction(type: .openURL, parameters: ["url": "https://x.y"], label: "Go")
        let audienceJSON = #"{"match":"any","groups":[{"match":"all","conditions":[{"field":"plan","op":"eq","value":["pro"]}]}]}"#
        let audience = try IAMRawJSON(data: Data(audienceJSON.utf8))
        let frequency = IAMFrequency(type: .capped, count: 3, interval: 60)
        let message = try makeMessage(actions: ["go": action],
                                      audience: audience,
                                      frequency: frequency)

        XCTAssertEqual(message.decodedActions?["go"]?.type, .openURL)
        XCTAssertEqual(message.decodedActions?["go"]?.label, "Go")
        // Audience is persisted as raw JSON, so the stored bytes must still parse
        // to the same tree — the evaluator is what reads it, not a model.
        let storedAudience = try XCTUnwrap(message.audience)
        let storedTree = try JSONSerialization.jsonObject(with: storedAudience) as? [String: Any]
        XCTAssertEqual(storedTree?["match"] as? String, "any")
        XCTAssertEqual((storedTree?["groups"] as? [Any])?.count, 1)
        XCTAssertEqual(message.decodedFrequency?.count, 3)
        XCTAssertEqual(message.decodedTrigger?.parameters?["k"], "v")
    }

    // MARK: - Corrupt persisted data must not crash

    func testCorruptActionsDataDecodesAsNil() throws {
        let message = try makeMessage()
        message.actions = Data([0xFF, 0x00, 0x12])
        XCTAssertNil(message.decodedActions)
    }

    func testCorruptAudienceDataIsKeptVerbatimRatherThanDroppingTheCampaign() throws {
        // Audience is no longer decoded on read: unreadable JSON stays stored and
        // fails closed at evaluation time (see IAMAudienceEvaluationTests), so one
        // bad audience cannot take the whole campaign — or its siblings — down.
        let message = try makeMessage()
        message.audience = Data("{broken".utf8)
        XCTAssertEqual(message.audience, Data("{broken".utf8))
    }

    func testCorruptFrequencyDataDecodesAsNilAndFailsClosedForDisplay() throws {
        let message = try makeMessage()
        message.frequency = Data("not json at all".utf8)
        XCTAssertNil(message.decodedFrequency)
        XCTAssertFalse(message.canDisplay())
    }

    func testCorruptTriggerDataDecodesAsNil() throws {
        let message = try makeMessage()
        message.trigger = Data("[1,2".utf8)
        XCTAssertNil(message.decodedTrigger)
    }

    func testNilOptionalDataFieldsDecodeAsNil() throws {
        let message = try makeMessage()
        message.audience = nil
        message.frequency = nil
        message.trigger = nil
        message.actions = nil
        XCTAssertNil(message.audience)
        XCTAssertNil(message.decodedFrequency)
        XCTAssertNil(message.decodedTrigger)
        XCTAssertNil(message.decodedActions)
        XCTAssertTrue(message.canDisplay())
    }

    // MARK: - Display records

    func testDisplayRecordCreateLinksBackToTheMessage() throws {
        let message = try makeMessage()
        let record = IAMDisplayRecord.create(for: message, in: context)
        try context.save()

        XCTAssertEqual(record.message?.objectID, message.objectID)
        XCTAssertEqual((message.displayRecords as? Set<IAMDisplayRecord>)?.count, 1)
    }

    func testRecurringIntervalUsesTheMostRecentDisplayRecord() throws {
        let frequency = IAMFrequency(type: .recurring, count: -1, interval: 30)
        let message = try makeMessage(frequency: frequency)

        let old = IAMDisplayRecord.create(for: message, in: context)
        old.displayDate = Date().addingTimeInterval(-3600)
        let recent = IAMDisplayRecord.create(for: message, in: context)
        recent.displayDate = Date().addingTimeInterval(-5)
        try context.save()

        XCTAssertFalse(message.canDisplay())
    }

    // MARK: - Analytics event model

    func testAnalyticsEventCreateAssignsIdentityAndDate() throws {
        let event = try IAMAnalyticsEvent.create(type: .click,
                                                 messageId: "m1",
                                                 btnId: "cta",
                                                 btnText: "Learn More",
                                                 btnType: "open_url",
                                                 in: context)
        try context.save()

        XCTAssertEqual(event.eventType, "click")
        XCTAssertEqual(event.messageId, "m1")
        XCTAssertEqual(event.btnId, "cta")
        XCTAssertEqual(event.btnText, "Learn More")
        XCTAssertEqual(event.btnType, "open_url")
        XCTAssertLessThan(abs(event.eventDate.timeIntervalSinceNow), 5)
    }

    func testAnImpressionEventCarriesNoButtonPayload() throws {
        let event = try IAMAnalyticsEvent.create(type: .impression, messageId: "m1", in: context)
        try context.save()

        XCTAssertEqual(event.eventType, "impression")
        XCTAssertNil(event.btnId)
        XCTAssertNil(event.btnText)
        XCTAssertNil(event.btnType)
    }
}
