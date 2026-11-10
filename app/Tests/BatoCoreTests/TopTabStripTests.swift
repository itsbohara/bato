import XCTest
@testable import BatoCore

final class TopTabStripTests: XCTestCase {
    private func items(icons: Int, tabs: Int) -> [TopTabItem] {
        (0..<icons).map { _ in TopTabItem(id: UUID(), isIconOnly: true) } + (0..<tabs).map { _ in TopTabItem(id: UUID(), isIconOnly: false) }
    }

    func testFewTabsStayAtTheirMaximumWidth() {
        let frames = TopTabStrip.frames(for: items(icons: 0, tabs: 2), from: 100, to: 900)
        XCTAssertEqual(frames.map(\.width), [TopTabStrip.maxTabWidth, TopTabStrip.maxTabWidth])
        XCTAssertEqual(frames[0].minX, 100)
        XCTAssertEqual(frames[1].minX, 100 + TopTabStrip.maxTabWidth + TopTabStrip.gap)
    }

    func testTabsShrinkTogetherToFitTheRoom() {
        let frames = TopTabStrip.frames(for: items(icons: 0, tabs: 10), from: 0, to: 800)
        XCTAssertEqual(Set(frames.map(\.width)).count, 1)
        XCTAssertLessThan(frames[0].width, TopTabStrip.maxTabWidth)
        XCTAssertLessThanOrEqual(frames.last!.maxX, 800)
    }

    func testTabsStopShrinkingAtTheMinimumAndOverflowIsClipped() {
        let frames = TopTabStrip.frames(for: items(icons: 0, tabs: 100), from: 0, to: 600)
        XCTAssertEqual(frames[0].width, TopTabStrip.minTabWidth)
        XCTAssertGreaterThan(frames.last!.maxX, 600)
    }

    func testIconTabsKeepTheirWidthAndLeadTheTabs() {
        let frames = TopTabStrip.frames(for: items(icons: 3, tabs: 10), from: 0, to: 700)
        XCTAssertEqual(frames[0..<3].map(\.width), Array(repeating: TopTabStrip.iconTabWidth, count: 3))
        let afterIcons = frames[2].maxX + TopTabStrip.gap + TopTabStrip.groupGap
        XCTAssertEqual(frames[3].minX, afterIcons)
        XCTAssertLessThanOrEqual(frames.last!.maxX, 700)
    }

    func testNoGroupGapWithoutBothGroups() {
        let icons = TopTabStrip.frames(for: items(icons: 2, tabs: 0), from: 0, to: 500)
        XCTAssertEqual(icons[1].minX, TopTabStrip.iconTabWidth + TopTabStrip.gap)
        XCTAssertTrue(TopTabStrip.frames(for: [], from: 0, to: 500).isEmpty)
    }

    func testTabsShareTheTrafficLightsCentreLine() {
        let frame = TopTabStrip.frames(for: items(icons: 0, tabs: 1), from: 0, to: 500)[0]
        XCTAssertEqual(frame.midY, TopTabStrip.rowCenterY)
    }

    func testInsertionSlotIsTheFirstTabWhoseMidpointIsPastThePointer() {
        let frames = TopTabStrip.frames(for: items(icons: 0, tabs: 3), from: 0, to: 900)
        XCTAssertEqual(TopTabStrip.insertionSlot(atX: -5, among: frames), 0)
        XCTAssertEqual(TopTabStrip.insertionSlot(atX: frames[0].midX + 1, among: frames), 1)
        XCTAssertEqual(TopTabStrip.insertionSlot(atX: frames[1].midX + 1, among: frames), 2)
        XCTAssertEqual(TopTabStrip.insertionSlot(atX: 5000, among: frames), 3)
    }
}
