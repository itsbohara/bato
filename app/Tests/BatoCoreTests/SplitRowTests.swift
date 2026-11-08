import Foundation
import XCTest
@testable import BatoCore

final class SplitRowTests: XCTestCase {
    private func tab(_ state: inout BrowserState, _ name: String) throws -> UUID {
        try state.addTab(url: URL(string: "https://example.invalid/\(name)")!, title: name)
    }

    private func pair(_ state: inout BrowserState, _ a: UUID, _ b: UUID) throws -> UUID {
        try state.selectEntry(a)
        return try state.createSplit(with: b)
    }

    private func labels(_ rows: [SidebarRow]) -> [String] {
        rows.map {
            switch $0.content {
            case .page(let entry): return entry.title
            case .pair(_, let left, let right): return "\(left.title)|\(right.title)"
            }
        }
    }

    func testPairCollapsesToOneRowAtFirstMembersIndex() throws {
        var state = BrowserState.initial()
        let a = try tab(&state, "a"), b = try tab(&state, "b"), c = try tab(&state, "c"), d = try tab(&state, "d")
        _ = try pair(&state, b, d)
        XCTAssertEqual(labels(state.sidebarRows()[.tabs] ?? []), ["a", "b|d", "c"])
        XCTAssertEqual(state.sidebarRows()[.tabs]?.map(\.modelIndex), [0, 1, 2])
        _ = (a, c)
    }

    func testPairKeepsLeftPaneFirstEvenWhenRightMemberIsListedFirst() throws {
        var state = BrowserState.initial()
        let a = try tab(&state, "a"), b = try tab(&state, "b")
        try state.selectEntry(b)
        _ = try state.createSplit(with: a, side: .right)
        XCTAssertEqual(labels(state.sidebarRows()[.tabs] ?? []), ["b|a"])
        XCTAssertEqual(state.sidebarRows()[.tabs]?.first?.leadingEntryID, a)
    }

    func testPairInFolderAndCollapsedFolderRows() throws {
        var state = BrowserState.initial()
        let a = try tab(&state, "a"), b = try tab(&state, "b"), c = try tab(&state, "c")
        let id = try pair(&state, a, b)
        try state.pinSplit(id)
        let folder = try state.createFolder(name: "F")
        try state.movePin(a, toFolder: folder)
        try state.movePin(b, toFolder: folder)
        XCTAssertEqual(labels(state.sidebarRows()[.pinned(folder: folder)] ?? []), ["a|b"])
        XCTAssertEqual(labels(state.sidebarRows()[.tabs] ?? []), ["c"])
        try state.setFolderCollapsed(folder, collapsed: true)
        XCTAssertEqual(state.sidebarRows()[.pinned(folder: folder)]?.count, 0)
        _ = c
    }

    func testPairSplitAcrossSectionsRendersOnceInFirstDrawnSection() throws {
        var state = BrowserState.initial()
        let a = try tab(&state, "a"), b = try tab(&state, "b")
        try state.pinEntry(a)
        _ = try pair(&state, a, b)
        let rows = state.sidebarRows()
        XCTAssertEqual(labels(rows[.pinned(folder: nil)] ?? []), ["a|b"])
        XCTAssertEqual(rows[.tabs]?.count, 0)
    }

    func testPlacePairMovesBothMembersTogetherWithinTabs() throws {
        var state = BrowserState.initial()
        let a = try tab(&state, "a"), b = try tab(&state, "b"), c = try tab(&state, "c"), d = try tab(&state, "d")
        let id = try pair(&state, a, b)
        try state.placeSplit(id, in: .tabs, at: 2)
        XCTAssertEqual(state.currentWorkspace.tabs.map(\.title), ["c", "a", "b", "d"])
        XCTAssertEqual(labels(state.sidebarRows()[.tabs] ?? []), ["c", "a|b", "d"])
        try state.placeSplit(id, in: .tabs, at: 3)
        XCTAssertEqual(state.currentWorkspace.tabs.map(\.title), ["c", "d", "a", "b"])
        try state.placeSplit(id, in: .tabs, at: 0)
        XCTAssertEqual(state.currentWorkspace.tabs.map(\.title), ["a", "b", "c", "d"])
        XCTAssertEqual(state.currentWorkspace.splits.map(\.id), [id])
        _ = (c, d)
    }

    func testPlacePairOntoItsOwnSlotChangesNothing() throws {
        var state = BrowserState.initial()
        let a = try tab(&state, "a"), b = try tab(&state, "b"), c = try tab(&state, "c")
        let id = try pair(&state, b, c)
        let before = state
        try state.placeSplit(id, in: .tabs, at: 1)
        XCTAssertEqual(state, before)
        _ = a
    }

    func testPlacePairPinsAndUnpinsBothAndKeepsSelection() throws {
        var state = BrowserState.initial()
        let a = try tab(&state, "a"), b = try tab(&state, "b"), c = try tab(&state, "c")
        let id = try pair(&state, a, b)
        try state.placeSplit(id, in: .pinned(folder: nil), at: 0)
        XCTAssertEqual(state.currentWorkspace.pins.map(\.title), ["a", "b"])
        XCTAssertTrue(state.currentWorkspace.pins.allSatisfy { $0.kind == .pinned && $0.savedURL != nil })
        XCTAssertEqual(state.currentWorkspace.tabs.map(\.title), ["c"])
        XCTAssertEqual(state.currentSplit?.id, id)
        XCTAssertEqual(state.currentWorkspace.activeEntryID, a)
        try state.placeSplit(id, in: .tabs, at: 0)
        XCTAssertEqual(state.currentWorkspace.tabs.map(\.title), ["a", "b", "c"])
        XCTAssertTrue(state.currentWorkspace.tabs.allSatisfy { $0.kind == .temporary && $0.savedURL == nil })
        XCTAssertFalse(try XCTUnwrap(state.currentWorkspace.splits.first).isPinned)
        _ = c
    }

    func testPlacePairIntoFolderAndRejectsFavorites() throws {
        var state = BrowserState.initial()
        let a = try tab(&state, "a"), b = try tab(&state, "b"), c = try tab(&state, "c")
        let folder = try state.createFolder(name: "F")
        try state.placeEntry(c, in: .pinned(folder: folder), at: 0)
        let id = try pair(&state, a, b)
        try state.placeSplit(id, in: .pinned(folder: folder), at: 0)
        XCTAssertEqual(state.currentWorkspace.folders[0].pinIDs, [a, b, c])
        XCTAssertThrowsError(try state.placeSplit(id, in: .favorites, at: 0))
    }

    func testSingleDropIndicesCountPairAsOneRow() throws {
        var state = BrowserState.initial()
        let a = try tab(&state, "a"), b = try tab(&state, "b"), c = try tab(&state, "c"), d = try tab(&state, "d")
        _ = try pair(&state, a, b)
        try state.placeEntry(d, in: .tabs, at: 1)
        XCTAssertEqual(state.currentWorkspace.tabs.map(\.title), ["a", "b", "d", "c"])
        try state.placeEntry(d, in: .tabs, at: 0)
        XCTAssertEqual(state.currentWorkspace.tabs.map(\.title), ["d", "a", "b", "c"])
        _ = c
    }

    func testMovePairToAnotherWorkspaceMovesBothAndClearsSelection() throws {
        var state = BrowserState.initial()
        let other = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        let a = try tab(&state, "a"), b = try tab(&state, "b")
        let id = try pair(&state, a, b)
        try state.moveSplit(id, toWorkspace: other)
        let moved = try XCTUnwrap(state.workspaces.first { $0.id == other })
        XCTAssertEqual(moved.tabs.map(\.title), ["a", "b"])
        XCTAssertEqual(moved.splits.map(\.id), [id])
        XCTAssertTrue(state.currentWorkspace.tabs.isEmpty)
        XCTAssertTrue(state.currentWorkspace.splits.isEmpty)
        XCTAssertNil(state.currentWorkspace.activeEntryID)
        XCTAssertNil(state.currentWorkspace.activeSplitID)
    }

    func testSwapSidesFlipsPanesAndRatio() throws {
        var state = BrowserState.initial()
        let a = try tab(&state, "a"), b = try tab(&state, "b")
        let id = try pair(&state, a, b)
        try state.updateSplitRatio(id, ratio: 0.3)
        try state.swapSplitSides(id)
        let split = try XCTUnwrap(state.currentSplit)
        XCTAssertEqual([split.leftEntryID, split.rightEntryID], [b, a])
        XCTAssertEqual(split.dividerRatio, 0.7, accuracy: 0.0001)
        try state.setSplitOrientation(id, to: .vertical)
        XCTAssertEqual(state.currentSplit?.orientation, .vertical)
    }

    func testAdjacentSelectionTreatsPairAsOneStop() throws {
        var state = BrowserState.initial()
        let a = try tab(&state, "a"), b = try tab(&state, "b"), c = try tab(&state, "c")
        _ = try pair(&state, a, b)
        try state.selectEntry(c)
        XCTAssertEqual(state.adjacentEntryID(step: -1), a)
        try state.selectEntry(a)
        XCTAssertEqual(state.adjacentEntryID(step: 1), c)
        try state.selectEntry(b)
        XCTAssertEqual(state.adjacentEntryID(step: 1), c)
    }

    /// Regression: Ctrl-Tab away from a shown pair used to delete the pair.
    func testSwitchingAwayAndBackKeepsAndRedisplaysThePair() throws {
        var state = BrowserState.initial()
        let a = try tab(&state, "a"), b = try tab(&state, "b"), c = try tab(&state, "c")
        let id = try pair(&state, a, b)
        try state.selectEntry(c)
        XCTAssertNil(state.currentSplit)
        XCTAssertEqual(state.currentWorkspace.splits.map(\.id), [id])
        try state.selectEntry(b)
        XCTAssertEqual(state.currentSplit?.id, id)
        XCTAssertEqual(state.currentWorkspace.activeEntryID, b)
        try state.selectEntry(c)
        let next = try XCTUnwrap(state.adjacentEntryID(step: 1))
        try state.selectEntry(next)
        XCTAssertEqual(state.currentSplit?.id, id)
    }
}

final class TabSwitcherTests: XCTestCase {
    private func state(_ names: [String]) throws -> (BrowserState, [UUID]) {
        var state = BrowserState.initial()
        let ids = try names.map { try state.addTab(url: URL(string: "https://example.invalid/\($0)")!, title: $0) }
        return (state, ids)
    }

    func testRecentOrderPutsLastSelectedFirstThenNeverSelectedInSidebarOrder() throws {
        var (state, ids) = try state(["a", "b", "c", "d"])
        var recent = RecentTabs()
        let workspace = state.currentWorkspace.id
        for id in [ids[2], ids[0], ids[3]] { recent.record(entryID: id, workspaceID: workspace) }
        try state.selectEntry(ids[3])
        XCTAssertEqual(recent.items(in: state).map(\.selectionEntryID), [ids[3], ids[0], ids[2], ids[1]])
    }

    func testPairIsOneItemAtItsMostRecentMember() throws {
        var (state, ids) = try state(["a", "b", "c"])
        try state.selectEntry(ids[0])
        _ = try state.createSplit(with: ids[1])
        var recent = RecentTabs()
        let workspace = state.currentWorkspace.id
        for id in [ids[0], ids[2], ids[1]] { recent.record(entryID: id, workspaceID: workspace) }
        let items = recent.items(in: state)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].selectionEntryID, ids[1])
        XCTAssertEqual(Set(items[0].entryIDs), [ids[0], ids[1]])
        XCTAssertNotNil(items[0].splitID)
        XCTAssertEqual(items[1].selectionEntryID, ids[2])
    }

    func testUnavailableAndOtherWorkspaceEntriesAreSkipped() throws {
        var (state, ids) = try state(["a", "b"])
        var recent = RecentTabs()
        recent.record(entryID: ids[0], workspaceID: UUID())
        XCTAssertEqual(recent.items(in: state) { $0 == ids[1] }.map(\.selectionEntryID), [ids[0]])
        _ = state.currentWorkspace
    }

    private func items(_ count: Int) -> [TabSwitchItem] {
        (0..<count).map { _ in
            let id = UUID()
            return TabSwitchItem(entryIDs: [id], splitID: nil, selectionEntryID: id)
        }
    }

    func testNeedsAtLeastTwoItems() {
        XCTAssertNil(TabSwitcherSession(items: items(1), step: 1))
        XCTAssertNil(TabSwitcherSession(items: [], step: 1))
    }

    func testQuickTapTogglesToPreviousWithoutShowing() throws {
        let list = items(4)
        let session = try XCTUnwrap(TabSwitcherSession(items: list, step: 1))
        XCTAssertEqual(session.phase, .pending)
        XCTAssertEqual(session.controlReleased(), .commit(list[1]))
    }

    func testTabAdvancesShiftTabGoesBackAndBothWrap() throws {
        let list = items(3)
        var session = try XCTUnwrap(TabSwitcherSession(items: list, step: 1))
        session.advance(step: 1)
        XCTAssertEqual(session.selection, list[2])
        session.advance(step: 1)
        XCTAssertEqual(session.selection, list[0])
        session.advance(step: -1)
        XCTAssertEqual(session.selection, list[2])
        let backward = try XCTUnwrap(TabSwitcherSession(items: list, step: -1))
        XCTAssertEqual(backward.selection, list[2])
    }

    func testHoldShowsAndEscapeCancels() throws {
        var session = try XCTUnwrap(TabSwitcherSession(items: items(3), step: 1))
        session.holdElapsed()
        XCTAssertEqual(session.phase, .showing)
        XCTAssertEqual(session.escapePressed(), .cancel)
    }
}

final class SplitGrabberTests: XCTestCase {
    private let left = CGRect(x: 0, y: 0, width: 400, height: 600)
    private let right = CGRect(x: 408, y: 0, width: 392, height: 600)

    func testPillIsAShortVerticalPillCentredInTheGap() {
        let pill = SplitGrabber.pillRect(first: left, second: right)
        XCTAssertEqual(pill.midX, 404, accuracy: 0.001)
        XCTAssertEqual(pill.midY, 300, accuracy: 0.001)
        XCTAssertEqual(pill.width, 2)
        XCTAssertEqual(pill.height, 24)
    }

    func testStackedPanesGetAHorizontalPill() {
        let top = CGRect(x: 0, y: 0, width: 800, height: 296)
        let bottom = CGRect(x: 0, y: 304, width: 800, height: 296)
        let pill = SplitGrabber.pillRect(first: top, second: bottom)
        XCTAssertEqual(pill.width, 24)
        XCTAssertEqual(pill.height, 2)
        XCTAssertEqual(pill.midY, 300, accuracy: 0.001)
    }

    func testHitRectCoversTheGapAndSlopFullLength() {
        let hit = SplitGrabber.hitRect(first: left, second: right)
        XCTAssertEqual(hit.minX, 396)
        XCTAssertEqual(hit.maxX, 412)
        XCTAssertEqual(hit.height, 600)
    }

    func testRatioFollowsThePointerAndIsClamped() {
        XCTAssertEqual(SplitGrabber.ratio(at: CGPoint(x: 404, y: 10), first: left, second: right), 400.0 / 792.0, accuracy: 0.001)
        XCTAssertEqual(SplitGrabber.ratio(at: CGPoint(x: 5, y: 10), first: left, second: right), 0.15)
        XCTAssertEqual(SplitGrabber.ratio(at: CGPoint(x: 900, y: 10), first: left, second: right), 0.85)
    }
}
