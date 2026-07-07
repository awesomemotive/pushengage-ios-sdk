//
//  PESubscriberFieldsHandler.swift
//  PushEngage
//
//  Orchestrates `PushEngage.identify(...)` and `PushEngage.logout(...)`.
//
//  Mirrors the Android counterpart's per-call flow:
//    1. Synchronous validation via `PESubscriberFieldsValidator`. Failure →
//       callback(false, .custom(message)). No network.
//    2. Identify only: format payload (coerce numeric `profile_id` to String).
//    3. Cache short-circuit using `UserDefaultsType.subscriberFields`,
//       bounded by `cacheTTL` (default 24h):
//         - identify: every requested key already matches the cached value →
//           callback(true, nil) and skip the network.
//         - logout: none of the requested names exist in the cache →
//           callback(true, nil) and skip the network.
//       Once the cache's last-write timestamp is older than `cacheTTL`, the
//       check is treated as a miss so the next call forces a server round-trip
//       and refreshes the timestamp. This caps server-side divergence at 24h.
//    4. Otherwise dispatch via the network router. On 2xx: mutate the cache and
//       callback(true, nil). On error: callback(false, error).
//

import Foundation
import PushEngageExtension

internal final class PESubscriberFieldsHandler {

    static let defaultCacheTTL: TimeInterval = 24 * 60 * 60

    private let networkRouter: NetworkRouterType
    private var userDefaults: UserDefaultsType
    private let cacheTTL: TimeInterval
    private let now: () -> Date

    init(networkRouter: NetworkRouterType,
         userDefaults: UserDefaultsType,
         cacheTTL: TimeInterval = PESubscriberFieldsHandler.defaultCacheTTL,
         now: @escaping () -> Date = Date.init) {
        self.networkRouter = networkRouter
        self.userDefaults = userDefaults
        self.cacheTTL = cacheTTL
        self.now = now
    }

    // MARK: - identify

    func identify(fields: [String: Any]?,
                  completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?) {
        if let message = PESubscriberFieldsValidator.validateIdentifyPayload(fields) {
            completionHandler?(false, PEError.custom(message))
            return
        }
        // No subscriber yet → can't address `/subscriber/{hash}`. Reject locally
        // rather than emitting `subscriber//` and letting the server 4xx.
        if userDefaults.subscriberHash.isEmpty {
            completionHandler?(false, PEError.subscriberNotAvailable)
            return
        }
        // `validateIdentifyPayload` already guards against nil/empty.
        let formatted = PESubscriberFieldsValidator.formatSubscriberFields(fields!)
        let stringified = stringify(formatted)

        if isCacheFresh() && isIdentifyCacheInSync(requested: stringified) {
            completionHandler?(true, nil)
            return
        }

        networkRouter.request(.identifySubscriber((hash: userDefaults.subscriberHash,
                                                   fields: formatted))) { [weak self] result in
            switch result {
            case .success:
                self?.userDefaults.mergeSubscriberFields(stringified)
                completionHandler?(true, nil)
            case .failure(let error):
                completionHandler?(false, error)
            }
        }
    }

    // MARK: - logout

    func logout(fieldNames: [String]?,
                completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?) {
        let effective: [String] = {
            if let names = fieldNames, !names.isEmpty { return names }
            return PESubscriberFieldsValidator.defaultLogoutFields
        }()

        if let message = PESubscriberFieldsValidator.validateLogoutFieldNames(effective) {
            completionHandler?(false, PEError.custom(message))
            return
        }
        if userDefaults.subscriberHash.isEmpty {
            completionHandler?(false, PEError.subscriberNotAvailable)
            return
        }

        let cached = userDefaults.subscriberFields
        if isCacheFresh() && effective.allSatisfy({ cached[$0] == nil }) {
            completionHandler?(true, nil)
            return
        }

        networkRouter.request(.logoutSubscriberFields((hash: userDefaults.subscriberHash,
                                                      fieldNames: effective))) { [weak self] result in
            switch result {
            case .success:
                self?.userDefaults.removeSubscriberFields(effective)
                completionHandler?(true, nil)
            case .failure(let error):
                completionHandler?(false, error)
            }
        }
    }

    // MARK: - Cache helpers

    private func isCacheFresh() -> Bool {
        guard let ts = userDefaults.subscriberFieldsCacheTimestamp else { return false }
        return now().timeIntervalSince(ts) <= cacheTTL
    }

    private func isIdentifyCacheInSync(requested: [String: String]) -> Bool {
        let cached = userDefaults.subscriberFields
        if requested.isEmpty { return false }
        for (key, value) in requested {
            guard let cachedValue = cached[key], cachedValue == value else { return false }
        }
        return true
    }

    private func stringify(_ fields: [String: Any]) -> [String: String] {
        return PESubscriberFieldsStringify.stringifyDict(fields)
    }
}
