import XCTest
import CoreData
@testable import PushEngage

/// Outbound-URL rules for campaign content, matching Android's `IAMActionHandler.openUrl`
/// and `shouldOverrideUrlLoading`: http(s) only, a scheme-less string defaults to https,
/// everything else is refused.
///
/// Before this the SDK handed any parseable string to `UIApplication.shared.open` and had no
/// navigation policy on the message WebView at all — so `mailto:`/`javascript:`/`file:` were
/// passed through, and an `<a href>` tap navigated the message away in place. The message is
/// rendered without an address bar, which is what makes in-place navigation a phishing
/// surface rather than a cosmetic bug.
final class IAMOutboundURLTests: XCTestCase {

    func testHttpAndHttpsAreOpenable() {
        XCTAssertTrue(IAMViewController.isExternallyOpenableScheme("http"))
        XCTAssertTrue(IAMViewController.isExternallyOpenableScheme("https"))
    }

    /// A scheme is case-insensitive per RFC 3986, and campaign HTML is hand-authored.
    func testSchemeMatchingIsCaseInsensitive() {
        for scheme in ["HTTP", "Https", "hTTpS"] {
            XCTAssertTrue(IAMViewController.isExternallyOpenableScheme(scheme),
                          "\(scheme) must be accepted — schemes are case-insensitive")
        }
    }

    /// The exact set Android refuses. `javascript:` and `file:` are the ones with teeth:
    /// one executes in whatever context opens it, the other reaches the container.
    func testEverythingOtherThanHttpIsRefused() {
        for scheme in ["mailto", "javascript", "file", "tel", "intent", "data", "about", "ftp"] {
            XCTAssertFalse(IAMViewController.isExternallyOpenableScheme(scheme),
                           "\(scheme) must be refused")
        }
    }

    func testEmptyAndUnparseableAreRefusedWithoutOpening() {
        let controller = IAMViewController(message: unstoredMessage())
        XCTAssertFalse(controller.openExternally(nil))
        XCTAssertFalse(controller.openExternally(""))
    }

    /// Android logs `Invalid URL scheme: mailto` and returns false rather than handing the
    /// URL onward. The caller still dismisses the message, so a one-button campaign cannot
    /// be left stranded (Android finding 12).
    func testANonHttpActionURLIsRefused() {
        let controller = IAMViewController(message: unstoredMessage())
        XCTAssertFalse(controller.openExternally("mailto:someone@example.com"))
        XCTAssertFalse(controller.openExternally("javascript:alert(1)"))
        XCTAssertFalse(controller.openExternally("file:///etc/passwd"))
    }

    /// ACT-02: a scheme-less URL defaults to https instead of failing silently.
    func testASchemelessURLIsAcceptedByDefaultingToHttps() {
        let controller = IAMViewController(message: unstoredMessage())
        XCTAssertTrue(controller.openExternally("pushengage.com"),
                      "a scheme-less URL must be accepted by defaulting to https")
    }

    /// An in-memory message is enough here: these paths touch only the URL string, and
    /// constructing the controller must not require the shared on-disk store.
    private func unstoredMessage() -> IAMMessage {
        let model = IAMCoreDataManager.managedObjectModel!
        let container = NSPersistentContainer(name: "InAppMessaging", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in XCTAssertNil(error) }
        holdOpen.append(container)

        let message = IAMMessage(context: container.viewContext)
        message.id = "outbound-url-\(UUID().uuidString)"
        message.position = IAMPosition.center.rawValue
        message.htmlContent = "<html></html>"
        message.displayDuration = 0
        message.shouldDismissOnTap = false
        return message
    }

    /// The container must outlive the message, or the managed object is invalidated.
    private var holdOpen: [NSPersistentContainer] = []
}
