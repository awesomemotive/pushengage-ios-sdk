import XCTest
@testable import PushEngage

/// Real-backend IAM network tests mirroring Android's IAMNetworkServiceImplTest,
/// per the backend contract §2: metadata gates (1h cache, iam_status, version),
/// host discovery via the metadata api block, campaign parsing, and the
/// per-event analytics POSTs.
final class IAMNetworkServiceImplTests: XCTestCase {

    private var prefs: IAMPrefs!
    private var configuration: IAMConfiguration!
    private var service: IAMNetworkServiceImpl!

    private static let suiteName = "IAMNetworkServiceImplTests"

    override func setUpWithError() throws {
        try super.setUpWithError()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        defaults.removePersistentDomain(forName: Self.suiteName)
        prefs = IAMPrefs(defaults: defaults)
        configuration = IAMConfiguration()
        configuration.siteKey = "site-key-1"
        configuration.environment = .staging

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [IAMURLProtocolStub.self]
        let session = URLSession(configuration: sessionConfiguration)

        IAMURLProtocolStub.reset()
        service = IAMNetworkServiceImpl(session: session, prefs: prefs, configuration: configuration)
    }

    override func tearDown() {
        IAMURLProtocolStub.reset()
        UserDefaults(suiteName: Self.suiteName)?.removePersistentDomain(forName: Self.suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    private func metadataJSON(version: String = "v-2",
                              status: String = "active",
                              backendCdn: String? = "https://campaigns.example.com/p/v1/",
                              iamAnalytics: String? = "https://analytics.example.com/p/v1/") -> String {
        let cdn = backendCdn.map { "\"backend_cdn\": \"\($0)\"," } ?? ""
        let analytics = iamAnalytics.map { "\"iam_analytics\": \"\($0)\"," } ?? ""
        return """
        { "error_code": 0, "data": {
            "version": "\(version)", "site_id": 5276, "iam_status": "\(status)",
            "api": { \(cdn) \(analytics) "backend": "", "log": "" }
        } }
        """
    }

    private let campaignsJSON = """
    { "error_code": 0, "data": [ {
        "id": "c-1", "position": "center", "htmlContent": "<html></html>",
        "displayDuration": 0, "shouldDismissOnTap": false, "priority": 1,
        "startDate": "2025-07-01T00:00:00Z", "endDate": null,
        "trigger": { "type": "custom", "event": "evt", "parameters": { "k": "v" } },
        "frequency": { "type": "capped", "count": 3, "interval": 86400 },
        "actions": { "ok": { "type": "dismiss", "label": "OK" } }
    } ] }
    """

    private func syncOnce() -> Result<IAMCampaignSyncResult, Error>? {
        var captured: Result<IAMCampaignSyncResult, Error>?
        let expectation = expectation(description: "sync")
        service.syncCampaigns(siteKey: "site-key-1", storedVersion: prefs.iamVersion) { result in
            captured = result
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        return captured
    }

    // MARK: - Metadata is always checked (no client-side freshness gate) (§2.1)

    func testMetadataIsCheckedEvenWhenRecentlyFetched() throws {
        // No client-side freshness gate: a recent fetch must not suppress the
        // metadata call — the version is only observable by fetching metadata,
        // so it is checked on every sync. The version gate still avoids the
        // campaigns fetch when nothing changed.
        prefs.iamMetadataFetchedAt = Date().timeIntervalSince1970 - 60 // 1 min old — must be ignored
        IAMURLProtocolStub.stub(pathContaining: "iam/campaigns/metadata", body: metadataJSON())
        IAMURLProtocolStub.stub(pathContaining: "iam/campaigns?", body: campaignsJSON)

        _ = try XCTUnwrap(syncOnce())
        XCTAssertEqual(
            IAMURLProtocolStub.requests.filter { $0.url!.absoluteString.contains("metadata") }.count, 1,
            "metadata is fetched regardless of last-fetch time"
        )
    }

    func testInactiveStatusYieldsInactiveResult() throws {
        IAMURLProtocolStub.stub(pathContaining: "iam/campaigns/metadata",
                                body: metadataJSON(status: "paused"))
        let result = try XCTUnwrap(syncOnce())
        XCTAssertEqual(try result.get().status, .inactive)
        // No campaigns fetch happened
        XCTAssertEqual(IAMURLProtocolStub.requests.count, 1)
    }

    func testUnchangedVersionSkipsTheCampaignsFetch() throws {
        prefs.iamVersion = "v-2"
        IAMURLProtocolStub.stub(pathContaining: "iam/campaigns/metadata", body: metadataJSON(version: "v-2"))
        let result = try XCTUnwrap(syncOnce())
        XCTAssertEqual(try result.get().status, .unchanged)
        XCTAssertEqual(IAMURLProtocolStub.requests.count, 1)
    }

    func testMissingVersionIsAnError() throws {
        IAMURLProtocolStub.stub(pathContaining: "iam/campaigns/metadata",
                                body: #"{ "error_code": 0, "data": { "iam_status": "active" } }"#)
        let result = try XCTUnwrap(syncOnce())
        XCTAssertThrowsError(try result.get())
    }

    func testMetadataHTTPFailureIsAnError() throws {
        IAMURLProtocolStub.stub(pathContaining: "iam/campaigns/metadata", statusCode: 500, body: "{}")
        let result = try XCTUnwrap(syncOnce())
        XCTAssertThrowsError(try result.get())
    }

    // MARK: - Active sync + host discovery (§2.1/§2.2)

    func testActiveSyncFetchesCampaignsFromTheAdvertisedHost() throws {
        IAMURLProtocolStub.stub(pathContaining: "iam/campaigns/metadata", body: metadataJSON())
        IAMURLProtocolStub.stub(pathContaining: "iam/campaigns?", body: campaignsJSON)

        let result = try XCTUnwrap(try XCTUnwrap(syncOnce()).get())
        XCTAssertEqual(result.status, .active)
        XCTAssertEqual(result.version, "v-2")
        XCTAssertEqual(result.campaigns.count, 1)
        XCTAssertEqual(result.campaigns.first?.id, "c-1")
        XCTAssertEqual(result.campaigns.first?.actions["ok"]?.label, "OK")
        XCTAssertEqual(result.campaignsHost, "https://campaigns.example.com/p/v1/")
        XCTAssertEqual(result.analyticsHost, "https://analytics.example.com/p/v1/")

        let campaignsRequest = try XCTUnwrap(
            IAMURLProtocolStub.requests.first { $0.url!.absoluteString.contains("iam/campaigns?") }
        )
        let url = campaignsRequest.url!.absoluteString
        XCTAssertTrue(url.hasPrefix("https://campaigns.example.com/p/v1/iam/campaigns?"))
        XCTAssertTrue(url.contains("version=v-2"))
        XCTAssertTrue(url.contains("site_key=site-key-1"))
    }

    func testEmptyApiFieldsFallBackToTheBaseHost() throws {
        IAMURLProtocolStub.stub(pathContaining: "iam/campaigns/metadata",
                                body: metadataJSON(backendCdn: "", iamAnalytics: ""))
        IAMURLProtocolStub.stub(pathContaining: "iam/campaigns?", body: campaignsJSON)

        let result = try XCTUnwrap(try XCTUnwrap(syncOnce()).get())
        XCTAssertEqual(result.campaignsHost, IAMNetworkConstants.stagingIAMBaseURL)
        XCTAssertEqual(result.analyticsHost, IAMNetworkConstants.stagingIAMBaseURL)
    }

    func testMetadataIsFetchedFromTheEnvironmentIAMHost() throws {
        IAMURLProtocolStub.stub(pathContaining: "iam/campaigns/metadata",
                                body: metadataJSON(status: "paused"))
        _ = syncOnce()
        let url = try XCTUnwrap(IAMURLProtocolStub.requests.first?.url?.absoluteString)
        XCTAssertTrue(url.hasPrefix(IAMNetworkConstants.stagingIAMBaseURL), "got \(url)")
        XCTAssertTrue(url.contains("site_key=site-key-1"))
    }

    func testProductionMetadataIsFetchedFromClientsApi() throws {
        configuration.environment = .production
        IAMURLProtocolStub.stub(pathContaining: "iam/campaigns/metadata",
                                body: metadataJSON(status: "paused"))
        _ = syncOnce()
        let url = try XCTUnwrap(IAMURLProtocolStub.requests.first?.url?.absoluteString)
        XCTAssertTrue(url.hasPrefix("https://clients-api.pushengage.com/p/v1/iam/campaigns/metadata?"),
                      "got \(url)")
    }

    func testProductionIAMHostMatchesAndroid() {
        XCTAssertEqual(IAMNetworkConstants.productionIAMBaseURL, "https://clients-api.pushengage.com/p/v1/")
    }

    func testStagingIAMHostIsUnchanged() {
        XCTAssertEqual(IAMNetworkConstants.stagingIAMBaseURL, "https://staging-dexter2.pushengage.com/p/v1/")
    }

    func testBaseUrlOverrideWinsOverEnvironmentConstant() throws {
        prefs.iamBaseUrl = "https://override.example.com/p/v1/"
        IAMURLProtocolStub.stub(pathContaining: "iam/campaigns/metadata",
                                body: metadataJSON(status: "paused"))
        _ = syncOnce()
        let url = try XCTUnwrap(IAMURLProtocolStub.requests.first?.url?.absoluteString)
        XCTAssertTrue(url.hasPrefix("https://override.example.com/p/v1/"), "got \(url)")
    }

    // MARK: - Analytics (§2.3)

    func testAnalyticsPostsOnePayloadPerEventToTheAnalyticsHost() throws {
        prefs.iamAnalyticsUrl = "https://analytics.example.com/p/v1/"
        IAMURLProtocolStub.stub(pathContaining: "iam/campaigns/analytics", body: "{}")

        let payloads = [
            IAMAnalyticsPayload(campaignId: "c-1", impression: 1, click: 0),
            IAMAnalyticsPayload(campaignId: "c-1", impression: 0, click: 1, btnId: "ok")
        ]
        let outcome = try XCTUnwrap(report(payloads).get())

        XCTAssertTrue(outcome.allSynced)
        XCTAssertEqual(outcome.syncedIndices, [0, 1])
        let requests = IAMURLProtocolStub.requests
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url!.absoluteString.hasPrefix("https://analytics.example.com/p/v1/iam/campaigns/analytics"))
            XCTAssertTrue(request.url!.absoluteString.contains("site_key=site-key-1"))
        }
        let clickBody = try XCTUnwrap(IAMURLProtocolStub.bodies.last)
        let clickJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: clickBody) as? [String: Any])
        XCTAssertEqual(clickJSON["campaign_id"] as? String, "c-1")
        XCTAssertEqual(clickJSON["click"] as? Int, 1)
        XCTAssertEqual(clickJSON["impression"] as? Int, 0)
        XCTAssertEqual(clickJSON["btn_id"] as? String, "ok")
    }

    func testAnalyticsWithoutSiteKeyFails() throws {
        configuration.siteKey = nil

        XCTAssertThrowsError(try report([payload(campaignId: "c")]).get(),
                             "a missing site key means nothing was attempted")
        XCTAssertTrue(IAMURLProtocolStub.requests.isEmpty)
    }

    func testAnalyticsServerErrorStopsTheBatchAndReportsTheFailure() throws {
        prefs.iamAnalyticsUrl = "https://analytics.example.com/p/v1/"
        IAMURLProtocolStub.stub(pathContaining: "iam/campaigns/analytics", statusCode: 500, body: "{}")

        let outcome = try XCTUnwrap(report([payload(campaignId: "c")]).get())

        XCTAssertFalse(outcome.allSynced)
        XCTAssertTrue(outcome.syncedIndices.isEmpty)
        XCTAssertNotNil(outcome.failure)
    }

    func testAnalyticsReportsTheEventsDeliveredBeforeAMidBatchFailure() throws {
        prefs.iamAnalyticsUrl = "https://analytics.example.com/p/v1/"
        IAMURLProtocolStub.stub(pathContaining: "iam/campaigns/analytics",
                                statusCodes: [200, 200, 503], body: "{}")

        let outcome = try XCTUnwrap(report([payload(campaignId: "c-0"),
                                            payload(campaignId: "c-1"),
                                            payload(campaignId: "c-2"),
                                            payload(campaignId: "c-3")]).get())

        XCTAssertEqual(outcome.syncedIndices, [0, 1],
                       "the delivered payloads must be reported so they are not re-POSTed")
        XCTAssertFalse(outcome.allSynced)
        XCTAssertEqual(IAMURLProtocolStub.requests.count, 3,
                       "the batch stops at the transient failure")
    }

    func testAnalyticsSkipsAPermanentlyRejectedPayloadAndSendsTheRest() throws {
        for code in [400, 409, 413, 422] {
            IAMURLProtocolStub.reset()
            prefs.iamAnalyticsUrl = "https://analytics.example.com/p/v1/"
            IAMURLProtocolStub.stub(pathContaining: "iam/campaigns/analytics",
                                    statusCodes: [code, 200, 200], body: "{}")

            let outcome = try XCTUnwrap(report([payload(campaignId: "c-0"),
                                                payload(campaignId: "c-1"),
                                                payload(campaignId: "c-2")]).get())

            XCTAssertEqual(IAMURLProtocolStub.requests.count, 3,
                           "HTTP \(code) must not abort the batch")
            XCTAssertEqual(outcome.syncedIndices, [0, 1, 2],
                           "HTTP \(code) is permanent, so the payload is dropped rather than requeued")
            XCTAssertTrue(outcome.allSynced, "HTTP \(code) leaves nothing queued")
        }
    }

    func testAnalyticsRetriesRatherThanDroppingOnARetryableClientError() throws {
        for code in [408, 429, 401, 403] {
            IAMURLProtocolStub.reset()
            prefs.iamAnalyticsUrl = "https://analytics.example.com/p/v1/"
            IAMURLProtocolStub.stub(pathContaining: "iam/campaigns/analytics",
                                    statusCodes: [code, 200, 200], body: "{}")

            let outcome = try XCTUnwrap(report([payload(campaignId: "c-0"),
                                                payload(campaignId: "c-1"),
                                                payload(campaignId: "c-2")]).get())

            XCTAssertEqual(IAMURLProtocolStub.requests.count, 1,
                           "HTTP \(code) must stop the batch, not skip past it")
            XCTAssertTrue(outcome.syncedIndices.isEmpty,
                          "HTTP \(code) is retryable, so nothing may be cleared")
            XCTAssertFalse(outcome.allSynced)
        }
    }

    // MARK: - Helpers

    private func payload(campaignId: String) -> IAMAnalyticsPayload {
        IAMAnalyticsPayload(campaignId: campaignId, impression: 1, click: 0)
    }

    private func report(_ payloads: [IAMAnalyticsPayload]) -> Result<IAMReportOutcome, Error> {
        var captured: Result<IAMReportOutcome, Error>!
        let expectation = expectation(description: "analytics")
        service.reportAnalytics(payloads: payloads) {
            captured = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        return captured
    }
}

// MARK: - URLProtocol stub

/// Intercepts URLSession traffic for the stubbed session; matches stubs by URL
/// substring and records every request (plus POST bodies) for assertions.
final class IAMURLProtocolStub: URLProtocol {

    struct Stub {
        /// Consumed one per matching request; the last code repeats once exhausted.
        let statusCodes: [Int]
        let body: Data
    }

    private static let lock = NSLock()
    private static var stubs: [(match: String, stub: Stub)] = []
    private static var matchCounts: [String: Int] = [:]
    private(set) static var requests: [URLRequest] = []
    private(set) static var bodies: [Data] = []

    static func stub(pathContaining match: String, statusCode: Int = 200, body: String) {
        stub(pathContaining: match, statusCodes: [statusCode], body: body)
    }

    /// Answers successive requests matching `match` with `statusCodes` in order.
    static func stub(pathContaining match: String, statusCodes: [Int], body: String) {
        lock.lock(); defer { lock.unlock() }
        stubs.append((match, Stub(statusCodes: statusCodes, body: Data(body.utf8))))
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        stubs = []
        matchCounts = [:]
        requests = []
        bodies = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            Self.bodies.append(data)
        } else if let body = request.httpBody {
            Self.bodies.append(body)
        }
        let match = Self.stubs.first { request.url?.absoluteString.contains($0.match) == true }
        var statusCode = 0
        if let match = match {
            let seen = Self.matchCounts[match.match, default: 0]
            Self.matchCounts[match.match] = seen + 1
            statusCode = match.stub.statusCodes[min(seen, match.stub.statusCodes.count - 1)]
        }
        Self.lock.unlock()

        guard let stub = match?.stub, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: statusCode,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
