import XCTest
@testable import BatoCore

final class SplitOrientationTests: XCTestCase {
    private func state() throws -> (BrowserState, UUID, UUID) {
        var state = BrowserState.initial()
        let first = try state.addTab(url: URL(string: "https://a.test/")!, title: "A")
        let second = try state.addTab(url: URL(string: "https://b.test/")!, title: "B")
        try state.selectEntry(first)
        return (state, first, second)
    }

    func testSideMappingAndOrientation() {
        XCTAssertEqual(SplitSide.right.orientation, .horizontal)
        XCTAssertEqual(SplitSide.left.orientation, .horizontal)
        XCTAssertEqual(SplitSide.top.orientation, .vertical)
        XCTAssertEqual(SplitSide.bottom.orientation, .vertical)
        XCTAssertEqual(SplitSide.allCases.filter(\.newPageIsFirst), [.left, .top])
    }

    func testCreateSplitPlacesNewPageBySide() throws {
        for side in SplitSide.allCases {
            var (state, focused, other) = try state()
            _ = try state.createSplit(with: other, side: side)
            let pair = try XCTUnwrap(state.currentSplit)
            XCTAssertEqual(pair.orientation, side.orientation)
            XCTAssertEqual(pair.leftEntryID, side.newPageIsFirst ? other : focused)
            XCTAssertEqual(pair.rightEntryID, side.newPageIsFirst ? focused : other)
        }
    }

    func testAddSplitTabFocusesNewPane() throws {
        var (state, source, _) = try state()
        let id = try state.addSplitTab(url: URL(string: "https://c.test/")!, title: "C", side: .bottom)
        let pair = try XCTUnwrap(state.currentSplit)
        XCTAssertEqual(pair.leftEntryID, source)
        XCTAssertEqual(pair.rightEntryID, id)
        XCTAssertEqual(pair.orientation, .vertical)
        XCTAssertEqual(state.currentWorkspace.activeEntryID, id)
        XCTAssertNoThrow(try state.validate())
    }

    func testAddSplitTabFromPairReplacesOtherPane() throws {
        var (state, source, other) = try state()
        _ = try state.createSplit(with: other)
        let id = try state.addSplitTab(url: URL(string: "https://c.test/")!, title: "C", side: .top)
        let pair = try XCTUnwrap(state.currentSplit)
        XCTAssertEqual(pair.leftEntryID, id)
        XCTAssertEqual(pair.rightEntryID, source)
        XCTAssertEqual(state.currentWorkspace.splits.count, 1)
        XCTAssertTrue(state.currentWorkspace.tabs.contains { $0.id == other })
        XCTAssertNoThrow(try state.validate())
    }

    func testOrientationPersistsAndOldDocumentsDecodeHorizontal() throws {
        let pair = PageSplit(leftEntryID: UUID(), rightEntryID: UUID(), orientation: .vertical)
        let decoded = try JSONDecoder().decode(PageSplit.self, from: JSONEncoder().encode(pair))
        XCTAssertEqual(decoded, pair)

        let horizontal = PageSplit(leftEntryID: UUID(), rightEntryID: UUID())
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(horizontal), encoding: .utf8))
        XCTAssertFalse(json.contains("orientation"))
        let old = try JSONDecoder().decode(PageSplit.self, from: Data(json.utf8))
        XCTAssertEqual(old.orientation, .horizontal)
    }

    func testPaneControlsFollowFocusAndHover() {
        let focused = SplitPaneControls.visible(focused: true, hovered: false)
        XCTAssertTrue(focused.isSuperset(of: [.back, .forward, .reload, .host, .extensions, .splitMenu, .close]))
        let minimal = SplitPaneControls.visible(focused: false, hovered: false)
        XCTAssertEqual(minimal, [.back, .forward, .host, .close])
        XCTAssertEqual(SplitPaneControls.visible(focused: false, hovered: true), focused)
        XCTAssertEqual(SplitPaneControls.dimmed(focused: false), [.back, .forward])
        XCTAssertTrue(SplitPaneControls.dimmed(focused: true).isEmpty)
    }

    func testSidebarToggleOnlyOnLeadingPaneWhenHidden() {
        XCTAssertTrue(SplitPaneChrome.showsSidebarToggle(paneIndex: 0, sidebarHidden: true))
        XCTAssertFalse(SplitPaneChrome.showsSidebarToggle(paneIndex: 1, sidebarHidden: true))
        XCTAssertFalse(SplitPaneChrome.showsSidebarToggle(paneIndex: 0, sidebarHidden: false))
    }

    func testToolbarFrameIsTopBandOfPane() {
        let pane = CGRect(x: 10, y: 20, width: 300, height: 400)
        XCTAssertEqual(SplitPaneChrome.toolbarFrame(ofPane: pane), CGRect(x: 10, y: 20, width: 300, height: 40))
        XCTAssertEqual(SplitPaneChrome.toolbarFrame(ofPane: CGRect(x: 0, y: 0, width: 50, height: 10)).height, 10)
    }
}
