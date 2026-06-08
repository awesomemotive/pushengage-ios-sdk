import XCTest
@testable import PushEngage

/// Pins the rename of the public `PEnotificationAction` type to the
/// PE-prefix-convention-correct `PENotificationAction`. The Objective-C
/// runtime name is intentionally preserved as `PEnotificationAction` via
/// `@objc(PEnotificationAction)` so any existing Obj-C consumer keeps
/// resolving the bridged class.
final class PENotificationActionRenameTests: XCTestCase {

    // MARK: - Swift canonical name

    func test_swift_canonicalTypeName_isPENotificationAction() {
        let action = PENotificationAction(actionID: "btn-1", actionType: .taken)
        XCTAssertEqual(action.actionID, "btn-1")
        XCTAssertEqual(action.actionType, .taken)
    }

    // MARK: - Objective-C bridge preserves the historical class name
    //
    // External Obj-C consumers that wrote `PEnotificationAction *` against the
    // 0.0.x SDK must keep working after the rename. The `@objc(PEnotificationAction)`
    // attribute keeps the Obj-C runtime name fixed.

    func test_objc_runtimeName_isPreservedAsPEnotificationAction() {
        let runtimeName = NSStringFromClass(PENotificationAction.self)
        XCTAssertTrue(runtimeName.hasSuffix(".PEnotificationAction") || runtimeName == "PEnotificationAction",
                      "ObjC runtime name must remain 'PEnotificationAction' for back-compat — got '\(runtimeName)'")
    }

    // MARK: - PENotificationOpenResult exposes the renamed type
    //
    // PENotificationOpenResult.notificationAction is the public touchpoint
    // most consumers actually see. It must now type as PENotificationAction.

    func test_openResult_actionType_isPENotificationAction() {
        let action = PENotificationAction(actionID: "a", actionType: .opened)
        let notification = PENotification(userInfo: [:])
        let result = PENotificationOpenResult(notification: notification, notficationAction: action)
        XCTAssertTrue(type(of: result.notificationAction) == PENotificationAction.self)
    }
}
