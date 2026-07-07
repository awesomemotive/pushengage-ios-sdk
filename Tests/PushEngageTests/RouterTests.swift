import XCTest
@testable import PushEngage
@testable import PushEngageExtension
/// Tier 7 — `Router` behavior under stubbed URLSession responses.
///
/// `Router.init(session:)` (added 2026-05-18) accepts an injectable URLSession so
/// the tests can wire it to `StubURLProtocol`. Production still uses the shared
/// ephemeral session by default.
final class RouterTests: XCTestCase {

    private var session: URLSession!
    private var sut: Router!

    /// A simple route that builds a valid URLRequest without elaborate inputs.
    private var simpleRoute: PERouter {
        return .checkSubscriberHash("test-hash")
    }

    override func setUp() {
        super.setUp()
        session = URLSession.stubbedSession()
        sut = Router(session: session)
    }

    override func tearDown() {
        StubURLProtocol.requestHandler = nil
        sut = nil
        session = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func httpResponse(_ statusCode: Int, url: URL = URL(string: "https://example.test")!) -> HTTPURLResponse {
        return HTTPURLResponse(url: url,
                               statusCode: statusCode,
                               httpVersion: "HTTP/1.1",
                               headerFields: nil)!
    }

    // MARK: - Happy path

    func test_request_success2xx_returnsData() {
        let body = Data(#"{"hello":"world"}"#.utf8)
        StubURLProtocol.requestHandler = { request in
            return (self.httpResponse(200), body)
        }

        let exp = expectation(description: "completion")
        sut.request(simpleRoute) { result in
            switch result {
            case .success(let data):
                XCTAssertEqual(data, body)
            case .failure(let error):
                XCTFail("Expected success, got \(error)")
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - 2xx with empty body
    //
    // URLProtocol delivers `Data()` (empty) when our handler returns nil, so
    // the Router's `data != nil` check is satisfied and the success branch
    // fires with an empty Data. There is no way to reach `.dataNotFound`
    // through dataTask in this stub setup — that branch only triggers when
    // URLSession reports `Data?` as actually nil, which our protocol layer
    // doesn't currently produce.
    func test_request_success2xx_butEmptyBody_returnsSuccessWithEmptyData() {
        StubURLProtocol.requestHandler = { _ in
            return (self.httpResponse(200), nil)
        }

        let exp = expectation(description: "completion")
        sut.request(simpleRoute) { result in
            if case .success(let data) = result {
                XCTAssertEqual(data.count, 0)
                exp.fulfill()
            } else {
                XCTFail("Got \(result)")
            }
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - 4xx with NetworkResponse JSON

    func test_request_4xxWithErrorJSON_returnsInvalidStatusCodeWithMessage() {
        let body = Data(#"{"error_code":42,"error_message":"bad request"}"#.utf8)
        StubURLProtocol.requestHandler = { _ in
            return (self.httpResponse(400), body)
        }

        let exp = expectation(description: "completion")
        sut.request(simpleRoute) { result in
            switch result {
            case .success:
                XCTFail("Expected failure")
            case .failure(let error):
                if case .invalidStatusCode(let message, let code) = error {
                    XCTAssertEqual(message, "bad request")
                    XCTAssertEqual(code, 400)
                } else {
                    XCTFail("Expected invalidStatusCode, got \(error)")
                }
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - 4xx with non-JSON body

    func test_request_4xxWithNonJSON_returnsInvalidStatusCodeWithGenericMessage() {
        let body = Data("plain-text-not-json".utf8)
        StubURLProtocol.requestHandler = { _ in
            return (self.httpResponse(403), body)
        }

        let exp = expectation(description: "completion")
        sut.request(simpleRoute) { result in
            switch result {
            case .success:
                XCTFail("Expected failure")
            case .failure(let error):
                if case .invalidStatusCode(let message, let code) = error {
                    XCTAssertEqual(message, "Not a network response")
                    XCTAssertEqual(code, 403)
                } else {
                    XCTFail("Expected invalidStatusCode, got \(error)")
                }
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - 4xx with no body
    //
    // As with the 2xx case, URLProtocol delivers Data() not nil, so the
    // `invalidStatusCodeHandler` runs against empty data, the JSON decode
    // fails, and we get the generic "Not a network response" message.
    func test_request_4xxNoBody_returnsInvalidStatusCodeWithGenericMessage() {
        StubURLProtocol.requestHandler = { _ in
            return (self.httpResponse(404), nil)
        }

        let exp = expectation(description: "completion")
        sut.request(simpleRoute) { result in
            if case .failure(.invalidStatusCode(let message, let code)) = result {
                XCTAssertEqual(message, "Not a network response")
                XCTAssertEqual(code, 404)
                exp.fulfill()
            } else {
                XCTFail("Got \(result)")
            }
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - Concurrency — no data race on `task` (run under `-enableThreadSanitizer YES`)

    func test_router_concurrentRequestAndCancel_noDataRace() {
        StubURLProtocol.requestHandler = { _ in (self.httpResponse(200), Data("{}".utf8)) }

        let iterations = 100
        let done = expectation(description: "all concurrent ops complete")
        done.expectedFulfillmentCount = iterations * 2
        for _ in 0..<iterations {
            DispatchQueue.global().async {
                self.sut.request(self.simpleRoute) { _ in done.fulfill() }
            }
            DispatchQueue.global().async {
                self.sut.cancel()
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 60.0)
    }

    // MARK: - 5xx

    func test_request_5xx_returnsInvalidStatusCode() {
        let body = Data(#"{"error_code":99,"error_message":"server fault"}"#.utf8)
        StubURLProtocol.requestHandler = { _ in
            return (self.httpResponse(503), body)
        }

        let exp = expectation(description: "completion")
        sut.request(simpleRoute) { result in
            if case .failure(.invalidStatusCode(let message, let code)) = result {
                XCTAssertEqual(message, "server fault")
                XCTAssertEqual(code, 503)
                exp.fulfill()
            } else {
                XCTFail("Got \(result)")
            }
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - Transport error

    func test_request_transportError_returnsNetworkError() {
        StubURLProtocol.requestHandler = { _ in
            throw URLError(.timedOut)
        }

        let exp = expectation(description: "completion")
        sut.request(simpleRoute) { result in
            if case .failure(.networkError) = result {
                exp.fulfill()
            } else {
                XCTFail("Expected networkError, got \(result)")
            }
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - Route .none (falls through default → base URL is still constructed)
    //
    // `.none` doesn't actually throw from asURLRequest — it builds a request
    // against `NetworkConstants.baseURL`. With no stub handler installed it
    // therefore takes the transport-error branch and returns `.networkError`.
    func test_request_noneRoute_buildsBaseURLAndProceeds() {
        // Stub returns success so we can verify .none doesn't trip an exception path.
        StubURLProtocol.requestHandler = { _ in
            return (self.httpResponse(200), Data("{}".utf8))
        }

        let exp = expectation(description: "completion")
        sut.request(.none) { result in
            if case .success = result {
                exp.fulfill()
            } else {
                XCTFail("`.none` route should build a valid base URL request, got \(result)")
            }
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - cancel

    func test_cancel_doesNotCrashWhenNoInFlightTask() {
        sut.cancel()
        XCTAssertTrue(true, "cancel() with no task must be a safe no-op")
    }

    func test_cancel_cancelsInFlightTask() {
        // Stub a slow handler so the task is still in-flight when we cancel.
        let group = DispatchGroup()
        group.enter()
        StubURLProtocol.requestHandler = { _ in
            group.wait(timeout: .now() + 1.0)
            return (self.httpResponse(200), Data())
        }

        let exp = expectation(description: "callback fires")
        sut.request(simpleRoute) { result in
            // We expect either a cancelled networkError or no callback at all.
            // The Router maps URLError(.cancelled) → .networkError.
            if case .failure = result {
                exp.fulfill()
            } else {
                XCTFail("Expected failure after cancel, got \(result)")
            }
        }
        // Give the task a moment to start, then cancel.
        Thread.sleep(forTimeInterval: 0.05)
        sut.cancel()
        group.leave()
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - Request building

    func test_request_invokesHandlerWithBuiltURLRequest() {
        var capturedURL: URL?
        StubURLProtocol.requestHandler = { request in
            capturedURL = request.url
            return (self.httpResponse(200), Data("{}".utf8))
        }

        let exp = expectation(description: "completion")
        sut.request(simpleRoute) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 2.0)

        XCTAssertNotNil(capturedURL)
        XCTAssertTrue(capturedURL!.absoluteString.contains("test-hash"),
                      "checkSubscriberHash route must embed the hash in its URL: \(capturedURL!.absoluteString)")
    }
}
