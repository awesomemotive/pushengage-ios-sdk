import XCTest
#if canImport(UIKit)
import UIKit
#endif
@testable import PushEngage

/// The `center` width rules (§3.2): 16 pt minimum side margins in both
/// orientations, plus a landscape-only cap of 70 % of the host width. Android's
/// `IAMWebViewContainer.createCenterLayoutParams` caps against `widthPixels` when
/// `widthPixels > heightPixels`, so the factor applies to the wide dimension.
///
/// These resolve real Auto Layout rather than duplicating the arithmetic, so a
/// constraint that reads a value before it is laid out fails here too.
final class IAMCenterLandscapeWidthTests: XCTestCase {

    private let margin: CGFloat = 16

    /// Lays out a container inside a host of `size`, with `inset` standing in for
    /// the safe-area inset on each side, and returns the container's frame.
    private func layout(size: CGSize,
                        sideInset: CGFloat = 0,
                        isLandscape: Bool) -> CGRect {
        let host = UIView(frame: CGRect(origin: .zero, size: size))

        // A guide inset from the host models the safe area; a bare UIView's own
        // safeAreaLayoutGuide is always the full bounds in a unit test.
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
        NSLayoutConstraint.activate([container.heightAnchor.constraint(equalToConstant: 200)])
        NSLayoutConstraint.activate(IAMViewController.centerConstraints(container: container,
                                                                        host: host,
                                                                        safeArea: safeArea,
                                                                        isLandscape: isLandscape,
                                                                        standardMargin: margin))
        host.setNeedsLayout()
        host.layoutIfNeeded()
        return container.frame
    }

    // MARK: - Landscape: the 70 % cap

    /// iPhone 16 landscape: 852 x 393 with a 59 pt Dynamic Island inset per side.
    /// Taking the factor off the narrow side gave 616 pt; deriving a margin from an
    /// unresolved safe area gave 478.7 pt. Both are wrong.
    func testIPhone16LandscapeCardIsSeventyPercentOfTheHostWidth() {
        let frame = layout(size: CGSize(width: 852, height: 393), sideInset: 59, isLandscape: true)
        XCTAssertEqual(frame.width, 852 * 0.7, accuracy: 0.5,
                       "the cap must be 70 % of the landscape width (596.4 pt)")
    }

    func testIPhone16LandscapeCardIsCentredOnTheHost() {
        let frame = layout(size: CGSize(width: 852, height: 393), sideInset: 59, isLandscape: true)
        XCTAssertEqual(frame.midX, 426, accuracy: 0.5)
    }

    /// Neither of the two previous wrong answers may reappear.
    func testIPhone16LandscapeCardIsNeitherOfThePreviousRegressions() {
        let width = layout(size: CGSize(width: 852, height: 393), sideInset: 59, isLandscape: true).width
        XCTAssertNotEqual(width, 616.1, accuracy: 1.0, "regressed to 70 % of the narrow dimension")
        XCTAssertNotEqual(width, 478.7, accuracy: 1.0, "regressed to a margin from an unresolved safe area")
    }

    /// No side insets: the cap is still 70 % of the host, not of the safe area.
    func testLandscapeWithoutSideInsetsStillCapsAtSeventyPercent() {
        let frame = layout(size: CGSize(width: 667, height: 375), isLandscape: true)
        XCTAssertEqual(frame.width, 667 * 0.7, accuracy: 0.5)
    }

    /// 11-inch iPad landscape. The `min(width, height)` formula gave 79 % here.
    func testIPadLandscapeCapsAtSeventyPercent() {
        let frame = layout(size: CGSize(width: 1194, height: 834), isLandscape: true)
        XCTAssertEqual(frame.width, 1194 * 0.7, accuracy: 0.5)
    }

    /// The cap tracks the host, so a wider screen yields a wider card.
    func testTheCapScalesWithTheHostWidth() {
        let narrow = layout(size: CGSize(width: 667, height: 375), isLandscape: true).width
        let wide = layout(size: CGSize(width: 1194, height: 834), isLandscape: true).width
        XCTAssertLessThan(narrow, wide)
    }

    // MARK: - The 16 pt floor still wins

    /// Heavy insets leave less than 70 % of the host inside the safe area, so the
    /// required margins must shrink the card rather than let it overhang.
    func testHeavyInsetsShrinkTheCardToRespectTheMargins() {
        let size = CGSize(width: 852, height: 393)
        let frame = layout(size: size, sideInset: 140, isLandscape: true)
        let safeWidth = 852 - 2 * 140.0
        XCTAssertEqual(frame.width, safeWidth - 2 * margin, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(frame.minX, 140 + margin - 0.5)
        XCTAssertLessThanOrEqual(frame.maxX, 852 - 140 - margin + 0.5)
    }

    /// Whatever the inset, the card stays inside the safe area by at least 16 pt.
    func testCardNeverOverhangsTheSafeArea() {
        for inset in stride(from: CGFloat(0), through: 200, by: 25) {
            let frame = layout(size: CGSize(width: 852, height: 393), sideInset: inset, isLandscape: true)
            XCTAssertGreaterThanOrEqual(frame.minX, inset + margin - 0.5, "overhang at inset \(inset)")
            XCTAssertLessThanOrEqual(frame.maxX, 852 - inset - margin + 0.5, "overhang at inset \(inset)")
        }
    }

    // MARK: - Portrait is unchanged

    /// Portrait has no cap: the card is the safe area minus a 16 pt margin a side.
    func testPortraitCardFillsTheSafeAreaMinusMargins() {
        let frame = layout(size: CGSize(width: 393, height: 852), isLandscape: false)
        XCTAssertEqual(frame.width, 393 - 2 * margin, accuracy: 0.5)
        XCTAssertEqual(frame.minX, margin, accuracy: 0.5)
    }

    func testPortraitIsNotSubjectToTheLandscapeCap() {
        let frame = layout(size: CGSize(width: 393, height: 852), isLandscape: false)
        XCTAssertGreaterThan(frame.width, 393 * IAMViewController.centerLandscapeWidthFactor)
    }

    // MARK: - The constant

    func testWidthFactorMatchesTheContract() {
        XCTAssertEqual(IAMViewController.centerLandscapeWidthFactor, 0.7, accuracy: 0.0001)
    }
}
