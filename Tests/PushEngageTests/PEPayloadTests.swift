import XCTest
@testable import PushEngage
@testable import PushEngageExtension
/// Verifies the JSON Codable round-trip for the wire payload (`PEPayload`).
final class PEPayloadTests: XCTestCase {

    private func decode(_ json: String) throws -> PEPayload {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(PEPayload.self, from: data)
    }

    func test_decode_alertBlock() throws {
        let json = """
        {
          "aps": {
            "alert": {"title": "T", "body": "B", "subtitle": "S"},
            "badge": 3,
            "sound": "ping.caf",
            "mutable-content": 1,
            "content-available": 1,
            "category": "cat",
            "thread-id": "thread-9",
            "target-content-id": "tc-1"
          },
          "pe": {"tag": "x"}
        }
        """
        let payload = try decode(json)
        XCTAssertEqual(payload.aps?.alert?.title, "T")
        XCTAssertEqual(payload.aps?.alert?.body, "B")
        XCTAssertEqual(payload.aps?.alert?.subtitle, "S")
        XCTAssertEqual(payload.aps?.badge, 3)
        XCTAssertEqual(payload.aps?.sound, "ping.caf")
        XCTAssertEqual(payload.aps?.mutableContent, 1)
        XCTAssertEqual(payload.aps?.contentAvailable, 1)
        XCTAssertEqual(payload.aps?.category, "cat")
        XCTAssertEqual(payload.aps?.threadID, "thread-9")
        XCTAssertEqual(payload.aps?.targetContentID, "tc-1")
    }

    func test_decode_customBlock_mapsAllShortKeys() throws {
        let json = """
        {
          "aps": {},
          "pe": {
            "tag": "t-1",
            "att": "https://example.com/img.png",
            "u": "https://example.com/article",
            "rf": 1,
            "bi": 2,
            "t": "Title",
            "b": "Body",
            "ba": 5,
            "s": "sound.caf",
            "sb": "Sub",
            "ab": [{"a": "id1", "b": "text1"}],
            "dl": "myapp://x",
            "ad": {"k": "v"}
          }
        }
        """
        let payload = try decode(json)
        let custom = payload.custom
        XCTAssertEqual(custom?.tag, "t-1")
        XCTAssertEqual(custom?.attachmentURL, "https://example.com/img.png")
        XCTAssertEqual(custom?.launchURL, "https://example.com/article")
        XCTAssertEqual(custom?.isSponsered, 1)
        XCTAssertEqual(custom?.badgeIncrement, 2)
        XCTAssertEqual(custom?.title, "Title")
        XCTAssertEqual(custom?.body, "Body")
        XCTAssertEqual(custom?.badge, 5)
        XCTAssertEqual(custom?.sound, "sound.caf")
        XCTAssertEqual(custom?.subtitle, "Sub")
        XCTAssertEqual(custom?.actionButtons?.count, 1)
        XCTAssertEqual(custom?.actionButtons?.first?.id, "id1")
        XCTAssertEqual(custom?.actionButtons?.first?.text, "text1")
        XCTAssertEqual(custom?.deeplinking, "myapp://x")
        XCTAssertEqual(custom?.additionalData?["k"], "v")
    }

    func test_decode_missingCustomBlock_doesNotThrow() throws {
        let json = """
        {"aps": {"alert": {"title": "X", "body": "Y"}}}
        """
        let payload = try decode(json)
        XCTAssertNotNil(payload.aps)
        XCTAssertNil(payload.custom)
    }

    func test_decode_missingApsBlock_doesNotThrow() throws {
        let json = """
        {"pe": {"tag": "only-pe"}}
        """
        let payload = try decode(json)
        XCTAssertNil(payload.aps)
        XCTAssertEqual(payload.custom?.tag, "only-pe")
    }

    func test_actionButtonInfo_decode() throws {
        let data = Data(#"{"a":"action-id","b":"Visible Text"}"#.utf8)
        let button = try JSONDecoder().decode(ActionButtonInfo.self, from: data)
        XCTAssertEqual(button.id, "action-id")
        XCTAssertEqual(button.text, "Visible Text")
    }
}
