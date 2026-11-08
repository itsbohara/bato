import XCTest
import BatoCore
@testable import BatoBrowserUI

final class SidebarDropMapTests: XCTestCase {
    private let folder = UUID()
    private func frame(_ y: CGFloat, x: CGFloat = 0, width: CGFloat = 240, height: CGFloat = 38) -> NSRect {
        NSRect(x: x, y: y, width: width, height: height)
    }
    private lazy var slots: [SidebarDropSlot] = [
        .init(kind: .tile(index: 0), frame: frame(0, width: 76, height: 44)),
        .init(kind: .tile(index: 1), frame: frame(0, x: 80, width: 76, height: 44)),
        .init(kind: .row(section: .pinned(folder: nil), index: 0), frame: frame(60)),
        .init(kind: .row(section: .pinned(folder: nil), index: 1), frame: frame(100)),
        .init(kind: .folder(id: folder, pinCount: 2), frame: frame(150, height: 24)),
        .init(kind: .row(section: .pinned(folder: folder), index: 0), frame: frame(180)),
        .init(kind: .newTabRow, frame: frame(230)),
        .init(kind: .row(section: .tabs, index: 0), frame: frame(270)),
        .init(kind: .row(section: .tabs, index: 1), frame: frame(310))
    ]
    private func target(_ x: CGFloat, _ y: CGFloat) -> SidebarDropTarget? {
        SidebarDropMap.resolve(point: NSPoint(x: x, y: y), slots: slots, unfiledPinCount: 2)
    }

    func testTabRowsInsertBeforeOrAfterByHalf() {
        XCTAssertEqual(target(50, 275)?.section, .tabs)
        XCTAssertEqual(target(50, 275)?.index, 0)
        XCTAssertEqual(target(50, 300)?.index, 1)
        XCTAssertEqual(target(50, 500)?.index, 2)
    }

    func testPinnedRowsAndFolderChildren() {
        XCTAssertEqual(target(50, 65)?.section, .pinned(folder: nil))
        XCTAssertEqual(target(50, 65)?.index, 0)
        XCTAssertEqual(target(50, 135)?.index, 2)
        XCTAssertEqual(target(50, 215)?.section, .pinned(folder: folder))
        XCTAssertEqual(target(50, 215)?.index, 1)
    }

    func testFolderHeadingHighlightsAndAppends() {
        let hit = target(50, 160)
        XCTAssertEqual(hit?.section, .pinned(folder: folder))
        XCTAssertEqual(hit?.index, 2)
        XCTAssertEqual(hit?.indicator, .highlight(frame(150, height: 24)))
    }

    func testNewTabRowSplitsPinnedEndAndTabsStart() {
        XCTAssertEqual(target(50, 235)?.section, .pinned(folder: nil))
        XCTAssertEqual(target(50, 235)?.index, 2)
        XCTAssertEqual(target(50, 260)?.section, .tabs)
        XCTAssertEqual(target(50, 260)?.index, 0)
    }

    func testTilesInsertBeforeHoveredTileOrAtEnd() {
        XCTAssertEqual(target(10, 20)?.section, .favorites)
        XCTAssertEqual(target(10, 20)?.index, 0)
        XCTAssertEqual(target(150, 20)?.index, 2)
        XCTAssertEqual(target(70, 20)?.index, 1)
    }

    func testLineIsTwoPointsAndInsideTheRow() throws {
        guard case .line(let line)? = target(50, 275)?.indicator else { return XCTFail("expected a line") }
        XCTAssertEqual(line.height, 2)
        XCTAssertLessThan(line.maxY, 270)
        XCTAssertGreaterThan(line.minX, 0)
    }

    func testNoSlotsMeansNoTarget() {
        XCTAssertNil(SidebarDropMap.resolve(point: .zero, slots: [], unfiledPinCount: 0))
    }

    func testFirstTileLineStaysClearOfTheSidebarEdge() {
        guard case .line(let line)? = target(10, 20)?.indicator else { return XCTFail("expected a line") }
        XCTAssertGreaterThanOrEqual(line.minX, 3)
        XCTAssertEqual(line.width, SidebarDropMap.tileLineThickness)
    }

    func testEmptyFavoritesZoneTakesTheDropAsFirstEssential() {
        let zone = SidebarDropSlot(kind: .emptyFavorites, frame: frame(0, height: 52))
        let shifted = slots.map { SidebarDropSlot(kind: $0.kind, frame: $0.frame.offsetBy(dx: 0, dy: 60)) }
        let target = SidebarDropMap.resolve(point: NSPoint(x: 50, y: 20), slots: [zone] + shifted, unfiledPinCount: 2)
        XCTAssertEqual(target?.section, .favorites)
        XCTAssertEqual(target?.index, 0)
        XCTAssertEqual(target?.indicator, .highlight(zone.frame))
    }

    func testRowsBelowTheLineShiftAndTheLineMovesIntoTheGap() throws {
        guard case .line(let line)? = target(50, 275)?.indicator else { return XCTFail("expected a line") }
        let plan = SidebarDropMap.shiftPlan(line: line, slots: slots)
        XCTAssertEqual(plan.shifted, [7, 8])
        XCTAssertEqual(plan.line.midY, line.midY + SidebarDropMap.shiftAmount / 2)
    }

    func testTilesAndRowsAboveTheLineNeverShift() throws {
        guard case .line(let line)? = target(50, 135)?.indicator else { return XCTFail("expected a line") }
        let plan = SidebarDropMap.shiftPlan(line: line, slots: slots)
        XCTAssertFalse(plan.shifted.contains { $0 <= 3 })
        XCTAssertTrue(plan.shifted.contains(4))
    }

    func testTileLinesNeverShiftRows() throws {
        guard case .line(let line)? = target(10, 20)?.indicator else { return XCTFail("expected a line") }
        let plan = SidebarDropMap.shiftPlan(line: line, slots: slots)
        XCTAssertTrue(plan.shifted.isEmpty)
        XCTAssertEqual(plan.line, line)
    }

    func testNothingShiftsWhenDroppingAtTheEnd() throws {
        guard case .line(let line)? = target(50, 500)?.indicator else { return XCTFail("expected a line") }
        let plan = SidebarDropMap.shiftPlan(line: line, slots: slots)
        XCTAssertTrue(plan.shifted.isEmpty)
        XCTAssertEqual(plan.line, line)
    }
}
