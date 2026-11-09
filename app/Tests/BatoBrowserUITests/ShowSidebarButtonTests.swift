import XCTest
import BatoCore
@testable import BatoBrowserUI

@MainActor
final class ShowSidebarButtonTests: XCTestCase {
    func testButtonShowsOnlyWhileSidebarIsHidden() {
        XCTAssertTrue(ContentCardFrameView.showsSidebarButton(sidebarCoverWidth: 0))
        XCTAssertFalse(ContentCardFrameView.showsSidebarButton(sidebarCoverWidth: 260))
    }

    func testButtonSlotMatchesEngineReservation() {
        let gap = SidebarMetrics.trafficLightGap, side = SidebarMetrics.revealButtonSide
        XCTAssertEqual(gap + side + 4, 38)
    }
}

@MainActor
final class EmptyCardStateTests: XCTestCase {
    func testEmptyCardTakesHitsOnlyInsideTheCard() {
        let card = ContentCardFrameView(theme: SpaceTheme(color: "#527FAD"))
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        host.addSubview(card)
        card.frame = host.bounds
        XCTAssertNil(card.hitTest(NSPoint(x: 400, y: 300)))
        card.showsEmptyState = true
        XCTAssertTrue(card.hitTest(NSPoint(x: 400, y: 300)) === card)
        XCTAssertNil(card.hitTest(NSPoint(x: 2, y: 2)))
        XCTAssertEqual(card.accessibilityLabel(), ContentCardFrameView.emptyHint)
    }
}
