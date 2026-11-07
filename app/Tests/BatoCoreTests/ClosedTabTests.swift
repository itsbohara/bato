import Foundation
import XCTest
@testable import BatoCore

final class ClosedTabTests: XCTestCase {
    private func url(_ name: String) -> URL { URL(string: "https://example.invalid/\(name)")! }

    func testStackPopsMostRecentFirstAndDropsOldestPastCapacity() {
        var stack = ClosedTabStack()
        let workspace = UUID(), profile = UUID()
        for index in 0..<(ClosedTabStack.capacity + 3) {
            stack.push(ClosedTab(profileID: profile, workspaceID: workspace, title: "\(index)", url: url("\(index)"), index: 0))
        }
        XCTAssertEqual(stack.tabs.count, ClosedTabStack.capacity)
        XCTAssertEqual(stack.pop()?.title, "\(ClosedTabStack.capacity + 2)")
        XCTAssertEqual(stack.tabs.first?.title, "3")
    }

    func testClosedTabRecordsPositionOfTemporaryTabsOnly() throws {
        var state = BrowserState.initial()
        let first = try state.addTab(url: url("a"), title: "A")
        let second = try state.addTab(url: url("b"), title: "B")
        let pinned = try state.addTab(url: url("c"), title: "C")
        try state.pinEntry(pinned)
        let record = try XCTUnwrap(state.closedTab(for: second))
        XCTAssertEqual(record.index, 1)
        XCTAssertEqual(record.workspaceID, state.activeWorkspaceID)
        XCTAssertEqual(record.url, url("b"))
        XCTAssertEqual(state.closedTab(for: first)?.index, 0)
        XCTAssertNil(state.closedTab(for: pinned))
        XCTAssertNil(state.closedTab(for: UUID()))
    }

    func testReopenRestoresPositionInOriginalWorkspaceAndSelectsIt() throws {
        var state = BrowserState.initial()
        let home = state.activeWorkspaceID
        _ = try state.addTab(url: url("a"), title: "A")
        let middle = try state.addTab(url: url("b"), title: "B")
        _ = try state.addTab(url: url("c"), title: "C")
        let record = try XCTUnwrap(state.closedTab(for: middle))
        try state.closeEntry(middle)
        let other = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        try state.activateWorkspace(other)
        let reopened = try state.reopenTab(record)
        XCTAssertEqual(state.activeWorkspaceID, home)
        XCTAssertEqual(state.currentWorkspace.tabs.map(\.title), ["A", "B", "C"])
        XCTAssertEqual(state.currentWorkspace.tabs[1].id, reopened)
        XCTAssertEqual(state.currentWorkspace.activeEntryID, reopened)
        XCTAssertNotEqual(reopened, middle)
        try state.validate()
    }

    func testReopenClampsPositionAndFallsBackWhenWorkspaceIsGone() throws {
        var state = BrowserState.initial()
        let profile = state.currentWorkspace.profileID
        _ = try state.addTab(url: url("a"), title: "A")
        let record = ClosedTab(profileID: profile, workspaceID: UUID(), title: "Gone", url: url("g"), index: 40)
        let reopened = try state.reopenTab(record)
        XCTAssertEqual(state.currentWorkspace.tabs.map(\.title), ["A", "Gone"])
        XCTAssertEqual(state.currentWorkspace.activeEntryID, reopened)
        let foreign = ClosedTab(profileID: UUID(), workspaceID: state.activeWorkspaceID, title: "X", url: url("x"), index: 0)
        XCTAssertThrowsError(try state.reopenTab(foreign))
    }

    func testAdjacentSelectionWrapsInSidebarOrder() throws {
        var state = BrowserState.initial()
        let a = try state.addTab(url: url("a"), title: "A")
        let b = try state.addTab(url: url("b"), title: "B")
        let c = try state.addTab(url: url("c"), title: "C")
        try state.pinEntry(c)
        try state.selectEntry(b)
        // Order is pins then tabs: C, A, B.
        XCTAssertEqual(state.adjacentEntryID(step: 1), c)
        XCTAssertEqual(state.adjacentEntryID(step: -1), a)
        try state.selectEntry(c)
        XCTAssertEqual(state.adjacentEntryID(step: -1), b)
        XCTAssertNil(state.adjacentEntryID(step: 0))
    }

    func testShortcutsPickByPositionAndNineIsLast() throws {
        var state = BrowserState.initial()
        XCTAssertNil(state.entryID(forShortcut: 1))
        let ids = try (0..<3).map { try state.addTab(url: url("\($0)"), title: "\($0)") }
        XCTAssertEqual(state.entryID(forShortcut: 1), ids[0])
        XCTAssertEqual(state.entryID(forShortcut: 3), ids[2])
        XCTAssertNil(state.entryID(forShortcut: 4))
        XCTAssertEqual(state.entryID(forShortcut: 9), ids[2])
        XCTAssertNil(state.entryID(forShortcut: 0))
        XCTAssertNil(state.entryID(forShortcut: 10))
    }
}
