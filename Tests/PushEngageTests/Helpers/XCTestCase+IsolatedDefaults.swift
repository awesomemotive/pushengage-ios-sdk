import XCTest

extension XCTestCase {

    /// Returns a UserDefaults suite that starts empty and is wiped again on teardown.
    func makeSuite(_ name: String) -> UserDefaults {
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        addTeardownBlock { suite.removePersistentDomain(forName: name) }
        return suite
    }
}
