import XCTest
@testable import PushEngage

final class AnyCodableTests: XCTestCase {

    private func decode(_ json: String) throws -> AnyCodable {
        try JSONDecoder().decode(AnyCodable.self, from: Data(json.utf8))
    }

    private func encode(_ value: AnyCodable) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    func test_decode_intScalar() throws {
        let value = try decode("42")
        XCTAssertEqual(value.value as? Int, 42)
    }

    func test_decode_doubleScalar() throws {
        let value = try decode("3.14")
        XCTAssertEqual(value.value as? Double, 3.14)
    }

    func test_decode_boolScalar() throws {
        let value = try decode("true")
        XCTAssertEqual(value.value as? Bool, true)
    }

    func test_decode_stringScalar() throws {
        let value = try decode("\"hello\"")
        XCTAssertEqual(value.value as? String, "hello")
    }

    func test_decode_array_ofMixedTypes() throws {
        let value = try decode("[1, \"two\", true]")
        let array = value.value as? [Any]
        XCTAssertEqual(array?.count, 3)
        XCTAssertEqual(array?[0] as? Int, 1)
        XCTAssertEqual(array?[1] as? String, "two")
        XCTAssertEqual(array?[2] as? Bool, true)
    }

    func test_decode_nestedObject() throws {
        let value = try decode("""
        {"a": 1, "b": {"c": "deep"}, "d": [10, 20]}
        """)
        let dict = value.value as? [String: Any]
        XCTAssertEqual(dict?["a"] as? Int, 1)

        let inner = dict?["b"] as? [String: Any]
        XCTAssertEqual(inner?["c"] as? String, "deep")

        let arr = dict?["d"] as? [Any]
        XCTAssertEqual(arr?.count, 2)
        XCTAssertEqual(arr?[0] as? Int, 10)
        XCTAssertEqual(arr?[1] as? Int, 20)
    }

    func test_encode_intScalar() throws {
        let json = try encode(AnyCodable(value: 7))
        XCTAssertEqual(json, "7")
    }

    func test_encode_stringScalar() throws {
        let json = try encode(AnyCodable(value: "hi"))
        XCTAssertEqual(json, "\"hi\"")
    }

    func test_encode_array() throws {
        let json = try encode(AnyCodable(value: [1, "two", true] as [Any]))
        // Order is preserved for arrays
        XCTAssertEqual(json, "[1,\"two\",true]")
    }

    func test_encode_dictionary_roundtrip() throws {
        let original: [String: Any] = ["k": "v", "n": 5]
        let json = try encode(AnyCodable(value: original))
        let roundtripped = try decode(json).value as? [String: Any]
        XCTAssertEqual(roundtripped?["k"] as? String, "v")
        XCTAssertEqual(roundtripped?["n"] as? Int, 5)
    }
}
