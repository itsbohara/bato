import Foundation
import XCTest
@testable import BatoCore

final class WorkspaceDeleteTests: XCTestCase {
    private func url(_ name: String) -> URL { URL(string: "https://example.invalid/\(name)")! }

    func testLastWorkspaceInAProfileCannotBeDeleted() throws {
        var state = BrowserState.initial()
        let only = state.activeWorkspaceID
        XCTAssertFalse(state.canDeleteWorkspace(only))
        XCTAssertThrowsError(try state.deleteWorkspace(only)) {
            XCTAssertEqual($0 as? BrowserStateError, .lastWorkspaceInProfile)
        }
        let other = try state.addProfile(name: "Other")
        let otherWorkspace = try state.addWorkspace(name: "Solo", profileID: other)
        XCTAssertFalse(state.canDeleteWorkspace(otherWorkspace))
        _ = try state.addWorkspace(name: "Second", profileID: state.profiles[0].id)
        XCTAssertTrue(state.canDeleteWorkspace(only))
    }

    func testDeletingTheActiveWorkspaceSelectsTheNextSiblingInTheSameProfile() throws {
        var state = BrowserState.initial()
        let profile = state.profiles[0].id
        let first = state.activeWorkspaceID
        let other = try state.addProfile(name: "Other")
        _ = try state.addWorkspace(name: "Elsewhere", profileID: other)
        let second = try state.addWorkspace(name: "Second", profileID: profile)
        let third = try state.addWorkspace(name: "Third", profileID: profile)
        try state.activateWorkspace(second)
        try state.deleteWorkspace(second)
        XCTAssertEqual(state.activeWorkspaceID, third)
        try state.deleteWorkspace(third)
        XCTAssertEqual(state.activeWorkspaceID, first)
        XCTAssertEqual(state.profiles.count, 2)
    }

    func testDeletingAnotherWorkspaceKeepsSelectionAndDropsItsPagesAndArchive() throws {
        var state = BrowserState.initial()
        let first = state.activeWorkspaceID
        let second = try state.addWorkspace(name: "Second", profileID: state.profiles[0].id)
        try state.activateWorkspace(second)
        let tab = try state.addTab(url: url("a"), title: "A")
        _ = try state.archiveTab(tab, at: Date())
        let pinned = try state.addTab(url: url("b"), title: "B")
        try state.pinEntry(pinned)
        XCTAssertEqual(state.lossOfDeleting(workspace: second), BrowserState.WorkspaceLoss(pages: 1, archived: 1))
        try state.activateWorkspace(first)
        try state.deleteWorkspace(second)
        XCTAssertEqual(state.activeWorkspaceID, first)
        XCTAssertEqual(state.workspaces.map(\.id), [first])
        XCTAssertTrue(state.archive.records.isEmpty)
        XCTAssertNil(state.lossOfDeleting(workspace: second))
    }

    func testClosedTabHistoryForgetsTheDeletedWorkspace() {
        var stack = ClosedTabStack()
        let profile = UUID(), gone = UUID(), kept = UUID()
        stack.push(ClosedTab(profileID: profile, workspaceID: gone, title: "x", url: url("x"), index: 0))
        stack.push(ClosedTab(profileID: profile, workspaceID: kept, title: "y", url: url("y"), index: 0))
        stack.removeTabs(inWorkspace: gone)
        XCTAssertEqual(stack.tabs.map(\.title), ["y"])
    }
}
