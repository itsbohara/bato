import Foundation
import XCTest
@testable import BatoCore

final class SidebarPlacementTests: XCTestCase {
    private func tab(_ state: inout BrowserState, _ name: String) throws -> UUID {
        try state.addTab(url: URL(string: "https://example.invalid/\(name)")!, title: name)
    }

    private func titles(_ entries: [PageEntry]) -> [String] { entries.map(\.title) }

    func testReorderTabsAccountsForRemovalWhenMovingDown() throws {
        var state = BrowserState.initial()
        let a = try tab(&state, "a"), b = try tab(&state, "b"), c = try tab(&state, "c")
        try state.placeEntry(a, in: .tabs, at: 3)
        XCTAssertEqual(titles(state.currentWorkspace.tabs), ["b", "c", "a"])
        try state.placeEntry(c, in: .tabs, at: 0)
        XCTAssertEqual(titles(state.currentWorkspace.tabs), ["c", "b", "a"])
        try state.placeEntry(b, in: .tabs, at: 2)
        XCTAssertEqual(titles(state.currentWorkspace.tabs), ["c", "b", "a"])
    }

    func testReorderPinsKeepsFoldersUntouched() throws {
        var state = BrowserState.initial()
        let a = try tab(&state, "a"), b = try tab(&state, "b"), c = try tab(&state, "c")
        for id in [a, b, c] { try state.pinEntry(id) }
        let folder = try state.createFolder(name: "F")
        try state.movePin(b, toFolder: folder)
        try state.placeEntry(c, in: .pinned(folder: nil), at: 0)
        let filed = Set(state.currentWorkspace.folders.flatMap(\.pinIDs))
        XCTAssertEqual(titles(state.currentWorkspace.pins.filter { !filed.contains($0.id) }), ["c", "a"])
        XCTAssertEqual(state.currentWorkspace.folders[0].pinIDs, [b])
    }

    func testTabToPinAtIndexSavesURLAndPinToTabDropsIt() throws {
        var state = BrowserState.initial()
        let a = try tab(&state, "a"), b = try tab(&state, "b"), c = try tab(&state, "c")
        try state.pinEntry(a)
        try state.pinEntry(b)
        try state.placeEntry(c, in: .pinned(folder: nil), at: 1)
        XCTAssertEqual(titles(state.currentWorkspace.pins), ["a", "c", "b"])
        XCTAssertEqual(state.currentWorkspace.pins[1].kind, .pinned)
        XCTAssertEqual(state.currentWorkspace.pins[1].savedURL, state.currentWorkspace.pins[1].lastURL)
        XCTAssertTrue(state.currentWorkspace.tabs.isEmpty)
        try state.placeEntry(a, in: .tabs, at: 0)
        XCTAssertEqual(titles(state.currentWorkspace.tabs), ["a"])
        XCTAssertNil(state.currentWorkspace.tabs[0].savedURL)
        XCTAssertEqual(state.currentWorkspace.tabs[0].kind, .temporary)
    }

    func testMoveIntoAndBetweenFoldersAndOut() throws {
        var state = BrowserState.initial()
        let a = try tab(&state, "a"), b = try tab(&state, "b"), c = try tab(&state, "c")
        let one = try state.createFolder(name: "One"), two = try state.createFolder(name: "Two")
        try state.placeEntry(a, in: .pinned(folder: one), at: 0)
        try state.placeEntry(b, in: .pinned(folder: one), at: 0)
        XCTAssertEqual(state.currentWorkspace.folders[0].pinIDs, [b, a])
        try state.placeEntry(c, in: .pinned(folder: one), at: 1)
        XCTAssertEqual(state.currentWorkspace.folders[0].pinIDs, [b, c, a])
        try state.placeEntry(b, in: .pinned(folder: two), at: 0)
        XCTAssertEqual(state.currentWorkspace.folders[1].pinIDs, [b])
        XCTAssertEqual(state.currentWorkspace.folders[0].pinIDs, [c, a])
        try state.placeEntry(a, in: .pinned(folder: one), at: 0)
        XCTAssertEqual(state.currentWorkspace.folders[0].pinIDs, [a, c])
        try state.placeEntry(c, in: .tabs, at: 0)
        XCTAssertEqual(state.currentWorkspace.folders[0].pinIDs, [a])
        XCTAssertEqual(state.currentWorkspace.tabs.map(\.id), [c])
        try state.placeEntry(a, in: .pinned(folder: nil), at: 0)
        XCTAssertEqual(state.currentWorkspace.folders[0].pinIDs, [])
        XCTAssertEqual(state.sidebarSection(of: a), .pinned(folder: nil))
    }

    func testFavoritesPromoteReorderAndDemote() throws {
        var state = BrowserState.initial()
        let a = try tab(&state, "a"), b = try tab(&state, "b"), c = try tab(&state, "c")
        try state.placeEntry(a, in: .favorites, at: 0)
        try state.placeEntry(b, in: .favorites, at: 0)
        XCTAssertEqual(state.profiles[0].favorites.map(\.id), [b, a])
        try state.placeEntry(b, in: .favorites, at: 2)
        XCTAssertEqual(state.profiles[0].favorites.map(\.id), [a, b])
        XCTAssertEqual(state.profiles[0].favorites[0].kind, .favorite)
        try state.placeEntry(a, in: .pinned(folder: nil), at: 0)
        XCTAssertEqual(state.profiles[0].favorites.map(\.id), [b])
        XCTAssertEqual(state.sidebarSection(of: a), .pinned(folder: nil))
        try state.placeEntry(b, in: .tabs, at: 0)
        XCTAssertTrue(state.profiles[0].favorites.isEmpty)
        XCTAssertEqual(state.currentWorkspace.tabs.map(\.id), [b, c])
    }

    func testSelectionSurvivesAndMissingFolderRejected() throws {
        var state = BrowserState.initial()
        let a = try tab(&state, "a")
        try state.selectEntry(a)
        try state.placeEntry(a, in: .favorites, at: 0)
        XCTAssertEqual(state.currentWorkspace.activeEntryID, a)
        XCTAssertFalse(state.canPlaceEntry(a, in: .pinned(folder: UUID())))
        let snapshot = state
        XCTAssertThrowsError(try state.placeEntry(a, in: .pinned(folder: UUID()), at: 0))
        XCTAssertEqual(state, snapshot)
        XCTAssertThrowsError(try state.placeEntry(UUID(), in: .tabs, at: 0))
    }

    func testPlacingPairMemberAcrossKindsDissolvesPair() throws {
        var state = BrowserState.initial()
        let a = try tab(&state, "a"), b = try tab(&state, "b")
        try state.selectEntry(a)
        _ = try state.createSplit(with: b)
        try state.placeEntry(b, in: .pinned(folder: nil), at: 0)
        XCTAssertTrue(state.currentWorkspace.splits.isEmpty)
        try state.validate()
    }
}
