import XCTest
@testable import PushEngage
@testable import PushEngageExtension
final class PEErrorTests: XCTestCase {

    func test_localizedDescription_isNonEmpty_forEveryCase() {
        let cases: [PEError] = [
            .contentNotFound,
            .networkError,
            .downloadAttachmentfailed,
            .parametersNil,
            .encodingFailed,
            .missingURL,
            .invalidInput,
            .parsingError,
            .invalidStatusCode("oops", 500),
            .dataEncodeingFailed,
            .errorResponse("err"),
            .networkNotReachable,
            .cancelled,
            .missingInputURL,
            .missingRedirectURL,
            .underlying(error: NSError(domain: "T", code: 1)),
            .incorrectParameter,
            .tiggerfailure,
            .mediaLengthExceeded,
            .requestFailureException,
            .dataNotFound,
            .networkResponseFailure(404, "missing"),
            .dataTypeCastingError,
            .requestTimeout,
            .failedToLogError,
            .siteStatusNotActive,
            .subscriberNotAvailable,
            .profilealreadyExist,
            .siteKeyNotAvailable,
            .permissionNotDetermined,
            .permissionNotGranted,
            .notificationUserActionFailed("reason"),
            .custom("anything"),
        ]
        for error in cases {
            let description = error.errorDescription ?? ""
            XCTAssertFalse(description.isEmpty,
                           "PEError.\(error) returned empty errorDescription")
        }
    }

    func test_invalidStatusCode_includesMessageAndCode() {
        let error = PEError.invalidStatusCode("Bad Request", 400)
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("Bad Request"), "Description was: \(description)")
        XCTAssertTrue(description.contains("400"), "Description was: \(description)")
    }

    func test_errorResponse_passesMessageThrough() {
        let error = PEError.errorResponse("Verbatim error")
        XCTAssertEqual(error.errorDescription, "Verbatim error")
    }

    func test_custom_passesStringThrough() {
        let error = PEError.custom("My custom string")
        XCTAssertEqual(error.errorDescription, "My custom string")
    }

    func test_underlying_forwardsLocalizedDescription() {
        let underlying = NSError(domain: "TestDomain",
                                 code: 42,
                                 userInfo: [NSLocalizedDescriptionKey: "Inner failure"])
        let error = PEError.underlying(error: underlying)
        XCTAssertEqual(error.errorDescription, "Inner failure")
    }
}
