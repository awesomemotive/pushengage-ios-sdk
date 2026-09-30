import XCTest
#if canImport(UIKit)
import UIKit
#endif
@testable import PushEngage

/// `top`/`bottom` banner width: the safe area less a 16 pt margin a side, capped at
/// `bannerMaxWidth` so a banner does not stretch edge to edge on a tablet. Matches
/// Android's `IAMWebViewContainer.bannerWidthPx`:
/// `min(screenWidth - 2 * margin, dpToPx(560))`, centred horizontally.
///
/// Resolves real Auto Layout rather than duplicating the arithmetic, so a constraint
/// that reads an unresolved value fails here too.
final class IAMBannerWidthTests: XCTestCase {

    private let margin: CGFloat = 16

    private func layout(size: CGSize,
                        sideInset: CGFloat = 0,
                        pinnedToTop: Bool = true) -> CGRect {
        let host = UIView(frame: CGRect(origin: .zero, size: size))

        let safeArea = UILayoutGuide()
        host.addLayoutGuide(safeArea)
        NSLayoutConstraint.activate([
            safeArea.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: sideInset),
            safeArea.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -sideInset),
            safeArea.topAnchor.constraint(equalTo: host.topAnchor),
            safeArea.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(container)
        NSLayoutConstraint.activate([container.heightAnchor.constraint(equalToConstant: 70)])
        NSLayoutConstraint.activate(IAMViewController.bannerConstraints(container: container,
                                                                        host: host,
                                                                        safeArea: safeArea,
                                                                        pinnedToTop: pinnedToTop,
                                                                        standardMargin: margin))
        host.setNeedsLayout()
        host.layoutIfNeeded()
        return container.frame
    }

    // MARK: - Phones are unaffected

    /// iPhone 16 portrait: 361 pt is under the cap, so nothing changes.
    func testIPhonePortraitBannerFillsTheSafeAreaMinusMargins() {
        let frame = layout(size: CGSize(width: 393, height: 852))
        XCTAssertEqual(frame.width, 393 - 2 * margin, accuracy: 0.5)
        XCTAssertEqual(frame.minX, margin, accuracy: 0.5)
    }

    /// iPhone 16 landscape: 734 − 32 = 702 would exceed the cap, so it clamps.
    func testIPhoneLandscapeBannerIsCappedAndCentred() {
        let frame = layout(size: CGSize(width: 852, height: 393), sideInset: 59)
        XCTAssertEqual(frame.width, IAMViewController.bannerMaxWidth, accuracy: 0.5)
        XCTAssertEqual(frame.midX, 426, accuracy: 0.5)
    }

    // MARK: - Tablets: the cap is the point

    /// iPad portrait measured 802 pt before the cap.
    func testIPadPortraitBannerIsCapped() {
        let frame = layout(size: CGSize(width: 834, height: 1210))
        XCTAssertEqual(frame.width, IAMViewController.bannerMaxWidth, accuracy: 0.5)
        XCTAssertEqual(frame.midX, 417, accuracy: 0.5)
    }

    /// iPad landscape measured 1178 pt before the cap — the worst case.
    func testIPadLandscapeBannerIsCapped() {
        let frame = layout(size: CGSize(width: 1210, height: 834))
        XCTAssertEqual(frame.width, IAMViewController.bannerMaxWidth, accuracy: 0.5)
        XCTAssertEqual(frame.midX, 605, accuracy: 0.5)
    }

    /// The two values this replaces must not come back.
    func testIPadBannerIsNotFullWidthAnyMore() {
        XCTAssertNotEqual(layout(size: CGSize(width: 834, height: 1210)).width, 802, accuracy: 1)
        XCTAssertNotEqual(layout(size: CGSize(width: 1210, height: 834)).width, 1178, accuracy: 1)
    }

    /// A banner never exceeds the cap at any width, and never overhangs the safe area.
    func testBannerNeverExceedsTheCapOrTheSafeArea() {
        for width in stride(from: CGFloat(320), through: 1400, by: 40) {
            for inset in [CGFloat(0), 24, 59] {
                let frame = layout(size: CGSize(width: width, height: 900), sideInset: inset)
                XCTAssertLessThanOrEqual(frame.width, IAMViewController.bannerMaxWidth + 0.5,
                                         "exceeded cap at width \(width) inset \(inset)")
                XCTAssertLessThanOrEqual(frame.width, width - 2 * inset - 2 * margin + 0.5,
                                         "overhang at width \(width) inset \(inset)")
            }
        }
    }

    // MARK: - Edge pinning survives the change

    func testTopBannerPinsToTheTopSafeEdge() {
        let frame = layout(size: CGSize(width: 393, height: 852), pinnedToTop: true)
        XCTAssertEqual(frame.minY, margin, accuracy: 0.5)
    }

    func testBottomBannerPinsToTheBottomSafeEdge() {
        let frame = layout(size: CGSize(width: 393, height: 852), pinnedToTop: false)
        XCTAssertEqual(frame.maxY, 852 - margin, accuracy: 0.5)
    }

    // MARK: - The constant

    /// 560 is Android's `dpToPx(560)`; pt and dp are treated as equivalent here.
    func testBannerMaxWidthMatchesAndroid() {
        XCTAssertEqual(IAMViewController.bannerMaxWidth, 560, accuracy: 0.0001)
    }
}
