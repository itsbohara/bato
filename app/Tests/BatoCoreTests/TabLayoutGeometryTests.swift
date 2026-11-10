import XCTest
@testable import BatoCore

final class TabLayoutGeometryTests: XCTestCase {
    private let window = CGSize(width: 1000, height: 700)

    func testSidebarEdges() {
        XCTAssertEqual(TabLayout.sidebar.sidebarEdge, .left)
        XCTAssertEqual(TabLayout.sidebarRight.sidebarEdge, .right)
        XCTAssertNil(TabLayout.top.sidebarEdge)
    }

    func testTopTabsFallBackToTheSidebarOnlyInFullscreen() {
        XCTAssertEqual(TabLayout.top.displayed(inFullscreen: true), .sidebar)
        XCTAssertEqual(TabLayout.top.displayed(inFullscreen: false), .top)
        XCTAssertEqual(TabLayout.sidebarRight.displayed(inFullscreen: true), .sidebarRight)
    }

    func testEngineCodesAreDistinct() {
        XCTAssertEqual(TabLayout.allCases.map(\.engineCode), [0, 1, 2])
    }

    func testLeftSidebarCardStartsAfterTheReservation() {
        let card = ChromeGeometry.cardRect(in: window, layout: .sidebar, reservation: 260)
        XCTAssertEqual(card, CGRect(x: 268, y: 8, width: 724, height: 684))
    }

    func testRightSidebarCardSitsOnTheLeftAndLeavesRoomOnTheRight() {
        let card = ChromeGeometry.cardRect(in: window, layout: .sidebarRight, reservation: 260)
        XCTAssertEqual(card, CGRect(x: 8, y: 8, width: 724, height: 684))
        XCTAssertEqual(ChromeGeometry.cardRect(in: window, layout: .sidebarRight, reservation: 0).maxX, 992)
    }

    func testTopLayoutCardStartsBelowTheStripAndIgnoresReservation() {
        let card = ChromeGeometry.cardRect(in: window, layout: .top, reservation: 260)
        XCTAssertEqual(card, CGRect(x: 8, y: 54, width: 984, height: 638))
    }

    func testCardNeverGoesNegativeInATinyWindow() {
        let card = ChromeGeometry.cardRect(in: CGSize(width: 100, height: 10), layout: .sidebarRight, reservation: 260)
        XCTAssertEqual(card.width, 0)
        XCTAssertEqual(card.height, 0)
    }

    func testCoverFollowsTheSidebarEdgeOrTheStrip() {
        XCTAssertEqual(ChromeGeometry.coverRect(in: window, layout: .sidebar, coverWidth: 260), CGRect(x: 0, y: 0, width: 260, height: 700))
        XCTAssertEqual(ChromeGeometry.coverRect(in: window, layout: .sidebarRight, coverWidth: 260), CGRect(x: 740, y: 0, width: 260, height: 700))
        XCTAssertEqual(ChromeGeometry.coverRect(in: window, layout: .top, coverWidth: 0), CGRect(x: 0, y: 0, width: 1000, height: 54))
    }
}
