import XCTest
@testable import PushEngage
@testable import PushEngageExtension
/// Unit tests for `PESubscriberFieldsValidator`. Mirrors the Android counterpart
/// `PESubscriberFieldsValidatorTest` so cross-platform docs apply unchanged.
final class PESubscriberFieldsValidatorTests: XCTestCase {

    // MARK: - allowlist + default-PII constants

    func test_validSubscriberFields_isThe12KeyAllowlist() {
        XCTAssertEqual(PESubscriberFieldsValidator.validSubscriberFields, [
            "first_name", "last_name", "email", "phone", "gender", "dob",
            "language", "profile_id", "country", "city", "state", "zip"
        ])
    }

    func test_defaultLogoutFields_isTheSevenKeyPIISet() {
        XCTAssertEqual(PESubscriberFieldsValidator.defaultLogoutFields, [
            "first_name", "last_name", "email", "phone", "gender", "dob", "profile_id"
        ])
    }

    // MARK: - validateIdentifyPayload

    func test_validateIdentifyPayload_nil_returnsRequiredMessage() {
        let error = PESubscriberFieldsValidator.validateIdentifyPayload(nil)
        XCTAssertNotNil(error)
        XCTAssertTrue(error?.contains("Payload is required") == true,
                      "nil → error mentioning 'Payload is required'; got \(error ?? "nil")")
    }

    func test_validateIdentifyPayload_empty_returnsAtLeastOneKeyMessage() {
        let error = PESubscriberFieldsValidator.validateIdentifyPayload([:])
        XCTAssertNotNil(error)
        XCTAssertTrue(error?.contains("at least one key") == true,
                      "empty → 'at least one key' message; got \(error ?? "nil")")
    }

    func test_validateIdentifyPayload_invalidKey_returnsKeyNotValidMessage() {
        let error = PESubscriberFieldsValidator.validateIdentifyPayload(["favorite_color": "blue"])
        XCTAssertNotNil(error)
        XCTAssertTrue(error?.contains("favorite_color") == true && error?.contains("is not valid") == true,
                      "got \(error ?? "nil")")
    }

    func test_validateIdentifyPayload_invalidValueType_array_returnsTypeMessage() {
        let error = PESubscriberFieldsValidator.validateIdentifyPayload(["first_name": ["Alice"]])
        XCTAssertNotNil(error)
        XCTAssertTrue(error?.contains("Value must be a string, number, or boolean") == true,
                      "got \(error ?? "nil")")
    }

    func test_validateIdentifyPayload_invalidValueType_dict_returnsTypeMessage() {
        let error = PESubscriberFieldsValidator.validateIdentifyPayload(["first_name": ["nested": 1]])
        XCTAssertNotNil(error)
        XCTAssertTrue(error?.contains("Value must be a string, number, or boolean") == true,
                      "got \(error ?? "nil")")
    }

    func test_validateIdentifyPayload_invalidValueType_date_returnsTypeMessage() {
        let error = PESubscriberFieldsValidator.validateIdentifyPayload(["dob": Date()])
        XCTAssertNotNil(error)
        XCTAssertTrue(error?.contains("Value must be a string, number, or boolean") == true,
                      "got \(error ?? "nil")")
    }

    func test_validateIdentifyPayload_allValidKeysAndTypes_returnsNil() {
        let fields: Parameters = [
            "first_name": "Alice", "last_name": "Smith",
            "email": "a@b.com", "phone": "+1234567890",
            "gender": "F", "dob": "1990-01-01",
            "language": "en", "profile_id": "user-42",
            "country": "US", "city": "SF", "state": "CA", "zip": "94101"
        ]
        XCTAssertNil(PESubscriberFieldsValidator.validateIdentifyPayload(fields))
    }

    func test_validateIdentifyPayload_boolValue_accepted() {
        XCTAssertNil(PESubscriberFieldsValidator.validateIdentifyPayload(["first_name": true]))
    }

    func test_validateIdentifyPayload_numberValue_accepted() {
        XCTAssertNil(PESubscriberFieldsValidator.validateIdentifyPayload(["profile_id": 12345]))
    }

    // MARK: - validateLogoutFieldNames

    func test_validateLogoutFieldNames_emptyList_returnsNil() {
        // Handler normalizes null/empty to default set before calling this — so
        // empty list is by construction valid here.
        XCTAssertNil(PESubscriberFieldsValidator.validateLogoutFieldNames([]))
    }

    func test_validateLogoutFieldNames_validNames_returnsNil() {
        XCTAssertNil(PESubscriberFieldsValidator.validateLogoutFieldNames(["email", "profile_id"]))
    }

    func test_validateLogoutFieldNames_invalidName_returnsNotValidMessage() {
        let error = PESubscriberFieldsValidator.validateLogoutFieldNames(["ssn"])
        XCTAssertNotNil(error)
        XCTAssertTrue(error?.contains("ssn") == true && error?.contains("is not valid") == true,
                      "got \(error ?? "nil")")
    }

    // MARK: - formatSubscriberFields (numeric profile_id coercion)

    func test_formatSubscriberFields_numericProfileId_coercedToString() {
        let formatted = PESubscriberFieldsValidator.formatSubscriberFields(["profile_id": 12345])
        XCTAssertEqual(formatted["profile_id"] as? String, "12345")
    }

    func test_formatSubscriberFields_stringProfileId_leftUnchanged() {
        let formatted = PESubscriberFieldsValidator.formatSubscriberFields(["profile_id": "user-42"])
        XCTAssertEqual(formatted["profile_id"] as? String, "user-42")
    }

    func test_formatSubscriberFields_absentProfileId_leftUnchanged() {
        let formatted = PESubscriberFieldsValidator.formatSubscriberFields(["first_name": "Alice"])
        XCTAssertEqual(formatted["first_name"] as? String, "Alice")
        XCTAssertNil(formatted["profile_id"])
    }

    func test_formatSubscriberFields_doubleProfileId_coercedToString() {
        let formatted = PESubscriberFieldsValidator.formatSubscriberFields(["profile_id": 42.0])
        XCTAssertEqual(formatted["profile_id"] as? String, "42.0")
    }
}
