import XCTest
@testable import PushEngage

/// Unit tests for `PESubscriberFieldsHandler`. Mirrors the Android counterpart's
/// validate-→ short-circuit → network → cache-mutate flow for both identify and
/// logout. All network IO is stubbed via `MockNetworkRouter`; cache state lives
/// in `MockUserDefaultsService`.
final class PESubscriberFieldsHandlerTests: XCTestCase {

    private var networkRouter: MockNetworkRouter!
    private var userDefaults: MockUserDefaultsService!
    private var fixedNow: Date!
    private var sut: PESubscriberFieldsHandler!

    override func setUp() {
        super.setUp()
        networkRouter = MockNetworkRouter()
        userDefaults = MockUserDefaultsService()
        userDefaults.subscriberHash = "HASH"
        fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        userDefaults.nowProvider = { [weak self] in self?.fixedNow ?? Date() }
        sut = PESubscriberFieldsHandler(networkRouter: networkRouter,
                                        userDefaults: userDefaults,
                                        now: { [weak self] in self?.fixedNow ?? Date() })
    }

    override func tearDown() {
        sut = nil
        userDefaults = nil
        networkRouter = nil
        super.tearDown()
    }

    // MARK: - identify validation

    func test_identify_nilFields_fails_noNetwork() {
        var response: Bool? = nil
        sut.identify(fields: nil) { ok, _ in response = ok }
        XCTAssertEqual(response, false)
        XCTAssertEqual(networkRouter.requestCallCount, 0)
    }

    func test_identify_emptyFields_fails_noNetwork() {
        var response: Bool? = nil
        sut.identify(fields: [:]) { ok, _ in response = ok }
        XCTAssertEqual(response, false)
        XCTAssertEqual(networkRouter.requestCallCount, 0)
    }

    func test_identify_invalidKey_fails_noNetwork() {
        var response: Bool? = nil
        sut.identify(fields: ["favorite_color": "blue"]) { ok, _ in response = ok }
        XCTAssertEqual(response, false)
        XCTAssertEqual(networkRouter.requestCallCount, 0)
    }

    func test_identify_invalidValueType_fails_noNetwork() {
        var response: Bool? = nil
        sut.identify(fields: ["first_name": [String]()]) { ok, _ in response = ok }
        XCTAssertEqual(response, false)
        XCTAssertEqual(networkRouter.requestCallCount, 0)
    }

    // MARK: - identify cache short-circuit

    func test_identify_cacheHit_skipsNetwork_callsBackSuccess() {
        userDefaults.mergeSubscriberFields(["email": "a@b.com", "first_name": "Alice"])
        var response: Bool? = nil
        sut.identify(fields: ["email": "a@b.com"]) { ok, _ in response = ok }
        XCTAssertEqual(response, true)
        XCTAssertEqual(networkRouter.requestCallCount, 0,
                       "identify with all keys matching cache must skip the network")
    }

    func test_identify_cacheStale_dispatchesNetwork() {
        // Pre-fill cache then advance "now" past the 24h TTL.
        userDefaults.mergeSubscriberFields(["email": "a@b.com"])
        fixedNow = fixedNow.addingTimeInterval(25 * 60 * 60)
        networkRouter.enqueueSuccess(#"{"error_code":0}"#)

        sut.identify(fields: ["email": "a@b.com"], completionHandler: nil)

        XCTAssertEqual(networkRouter.requestCallCount, 1,
                       "Cache older than 24h must force a network round-trip")
    }

    func test_identify_cacheMiss_dispatchesNetwork() {
        userDefaults.mergeSubscriberFields(["email": "a@b.com"])
        networkRouter.enqueueSuccess(#"{"error_code":0}"#)

        sut.identify(fields: ["email": "a@b.com", "phone": "1234"], completionHandler: nil)

        XCTAssertEqual(networkRouter.requestCallCount, 1)
    }

    func test_identify_networkSuccess_mergesCache() {
        networkRouter.enqueueSuccess(#"{"error_code":0}"#)
        sut.identify(fields: ["email": "a@b.com", "first_name": "Alice"], completionHandler: nil)

        XCTAssertEqual(userDefaults.subscriberFields, ["email": "a@b.com", "first_name": "Alice"])
    }

    func test_identify_networkFailure_doesNotMutateCache() {
        networkRouter.enqueueFailure(.networkNotReachable)
        sut.identify(fields: ["email": "a@b.com"], completionHandler: nil)

        XCTAssertEqual(userDefaults.subscriberFields, [:])
    }

    func test_identify_numericProfileId_coercedToString_inDispatchedRoute() {
        networkRouter.enqueueSuccess(#"{"error_code":0}"#)
        sut.identify(fields: ["profile_id": 12345], completionHandler: nil)

        guard case let .identifySubscriber(info) = networkRouter.requestedRoutes.first else {
            XCTFail("Expected .identifySubscriber route"); return
        }
        XCTAssertEqual(info.fields["profile_id"] as? String, "12345",
                       "Numeric profile_id must be stringified before dispatch (web SDK parity)")
    }

    // MARK: - logout default-PII normalization

    func test_logout_nilList_defaultsToPII() {
        networkRouter.enqueueSuccess(#"{"error_code":0}"#)
        // Pre-populate so the cache short-circuit doesn't kick in.
        userDefaults.mergeSubscriberFields(["email": "a@b.com"])
        sut.logout(fieldNames: nil, completionHandler: nil)

        guard case let .logoutSubscriberFields(info) = networkRouter.requestedRoutes.first else {
            XCTFail("Expected .logoutSubscriberFields route"); return
        }
        XCTAssertEqual(Set(info.fieldNames), Set(PESubscriberFieldsValidator.defaultLogoutFields))
    }

    func test_logout_emptyList_defaultsToPII() {
        networkRouter.enqueueSuccess(#"{"error_code":0}"#)
        userDefaults.mergeSubscriberFields(["email": "a@b.com"])
        sut.logout(fieldNames: [], completionHandler: nil)

        guard case let .logoutSubscriberFields(info) = networkRouter.requestedRoutes.first else {
            XCTFail("Expected .logoutSubscriberFields route"); return
        }
        XCTAssertEqual(Set(info.fieldNames), Set(PESubscriberFieldsValidator.defaultLogoutFields))
    }

    // MARK: - logout validation

    func test_logout_invalidName_fails_noNetwork() {
        var response: Bool? = nil
        sut.logout(fieldNames: ["ssn"]) { ok, _ in response = ok }
        XCTAssertEqual(response, false)
        XCTAssertEqual(networkRouter.requestCallCount, 0)
    }

    // MARK: - logout cache short-circuit

    func test_logout_noneOfNamesInCache_skipsNetwork_callsBackSuccess() {
        userDefaults.mergeSubscriberFields(["first_name": "Alice"])
        var response: Bool? = nil
        sut.logout(fieldNames: ["email", "phone"]) { ok, _ in response = ok }

        XCTAssertEqual(response, true)
        XCTAssertEqual(networkRouter.requestCallCount, 0,
                       "logout with no requested key present in cache must skip the network")
    }

    func test_logout_someNamesInCache_dispatchesNetwork() {
        userDefaults.mergeSubscriberFields(["email": "a@b.com"])
        networkRouter.enqueueSuccess(#"{"error_code":0}"#)
        sut.logout(fieldNames: ["email", "phone"], completionHandler: nil)
        XCTAssertEqual(networkRouter.requestCallCount, 1)
    }

    func test_logout_cacheStale_dispatchesNetwork() {
        userDefaults.mergeSubscriberFields(["first_name": "Alice"])
        fixedNow = fixedNow.addingTimeInterval(25 * 60 * 60)
        networkRouter.enqueueSuccess(#"{"error_code":0}"#)

        sut.logout(fieldNames: ["email"], completionHandler: nil)
        XCTAssertEqual(networkRouter.requestCallCount, 1,
                       "Stale cache must not short-circuit logout")
    }

    func test_logout_networkSuccess_removesCacheKeys() {
        userDefaults.mergeSubscriberFields(["email": "a@b.com", "first_name": "Alice"])
        networkRouter.enqueueSuccess(#"{"error_code":0}"#)

        sut.logout(fieldNames: ["email"], completionHandler: nil)

        XCTAssertEqual(userDefaults.subscriberFields, ["first_name": "Alice"])
    }

    func test_logout_networkFailure_doesNotMutateCache() {
        userDefaults.mergeSubscriberFields(["email": "a@b.com"])
        networkRouter.enqueueFailure(.networkNotReachable)

        sut.logout(fieldNames: ["email"], completionHandler: nil)

        XCTAssertEqual(userDefaults.subscriberFields, ["email": "a@b.com"])
    }

    // MARK: - Empty subscriberHash guard
    //
    // No subscriber yet → URL becomes `subscriber//fields`. Reject locally
    // with .subscriberNotAvailable rather than emitting a malformed request.

    func test_identify_emptySubscriberHash_failsLocally_noNetwork() {
        userDefaults.subscriberHash = ""
        var response: Bool? = nil
        var error: PEError? = nil
        sut.identify(fields: ["email": "a@b.com"]) { ok, err in
            response = ok
            error = err
        }
        XCTAssertEqual(response, false)
        XCTAssertEqual(networkRouter.requestCallCount, 0)
        if case .subscriberNotAvailable = error {} else {
            XCTFail("Expected .subscriberNotAvailable, got \(String(describing: error))")
        }
    }

    func test_logout_emptySubscriberHash_failsLocally_noNetwork() {
        userDefaults.subscriberHash = ""
        var response: Bool? = nil
        var error: PEError? = nil
        sut.logout(fieldNames: ["email"]) { ok, err in
            response = ok
            error = err
        }
        XCTAssertEqual(response, false)
        XCTAssertEqual(networkRouter.requestCallCount, 0)
        if case .subscriberNotAvailable = error {} else {
            XCTFail("Expected .subscriberNotAvailable, got \(String(describing: error))")
        }
    }

    // MARK: - Cache key semantics: 42 vs 42.0 (different keys by design)
    //
    // identify({profile_id: 42}) and identify({profile_id: 42.0}) stringify to
    // "42" and "42.0" respectively — different cache keys. Two consecutive calls
    // both hit the network. This is wasted RTT, but not a correctness bug.
    // Pinning the behavior so a future "normalize numeric whole-doubles" change
    // is intentional.

    func test_identify_intVsDoubleProfileId_doNotCacheCollide() {
        networkRouter.enqueueSuccess(#"{"error_code":0}"#)
        sut.identify(fields: ["profile_id": 42], completionHandler: nil)
        XCTAssertEqual(userDefaults.subscriberFields["profile_id"], "42")

        // Cache now holds "42". Second call with 42.0 stringifies to "42.0" —
        // different key — must hit the network again.
        networkRouter.enqueueSuccess(#"{"error_code":0}"#)
        sut.identify(fields: ["profile_id": 42.0], completionHandler: nil)
        XCTAssertEqual(networkRouter.requestCallCount, 2,
                       "Int 42 and Double 42.0 must be treated as distinct cache keys")
        XCTAssertEqual(userDefaults.subscriberFields["profile_id"], "42.0")
    }
}
