import XCTest
@testable import PushEngage
@testable import PushEngageExtension
/// Locks in the URL shape produced by `PERouter.getSubscriberForfields`.
///
/// Historically this route used `NetworkConstants.getHashPath = "subscriber/%@/"`,
/// which emitted `…/subscriber/<hash>/?fields=…` with a stray trailing slash
/// before the query string. Every other iOS hash-path constant is unslashed,
/// and the Android equivalent (`@GET("subscriber/{id}")`) is unslashed too.
/// These tests pin the cleaned-up shape: no trailing slash on the path
/// component, with the `fields` query parameter still attached.
final class PERouterGetSubscriberPathTests: XCTestCase {

    private func makeURLString(hash: String, fields: [String]?) throws -> String {
        let request = try PERouter
            .getSubscriberForfields((hash: hash, fields: fields))
            .asURLRequest()
        return request.url?.absoluteString ?? ""
    }

    func test_url_pathEndsWithHash_noTrailingSlash_whenNoFields() throws {
        let url = try makeURLString(hash: "HASH123", fields: nil)
        XCTAssertTrue(url.hasSuffix("/subscriber/HASH123"),
                      "URL must end with '/subscriber/<hash>' with no trailing slash — got '\(url)'")
    }

    func test_url_pathHasNoTrailingSlashBeforeQuery_whenFieldsProvided() throws {
        let url = try makeURLString(hash: "HASH123", fields: ["country", "city"])
        XCTAssertTrue(url.contains("/subscriber/HASH123?"),
                      "URL must transition directly from '/subscriber/<hash>' to '?' — got '\(url)'")
        XCTAssertFalse(url.contains("/subscriber/HASH123/?"),
                       "URL must NOT contain '/subscriber/<hash>/?' (legacy trailing slash) — got '\(url)'")
    }

    func test_url_includesFieldsQueryParameter() throws {
        let url = try makeURLString(hash: "HASH123", fields: ["country", "city"])
        XCTAssertTrue(url.contains("fields=country%2Ccity") || url.contains("fields=country,city"),
                      "URL must carry the joined fields= query — got '\(url)'")
    }

    func test_method_isGET() throws {
        let request = try PERouter
            .getSubscriberForfields((hash: "H", fields: ["country"]))
            .asURLRequest()
        XCTAssertEqual(request.httpMethod, "GET")
    }
}
