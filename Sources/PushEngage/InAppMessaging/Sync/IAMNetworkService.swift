import Foundation

/// Network surface for the IAM backend (contract §2).
protocol IAMNetworkServiceType {
    /// Metadata-gated campaign sync (§2.1/§2.2): applies the 1h metadata
    /// cache, the iam_status gate and the version gate, then fetches the full
    /// campaign set from the metadata-advertised host when the version moved.
    func syncCampaigns(siteKey: String,
                       storedVersion: String?,
                       completion: @escaping (Result<IAMCampaignSyncResult, Error>) -> Void)

    /// Posts analytics events (§2.3) — one POST per payload, no batching in v1.
    /// `.failure` means nothing was attempted; an attempted batch reports per-payload
    /// accounting so the caller clears only what the backend accounted for.
    func reportAnalytics(payloads: [IAMAnalyticsPayload],
                         completion: @escaping (Result<IAMReportOutcome, Error>) -> Void)
}

enum IAMNetworkError: Error, LocalizedError {
    case httpError(Int, endpoint: String)
    case emptyResponse(endpoint: String)
    case missingVersion
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let endpoint):
            return "\(endpoint) failed: HTTP \(code)"
        case .emptyResponse(let endpoint):
            return "\(endpoint) returned no data"
        case .missingVersion:
            return "Metadata missing version"
        case .invalidURL(let url):
            return "Invalid IAM URL: \(url)"
        }
    }
}

/// Real IAM backend implementation (contract §2), mirroring Android's
/// IAMNetworkServiceImpl.
///
/// Host discovery: metadata is fetched from the environment's IAM base host,
/// and its response advertises the campaigns (`backend_cdn`) and analytics
/// (`iam_analytics`) hosts; the analytics host is persisted for later posts.
final class IAMNetworkServiceImpl: IAMNetworkServiceType {

    private let session: URLSession
    private let prefs: IAMPrefs
    private let configuration: IAMConfiguration
    private let now: () -> Date

    init(session: URLSession = .shared,
         prefs: IAMPrefs = .shared,
         configuration: IAMConfiguration = .shared,
         now: @escaping () -> Date = Date.init) {
        self.session = session
        self.prefs = prefs
        self.configuration = configuration
        self.now = now
    }

    // MARK: - Campaign sync

    func syncCampaigns(siteKey: String,
                       storedVersion: String?,
                       completion: @escaping (Result<IAMCampaignSyncResult, Error>) -> Void) {
        // Always fetch metadata — it's the cheap discovery document that carries
        // the version, and the version is only observable by fetching it. The
        // version gate below still prevents a redundant campaigns (CDN) fetch when
        // nothing changed, so a dashboard edit is picked up on the next sync
        // instead of being hidden behind a client-side freshness cache.
        let base = metadataBaseUrl()
        get(host: base, path: IAMNetworkConstants.metadataPath,
            query: [URLQueryItem(name: "site_key", value: siteKey)],
            as: IAMEnvelope<IAMMetadataResponse>.self) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                completion(.failure(error))

            case .success(let envelope):
                guard let metadata = envelope.data else {
                    completion(.failure(IAMNetworkError.emptyResponse(endpoint: "metadata")))
                    return
                }

                // Gate on status.
                guard IAMNetworkConstants.activeStatus.caseInsensitiveCompare(metadata.iamStatus ?? "") == .orderedSame else {
                    PELogger.debug(
                        className: String(describing: IAMNetworkServiceImpl.self),
                        message: "IAM status is '\(metadata.iamStatus ?? "nil")' — not active, purging campaigns"
                    )
                    completion(.success(.inactive()))
                    return
                }

                // Gate on version — nothing changed since the last sync.
                guard let version = metadata.version, !version.isEmpty else {
                    completion(.failure(IAMNetworkError.missingVersion))
                    return
                }
                if version == storedVersion {
                    PELogger.debug(
                        className: String(describing: IAMNetworkServiceImpl.self),
                        message: "IAM version unchanged (\(version)) — no campaign fetch needed"
                    )
                    completion(.success(.unchanged()))
                    return
                }

                // Follow the metadata api block for host discovery, falling back
                // to the IAM base host when a field is missing/empty.
                let campaignsHost = metadata.api?.backendCdn.flatMap { $0.isEmpty ? nil : $0 } ?? base
                let analyticsHost = metadata.api?.iamAnalytics.flatMap { $0.isEmpty ? nil : $0 } ?? base

                self.get(host: campaignsHost, path: IAMNetworkConstants.campaignsPath,
                         query: [URLQueryItem(name: "version", value: version),
                                 URLQueryItem(name: "site_key", value: siteKey)],
                         as: IAMEnvelope<[IAMMessageResponse]>.self) { campaignsResult in
                    switch campaignsResult {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let campaignsEnvelope):
                        let campaigns = campaignsEnvelope.data ?? []
                        PELogger.debug(
                            className: String(describing: IAMNetworkServiceImpl.self),
                            message: "Fetched \(campaigns.count) campaigns for version \(version) from \(campaignsHost)"
                        )
                        completion(.success(IAMCampaignSyncResult(
                            status: .active,
                            version: version,
                            campaigns: campaigns,
                            campaignsHost: campaignsHost,
                            analyticsHost: analyticsHost
                        )))
                    }
                }
            }
        }
    }

    // MARK: - Analytics

    func reportAnalytics(payloads: [IAMAnalyticsPayload],
                         completion: @escaping (Result<IAMReportOutcome, Error>) -> Void) {
        guard let siteKey = configuration.siteKey, !siteKey.isEmpty else {
            completion(.failure(IAMNetworkError.emptyResponse(endpoint: "site_key not available yet")))
            return
        }
        // Prefer the metadata-advertised analytics host; fall back to the base.
        let host = prefs.iamAnalyticsUrl.isEmpty ? metadataBaseUrl() : prefs.iamAnalyticsUrl

        // One POST per event (no batching in v1); stop at the first retryable failure
        // so the events behind it stay queued for the next flush.
        postNext(payloads: payloads, index: 0, synced: [],
                 host: host, siteKey: siteKey, completion: completion)
    }

    /// Status codes that will never accept the payload, so retrying it only blocks
    /// every event queued behind it. 408/429 and the auth codes are excluded: those
    /// clear on their own or on a config fix.
    private static let permanentRejectionCodes: Set<Int> = [400, 409, 413, 422]

    private func postNext(payloads: [IAMAnalyticsPayload],
                          index: Int,
                          synced: [Int],
                          host: String,
                          siteKey: String,
                          completion: @escaping (Result<IAMReportOutcome, Error>) -> Void) {
        guard index < payloads.count else {
            completion(.success(IAMReportOutcome(syncedIndices: synced, allSynced: true)))
            return
        }
        post(host: host, path: IAMNetworkConstants.analyticsPath,
             query: [URLQueryItem(name: "site_key", value: siteKey)],
             body: payloads[index]) { [weak self] result in
            guard let self = self else {
                completion(.success(IAMReportOutcome(syncedIndices: synced, allSynced: false)))
                return
            }
            switch result {
            case .failure(let error):
                if case IAMNetworkError.httpError(let code, _) = error,
                   Self.permanentRejectionCodes.contains(code) {
                    PELogger.error(
                        className: String(describing: IAMNetworkServiceImpl.self),
                        message: "Analytics payload \(index) of \(payloads.count) rejected with "
                            + "HTTP \(code); dropping it rather than blocking the queue"
                    )
                    self.postNext(payloads: payloads, index: index + 1, synced: synced + [index],
                                  host: host, siteKey: siteKey, completion: completion)
                    return
                }
                completion(.success(IAMReportOutcome(syncedIndices: synced,
                                                     allSynced: false,
                                                     failure: error)))
            case .success:
                self.postNext(payloads: payloads, index: index + 1, synced: synced + [index],
                              host: host, siteKey: siteKey, completion: completion)
            }
        }
    }

    // MARK: - Base host

    /// IAM base host: the persisted override if present, else the dedicated
    /// per-environment IAM constant. IAM has its own host (not the
    /// notification CDN).
    func metadataBaseUrl() -> String {
        if !prefs.iamBaseUrl.isEmpty {
            return prefs.iamBaseUrl
        }
        switch configuration.environment {
        case .production:
            return IAMNetworkConstants.productionIAMBaseURL
        case .staging:
            return IAMNetworkConstants.stagingIAMBaseURL
        }
    }

    // MARK: - HTTP plumbing

    private func buildURL(host: String, path: String, query: [URLQueryItem]) -> URL? {
        guard var components = URLComponents(string: host + path) else { return nil }
        components.queryItems = query
        return components.url
    }

    private func get<T: Decodable>(host: String,
                                   path: String,
                                   query: [URLQueryItem],
                                   as type: T.Type,
                                   completion: @escaping (Result<T, Error>) -> Void) {
        guard let url = buildURL(host: host, path: path, query: query) else {
            completion(.failure(IAMNetworkError.invalidURL(host + path)))
            return
        }
        let task = session.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode) else {
                completion(.failure(IAMNetworkError.httpError(statusCode, endpoint: path)))
                return
            }
            guard let data = data else {
                completion(.failure(IAMNetworkError.emptyResponse(endpoint: path)))
                return
            }
            do {
                completion(.success(try IAMWireCodec.decoder.decode(T.self, from: data)))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    private func post<Body: Encodable>(host: String,
                                       path: String,
                                       query: [URLQueryItem],
                                       body: Body,
                                       completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = buildURL(host: host, path: path, query: query) else {
            completion(.failure(IAMNetworkError.invalidURL(host + path)))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try IAMWireCodec.encoder.encode(body)
        } catch {
            completion(.failure(error))
            return
        }
        let task = session.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode) else {
                completion(.failure(IAMNetworkError.httpError(statusCode, endpoint: path)))
                return
            }
            completion(.success(()))
        }
        task.resume()
    }
}

/// Offline mock: serves the bundled reference campaigns (§Appendix A) with a
/// fixed version, never touching the network. Not used in production — inject
/// it into IAMSyncManager when you want deterministic, offline content for
/// QA/tests. Mirrors Android's IAMNetworkServiceMock.
final class IAMNetworkServiceMock: IAMNetworkServiceType {

    func syncCampaigns(siteKey: String,
                       storedVersion: String?,
                       completion: @escaping (Result<IAMCampaignSyncResult, Error>) -> Void) {
        // Simulate network delay like the previous inline mock.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            completion(.success(IAMCampaignSyncResult(
                status: .active,
                version: "mock",
                campaigns: IAMController.mockMessages(),
                campaignsHost: nil,
                analyticsHost: nil
            )))
        }
    }

    func reportAnalytics(payloads: [IAMAnalyticsPayload],
                         completion: @escaping (Result<IAMReportOutcome, Error>) -> Void) {
        completion(.success(IAMReportOutcome(syncedIndices: Array(payloads.indices),
                                             allSynced: true)))
    }
}
