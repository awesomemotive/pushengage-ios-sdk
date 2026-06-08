import XCTest
@testable import PushEngage

/// Locks in `PERouter.identifySubscriber` (PUT subscriber/{hash} with field-map body)
/// and `PERouter.logoutSubscriberFields` (DELETE subscriber/{hash}/fields with body).
final class PERouterIdentifyLogoutTests: XCTestCase {

    // MARK: - identifySubscriber

    func test_identify_url_endsWithSubscriberHash() throws {
        let request = try PERouter
            .identifySubscriber((hash: "HASH123", fields: ["email": "a@b.com"]))
            .asURLRequest()
        let url = request.url?.absoluteString ?? ""
        XCTAssertTrue(url.hasSuffix("/subscriber/HASH123"),
                      "identify URL must end with '/subscriber/<hash>' — got '\(url)'")
    }

    func test_identify_method_isPUT() throws {
        let request = try PERouter
            .identifySubscriber((hash: "H", fields: ["email": "a@b.com"]))
            .asURLRequest()
        XCTAssertEqual(request.httpMethod, "PUT")
    }

    func test_identify_body_isFieldsJSONOnly() throws {
        let request = try PERouter
            .identifySubscriber((hash: "H", fields: ["email": "a@b.com", "profile_id": "user-42"]))
            .asURLRequest()
        guard let body = request.httpBody else {
            XCTFail("identify must have a body"); return
        }
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["email"] as? String, "a@b.com")
        XCTAssertEqual(json?["profile_id"] as? String, "user-42")
        XCTAssertEqual(json?.count, 2,
                       "identify body must contain exactly the supplied fields (no hash, no envelope)")
    }

    func test_identify_headers_includeStandardSet() throws {
        let request = try PERouter
            .identifySubscriber((hash: "H", fields: ["email": "a@b.com"]))
            .asURLRequest()
        let headers = request.allHTTPHeaderFields ?? [:]
        XCTAssertEqual(headers["Content-Type"], "application/json")
        XCTAssertEqual(headers["X-Pe-Client"], "iOS")
        XCTAssertEqual(headers["X-Pe-Sdk-Version"], NetworkConstants.sdkVersion)
    }

    // MARK: - logoutSubscriberFields

    func test_logout_url_endsWithFieldsSuffix() throws {
        let request = try PERouter
            .logoutSubscriberFields((hash: "HASH123", fieldNames: ["email"]))
            .asURLRequest()
        let url = request.url?.absoluteString ?? ""
        XCTAssertTrue(url.hasSuffix("/subscriber/HASH123/fields"),
                      "logout URL must end with '/subscriber/<hash>/fields' — got '\(url)'")
    }

    func test_logout_method_isDELETE() throws {
        let request = try PERouter
            .logoutSubscriberFields((hash: "H", fieldNames: ["email"]))
            .asURLRequest()
        XCTAssertEqual(request.httpMethod, "DELETE")
    }

    func test_logout_body_isBareJSONArray() throws {
        let request = try PERouter
            .logoutSubscriberFields((hash: "H", fieldNames: ["email", "profile_id"]))
            .asURLRequest()
        guard let body = request.httpBody else {
            XCTFail("logout must have a body"); return
        }
        let decoded = try JSONSerialization.jsonObject(with: body)
        guard let names = decoded as? [String] else {
            XCTFail("logout body must be a bare JSON array — got \(decoded)"); return
        }
        XCTAssertEqual(Set(names), Set(["email", "profile_id"]))
    }

    func test_logout_headers_includeStandardSet() throws {
        let request = try PERouter
            .logoutSubscriberFields((hash: "H", fieldNames: ["email"]))
            .asURLRequest()
        let headers = request.allHTTPHeaderFields ?? [:]
        XCTAssertEqual(headers["Content-Type"], "application/json")
        XCTAssertEqual(headers["X-Pe-Client"], "iOS")
    }
}
