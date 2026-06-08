import XCTest
@testable import PushEngage

final class SmokeTests: XCTestCase {

    func test_publicEntryPoint_exists() {
        XCTAssertNotNil(PushEngage.self)
    }

    func test_permissionStatus_rawValues() {
        XCTAssertEqual(PermissionStatus.granted.rawValue, "granted")
        XCTAssertEqual(PermissionStatus.denied.rawValue, "denied")
        XCTAssertEqual(PermissionStatus.notYetRequested.rawValue, "notYetRequested")
    }
}
