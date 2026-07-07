import XCTest
@testable import PushEngage
@testable import PushEngageExtension
final class ParameterEncoderTests: XCTestCase {

    // MARK: - URLParameterEncoder

    func test_urlEncoder_appendsQueryItemsSortedAscending() throws {
        var request = URLRequest(url: URL(string: "https://example.test/api")!)
        try URLParameterEncoder.encode(urlRequest: &request,
                                       with: ["b": "2", "a": "1", "c": "3"])

        let url = request.url!
        // Default sort is ascending, so the query string should be a=1&b=2&c=3
        XCTAssertEqual(url.query, "a=1&b=2&c=3")
    }

    func test_urlEncoder_appendsQueryItemsSortedDescending() throws {
        var request = URLRequest(url: URL(string: "https://example.test/api")!)
        try URLParameterEncoder.encode(urlRequest: &request,
                                       with: ["a": "1", "b": "2"],
                                       isSortedDesc: true)

        XCTAssertEqual(request.url?.query, "b=2&a=1")
    }

    func test_urlEncoder_emptyParameters_leavesURLUnchanged() throws {
        var request = URLRequest(url: URL(string: "https://example.test/api")!)
        try URLParameterEncoder.encode(urlRequest: &request, with: [:])
        XCTAssertNil(request.url?.query)
    }

    func test_urlEncoder_percentEncodesValuesWithSpecialChars() throws {
        var request = URLRequest(url: URL(string: "https://example.test/api")!)
        try URLParameterEncoder.encode(urlRequest: &request,
                                       with: ["q": "hello world&more"])

        XCTAssertNotNil(request.url?.query)
        XCTAssertTrue(request.url!.query!.contains("q="),
                      "Query string must contain the key")
        // The space and ampersand should be percent-encoded
        XCTAssertFalse(request.url!.query!.contains(" "),
                       "Literal spaces must be encoded")
    }

    func test_urlEncoder_missingURL_throws() {
        var request = URLRequest(url: URL(string: "https://example.test")!)
        request.url = nil

        XCTAssertThrowsError(try URLParameterEncoder.encode(urlRequest: &request,
                                                            with: ["k": "v"])) { error in
            if case PEError.missingURL = error {
                // ok
            } else {
                XCTFail("Expected missingURL, got \(error)")
            }
        }
    }

    // MARK: - JSONParameterEncoder — Codable overload

    private struct PayloadBody: Codable, Equatable {
        let key: String
        let count: Int
    }

    func test_jsonEncoder_codableObject_setsHTTPBody() throws {
        var request = URLRequest(url: URL(string: "https://example.test/api")!)
        let body = PayloadBody(key: "k", count: 7)

        try JSONParameterEncoder.encode(urlRequest: &request, with: body)

        XCTAssertNotNil(request.httpBody)
        let decoded = try JSONDecoder().decode(PayloadBody.self, from: request.httpBody!)
        XCTAssertEqual(decoded, body)
    }

    // MARK: - JSONParameterEncoder — Parameters (dictionary) overload

    func test_jsonEncoder_dictionary_setsHTTPBody() throws {
        var request = URLRequest(url: URL(string: "https://example.test/api")!)
        let params: Parameters = ["name": "Alice", "age": 30]

        try JSONParameterEncoder.encode(urlRequest: &request, for: params)

        XCTAssertNotNil(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
        XCTAssertEqual(json?["name"] as? String, "Alice")
        XCTAssertEqual(json?["age"] as? Int, 30)
    }

    // NOTE: A test for "non-JSON value in dictionary throws encodingFailed" is
    // intentionally omitted. `JSONSerialization.data(withJSONObject:)` raises an
    // Objective-C `NSInvalidArgumentException` for invalid types (e.g. `Date`) —
    // not a Swift Error — so the `do { } catch` in `JSONParameterEncoder.encode`
    // cannot intercept it. The encoder's failure path is therefore unreachable
    // for that specific input class without wrapping in a `@try`/`@catch` bridge.
}
