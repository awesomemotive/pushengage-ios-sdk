import XCTest
@testable import PushEngage

/// Unit tests for the host-info helpers used in UA composition:
/// `Utility.getHardwareIdentifier` and `Utility.getAppShortVersion`.
final class UtilityHostInfoTests: XCTestCase {

    // MARK: - getHardwareIdentifier

    func test_getHardwareIdentifier_isNonEmpty() {
        let identifier = Utility.getHardwareIdentifier
        XCTAssertFalse(identifier.isEmpty, "Hardware identifier must never be empty — UA composition relies on it")
    }

    func test_getHardwareIdentifier_containsNoWhitespace() {
        let identifier = Utility.getHardwareIdentifier
        let whitespace = CharacterSet.whitespacesAndNewlines
        XCTAssertNil(identifier.rangeOfCharacter(from: whitespace),
                     "Hardware identifier must not contain whitespace (would break UA parsing)")
    }

    func test_getHardwareIdentifier_containsNoSlash() {
        let identifier = Utility.getHardwareIdentifier
        XCTAssertFalse(identifier.contains("/"), "Hardware identifier must not contain '/' (UA segment delimiter)")
    }

    func test_getHardwareIdentifier_isStable() {
        let first = Utility.getHardwareIdentifier
        let second = Utility.getHardwareIdentifier
        XCTAssertEqual(first, second, "Hardware identifier must be deterministic across calls")
    }

    func test_getHardwareIdentifier_onSimulator_matchesSimulatorEnvVar() {
        // On the simulator, SIMULATOR_MODEL_IDENTIFIER is set by Xcode to the
        // model being simulated (e.g. "iPhone16,1"). This test only asserts
        // equality when running under the simulator — skipped on device runs.
        guard let simulatedModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] else {
            return // running on device — nothing to assert beyond non-empty
        }
        XCTAssertEqual(Utility.getHardwareIdentifier, simulatedModel,
                       "On the simulator the helper must return the simulated model identifier, not the host arch")
    }

    // MARK: - getAppShortVersion

    func test_getAppShortVersion_returnsEmptyOrInfoPlistValue() {
        // Xctest bundles don't always have a CFBundleShortVersionString in their
        // own Info.plist. Either an empty string or a non-empty value is
        // acceptable; what matters is that the helper never crashes and never
        // returns a value containing the UA-unsafe characters slash/space/control.
        let appVer = Utility.getAppShortVersion
        let unsafe = CharacterSet(charactersIn: "/ \t\n\r").union(.controlCharacters)
        XCTAssertNil(appVer.unicodeScalars.first(where: { unsafe.contains($0) }),
                     "App short version must not contain UA-unsafe characters")
    }
}
