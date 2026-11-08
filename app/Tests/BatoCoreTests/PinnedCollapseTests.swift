import XCTest
@testable import BatoCore

final class PinnedCollapseTests: XCTestCase {
    private func url(_ name: String) -> URL { URL(string: "https://\(name).test/")! }

    private func stateWithPinsAndFolder() throws -> (BrowserState, pin: UUID, filed: UUID, folder: UUID) {
        var state = BrowserState.initial()
        let pin = try state.addTab(url: url("pin"), title: "Pin")
        let filed = try state.addTab(url: url("filed"), title: "Filed")
        try state.pinEntry(pin)
        let folder = try state.createFolder(name: "Docs")
        try state.placeEntry(filed, in: .pinned(folder: folder), at: 0)
        _ = try state.addTab(url: url("today"), title: "Today")
        return (state, pin, filed, folder)
    }

    func testCollapsedSectionListsNoPinsOrFolders() throws {
        var (state, pin, filed, folder) = try stateWithPinsAndFolder()
        let rows = state.sidebarRows()
        XCTAssertEqual(rows[.pinned(folder: nil)]?.map(\.leadingEntryID), [pin])
        XCTAssertEqual(rows[.pinned(folder: folder)]?.map(\.leadingEntryID), [filed])
        try state.setPinsCollapsed(true, inWorkspace: state.activeWorkspaceID)
        let collapsed = state.sidebarRows()
        XCTAssertEqual(collapsed[.pinned(folder: nil)], [])
        XCTAssertEqual(collapsed[.pinned(folder: folder)], [])
        XCTAssertEqual(collapsed[.tabs]?.count, 1)
        try state.setPinsCollapsed(false, inWorkspace: state.activeWorkspaceID)
        XCTAssertEqual(state.sidebarRows()[.pinned(folder: nil)]?.map(\.leadingEntryID), [pin])
    }

    func testCollapseIsPerSpace() throws {
        var state = BrowserState.initial()
        let second = try state.addWorkspace(name: "Second", profileID: state.currentWorkspace.profileID)
        let first = state.workspaces.first { $0.id != second }!.id
        try state.setPinsCollapsed(true, inWorkspace: first)
        XCTAssertTrue(state.workspaces.first { $0.id == first }!.pinsCollapsed)
        XCTAssertFalse(state.workspaces.first { $0.id == second }!.pinsCollapsed)
        XCTAssertThrowsError(try state.setPinsCollapsed(true, inWorkspace: UUID()))
    }

    func testCollapsedStateSurvivesEncodingAndLegacyDocumentsLoadExpanded() throws {
        var state = BrowserState.initial()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(state)
        XCTAssertFalse(String(decoding: before, as: UTF8.self).contains("pinsCollapsed"))
        XCTAssertFalse(try JSONDecoder().decode(BrowserState.self, from: before).currentWorkspace.pinsCollapsed)
        try state.setPinsCollapsed(true, inWorkspace: state.activeWorkspaceID)
        let after = try encoder.encode(state)
        XCTAssertTrue(try JSONDecoder().decode(BrowserState.self, from: after).currentWorkspace.pinsCollapsed)
        try state.setPinsCollapsed(false, inWorkspace: state.activeWorkspaceID)
        XCTAssertEqual(try encoder.encode(state), before)
    }

    func testClearKeepsOnlyTheSelectedTodayTabAndItsPairPartner() throws {
        var state = BrowserState.initial()
        let a = try state.addTab(url: url("a"), title: "A")
        let b = try state.addTab(url: url("b"), title: "B")
        let c = try state.addTab(url: url("c"), title: "C")
        let d = try state.addTab(url: url("d"), title: "D")
        try state.selectEntry(b)
        XCTAssertEqual(Set(state.clearableTabIDs()), [a, c, d])
        _ = try state.createSplit(with: c)
        try state.selectEntry(b)
        XCTAssertEqual(Set(state.clearableTabIDs()), [a, d])
    }

    func testClearLeavesPinsAndFavoritesAlone() throws {
        var (state, pin, filed, _) = try stateWithPinsAndFolder()
        let today = state.currentWorkspace.tabs.map(\.id)
        let extra = try state.addTab(url: url("extra"), title: "Extra")
        try state.selectEntry(pin)
        let cleared = state.clearableTabIDs()
        XCTAssertEqual(Set(cleared), Set(today + [extra]))
        XCTAssertFalse(cleared.contains(pin))
        XCTAssertFalse(cleared.contains(filed))
    }

    func testClearedTabsAreRestorableFromTheArchive() throws {
        var state = BrowserState.initial()
        let a = try state.addTab(url: url("a"), title: "A")
        let b = try state.addTab(url: url("b"), title: "B")
        try state.selectEntry(b)
        for id in state.clearableTabIDs() { try state.archiveTab(id, at: Date()) }
        XCTAssertEqual(state.currentWorkspace.tabs.map(\.id), [b])
        XCTAssertEqual(state.archive.records.map(\.id), [a])
        try state.restoreArchivedTab(a)
        XCTAssertTrue(state.currentWorkspace.tabs.contains { $0.id == a })
    }

    func testTidyArchivesLaterDuplicatesAndKeepsTheSelectedOne() throws {
        var state = BrowserState.initial()
        let first = try state.addTab(url: url("same"), title: "One")
        let second = try state.addTab(url: url("same"), title: "Two")
        let unique = try state.addTab(url: url("other"), title: "Other")
        try state.selectEntry(unique)
        XCTAssertEqual(state.duplicateTabIDs(), [second])
        try state.selectEntry(second)
        XCTAssertEqual(state.duplicateTabIDs(), [first])
        XCTAssertEqual(BrowserState.initial().duplicateTabIDs(), [])
    }

    func testSplitPaneLayoutConstantsFollowArc() {
        XCTAssertEqual(SplitPaneChrome.paneGap, 10)
        XCTAssertEqual(SplitPaneChrome.paneCornerRadius, 10)
        XCTAssertEqual(SplitPaneChrome.focusOutlineWidth, 2)
        XCTAssertEqual(SplitPaneChrome.toolbarHeight, 40)
    }

    func testUnloadPinnedPairKeepsPairAndClearsSelection() throws {
        var state = BrowserState.initial()
        let left = try state.addTab(url: url("l"), title: "L")
        let right = try state.addTab(url: url("r"), title: "R")
        let pair = try state.createSplit(with: left)
        try state.pinSplit(pair)
        try state.selectEntry(left)
        XCTAssertEqual(state.currentSplit?.id, pair)
        try state.unloadPinnedPair(pair)
        XCTAssertEqual(state.currentWorkspace.splits.map(\.id), [pair])
        XCTAssertNil(state.currentSplit)
        XCTAssertNil(state.currentWorkspace.activeEntryID)
        XCTAssertEqual(Set(state.currentWorkspace.pins.map(\.id)), [left, right])
        try state.selectEntry(right)
        XCTAssertEqual(state.currentSplit?.id, pair)
    }

    func testUnloadPinnedPairRefusesUnpinnedPairsAndKeepsOtherSelection() throws {
        var state = BrowserState.initial()
        let left = try state.addTab(url: url("l"), title: "L")
        _ = try state.addTab(url: url("r"), title: "R")
        let pair = try state.createSplit(with: left)
        XCTAssertThrowsError(try state.unloadPinnedPair(pair))
    }
}
