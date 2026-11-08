import XCTest
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
