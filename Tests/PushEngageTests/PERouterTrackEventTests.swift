import XCTest
@testable import PushEngage

/// Locks in `PERouter.trackEvent` route behaviour: URL contains
/// `events/track`, method is POST, body is the JSON-encoded TrackEventRequest,
/// and the standard headers are populated.
final class PERouterTrackEventTests: XCTestCase {

    private func sampleRequest() -> TrackEventRequest {
        return TrackEventRequest(
            siteId: 7777,
            deviceTokenHash: "hash-1",
            eventName: "MySite.AddToCart",
            provider: TrackEventRequest.defaultProvider,
            eventType: TrackEventRequest.defaultEventType,
            profileId: "user-42",
            data: ["plan": .string("pro"), "amount": .double(19.99)]
        )
    }

    private func makeRequest() throws -> URLRequest {
        return try PERouter.trackEvent(sampleRequest()).asURLRequest()
    }

    func test_url_endsWithEventsTrack() throws {
        let request = try makeRequest()
        let url = request.url?.absoluteString ?? ""
        XCTAssertTrue(url.hasSuffix("/events/track"),
                      "trackEvent URL must end with '/events/track' — got '\(url)'")
    }

    func test_method_isPOST() throws {
        let request = try makeRequest()
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func test_headers_includeStandardSet() throws {
        let request = try makeRequest()
        let headers = request.allHTTPHeaderFields ?? [:]
        XCTAssertEqual(headers["Content-Type"], "application/json")
        XCTAssertEqual(headers["X-Pe-Client"], "iOS")
        XCTAssertEqual(headers["X-Pe-Sdk-Version"], NetworkConstants.sdkVersion)
    }

    func test_body_isJSONEncodedTrackEventRequest() throws {
        let request = try makeRequest()
        guard let body = request.httpBody else {
            XCTFail("trackEvent must have a JSON body")
            return
        }
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["site_id"] as? Int, 7777)
        XCTAssertEqual(json?["device_token_hash"] as? String, "hash-1")
        XCTAssertEqual(json?["event_name"] as? String, "MySite.AddToCart")
        XCTAssertEqual(json?["provider"] as? String, "PushEngage")
        XCTAssertEqual(json?["event_type"] as? String, "PushEngage.CustomEvent")
        XCTAssertEqual(json?["profile_id"] as? String, "user-42")
        let data = json?["data"] as? [String: Any]
        XCTAssertEqual(data?["plan"] as? String, "pro")
        XCTAssertEqual(data?["amount"] as? Double, 19.99)
    }

    func test_body_omitsProfileIdAsExplicitNullWhenNotSet() throws {
        let req = TrackEventRequest(
            siteId: 1,
            deviceTokenHash: "h",
            eventName: "e",
            provider: TrackEventRequest.defaultProvider,
            eventType: TrackEventRequest.defaultEventType,
            profileId: nil,
            data: [:]
        )
        let request = try PERouter.trackEvent(req).asURLRequest()
        guard let body = request.httpBody else {
            XCTFail("body missing"); return
        }
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        // Codable's default encoding for nil Optionals is to omit the key entirely.
        // This locks that behavior in so the wire payload stays minimal.
        XCTAssertNil(json?["profile_id"],
                     "profile_id key must be omitted when nil — got \(String(describing: json?["profile_id"]))")
    }

    func test_defaultConstants() {
        XCTAssertEqual(TrackEventRequest.defaultProvider, "PushEngage")
        XCTAssertEqual(TrackEventRequest.defaultEventType, "PushEngage.CustomEvent")
    }

    // MARK: - Bool wire-shape parity (Android sends JSON booleans, not 0/1)

    func test_body_bool_value_serializesAsJSONBoolean_notInteger() throws {
        let req = TrackEventRequest(
            siteId: 1,
            deviceTokenHash: "h",
            eventName: "e",
            provider: TrackEventRequest.defaultProvider,
            eventType: TrackEventRequest.defaultEventType,
            profileId: nil,
            data: ["is_trial": .bool(true)]
        )
        let request = try PERouter.trackEvent(req).asURLRequest()
        guard let body = request.httpBody else { XCTFail("body missing"); return }
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let data = json?["data"] as? [String: Any]
        // Bool must serialize as JSON true, not as integer 1 (Android wire parity).
        // Inspect via NSNumber bridging: JSON booleans round-trip to NSNumber
        // with CFGetTypeID == CFBooleanGetTypeID. Integers do not.
        let raw = data?["is_trial"]
        guard let number = raw as? NSNumber else {
            XCTFail("is_trial not encoded as NSNumber-compatible value; got \(String(describing: raw))")
            return
        }
        XCTAssertEqual(CFGetTypeID(number), CFBooleanGetTypeID(),
                       "Bool value must serialize as JSON boolean (CFBoolean), not integer — got \(number)")
    }

    func test_body_int_value_serializesAsJSONInteger() throws {
        let req = TrackEventRequest(
            siteId: 1,
            deviceTokenHash: "h",
            eventName: "e",
            provider: TrackEventRequest.defaultProvider,
            eventType: TrackEventRequest.defaultEventType,
            profileId: nil,
            data: ["count": .int(5)]
        )
        let request = try PERouter.trackEvent(req).asURLRequest()
        guard let body = request.httpBody else { XCTFail("body missing"); return }
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let data = json?["data"] as? [String: Any]
        XCTAssertEqual(data?["count"] as? Int, 5)
    }
}
