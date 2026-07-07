import XCTest
@testable import PushEngage
@testable import PushEngageExtension
/// Locks in the Android-parity public aliases on the `PushEngage` facade.
///
/// The pre-existing `add(attributes:completionHandler:)` and
/// `set(attributes:completionHandler:)` methods carry Swift-idiomatic argument
/// labels that don't map cleanly to the cross-platform `addSubscriberAttributes`
/// / `setSubscriberAttributes` names exposed by Android, React Native, and
/// Flutter. These tests pin the alias contract: methods exist on the facade
/// under the expected Swift signature AND under the expected Objective-C
/// selector (which is what the RN bridge and any Obj-C consumer dispatches on).
final class PushEngageAttributeAliasTests: XCTestCase {

    // MARK: - Swift signature (compile-time contract)
    //
    // If these methods are removed or renamed, the test target fails to compile.
    // The closures are never invoked — the singleton manager would attempt real
    // I/O — so we just confirm the call sites typecheck.

    func test_addSubscriberAttributes_swiftSignatureExists() {
        let _: (Parameters, ((Bool, Error?) -> Void)?) -> Void
            = PushEngage.addSubscriberAttributes(_:completionHandler:)
    }

    func test_setSubscriberAttributes_swiftSignatureExists() {
        let _: (Parameters, ((Bool, Error?) -> Void)?) -> Void
            = PushEngage.setSubscriberAttributes(_:completionHandler:)
    }

    // MARK: - Objective-C selector (runtime contract)
    //
    // The whole point of these aliases is cross-platform parity, which means
    // the Obj-C / RN bridge must see them under the canonical selector name.

    func test_addSubscriberAttributes_objcSelectorExists() {
        let sel = NSSelectorFromString("addSubscriberAttributes:completionHandler:")
        XCTAssertTrue(PushEngage.responds(to: sel),
                      "PushEngage must expose addSubscriberAttributes:completionHandler: " +
                      "to Obj-C for parity with Android / RN / Flutter SDKs")
    }

    func test_setSubscriberAttributes_objcSelectorExists() {
        let sel = NSSelectorFromString("setSubscriberAttributes:completionHandler:")
        XCTAssertTrue(PushEngage.responds(to: sel),
                      "PushEngage must expose setSubscriberAttributes:completionHandler: " +
                      "to Obj-C for parity with Android / RN / Flutter SDKs")
    }

    // MARK: - Back-compat — original add/set are deprecated but still present
    //
    // They must still compile so existing callers keep working (now with a
    // deprecation warning + fix-it to the SubscriberAttributes form). The test
    // methods are marked deprecated so exercising the deprecated API stays warning-free.

    @available(*, deprecated)
    func test_originalAdd_signatureStillExists() {
        let _: (Parameters, ((Bool, Error?) -> Void)?) -> Void
            = PushEngage.add(attributes:completionHandler:)
    }

    @available(*, deprecated)
    func test_originalSet_signatureStillExists() {
        let _: (Parameters, ((Bool, Error?) -> Void)?) -> Void
            = PushEngage.set(attributes:completionHandler:)
    }
}
