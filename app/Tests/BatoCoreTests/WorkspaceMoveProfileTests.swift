import Foundation
import XCTest
@testable import BatoCore

final class WorkspaceMoveProfileTests: XCTestCase {
    private func url(_ name: String) -> URL { URL(string: "https://example.invalid/\(name)")! }

    private func twoProfiles() throws -> (state: BrowserState, spare: UUID, target: UUID, moving: UUID) {
        var state = BrowserState.initial()
        let spare = state.activeWorkspaceID
        let moving = try state.addWorkspace(name: "Moving", profileID: state.profiles[0].id)
        let target = try state.addProfile(name: "Other")
        _ = try state.addWorkspace(name: "Home", profileID: target)
        return (state, spare, target, moving)
    }

    func testMovingChangesTheProfileAndKeepsPagesAndPosition() throws {
        var (state, _, target, moving) = try twoProfiles()
        try state.activateWorkspace(moving)
        let tab = try state.addTab(url: url("a"), title: "A")
        let before = state.workspaces.first { $0.id == moving }!
        let position = state.workspaces.firstIndex { $0.id == moving }!
        try state.moveWorkspace(moving, toProfile: target)
        let after = state.workspaces.first { $0.id == moving }!
        XCTAssertEqual(after.profileID, target)
        XCTAssertEqual(after.tabs, before.tabs)
        XCTAssertEqual(after.pins, before.pins)
        XCTAssertEqual(after.activeEntryID, tab)
        XCTAssertEqual(state.workspaces.firstIndex { $0.id == moving }, position)
    }

    func testMovingTheActiveWorkspaceKeepsItActive() throws {
        var (state, _, target, moving) = try twoProfiles()
        try state.activateWorkspace(moving)
        try state.moveWorkspace(moving, toProfile: target)
        XCTAssertEqual(state.activeWorkspaceID, moving)
        XCTAssertEqual(state.currentWorkspace.profileID, target)
    }

    func testSelectedFavoriteOfTheOldProfileIsDeselected() throws {
        var (state, _, target, moving) = try twoProfiles()
        try state.activateWorkspace(moving)
        let tab = try state.addTab(url: url("fav"), title: "Fav")
        try state.favoriteEntry(tab)
        try state.selectEntry(tab)
        XCTAssertEqual(state.currentWorkspace.activeEntryID, tab)
        try state.moveWorkspace(moving, toProfile: target)
        XCTAssertNil(state.currentWorkspace.activeEntryID)
        XCTAssertNoThrow(try state.validate())
    }

    func testRefusesTheLastWorkspaceOfItsProfileAndUnknownProfiles() throws {
        var (state, spare, target, moving) = try twoProfiles()
        XCTAssertFalse(state.canMoveWorkspace(moving, toProfile: UUID()))
        XCTAssertFalse(state.canMoveWorkspace(moving, toProfile: state.profiles[0].id))
        try state.moveWorkspace(moving, toProfile: target)
        XCTAssertFalse(state.canMoveWorkspace(spare, toProfile: target))
        XCTAssertThrowsError(try state.moveWorkspace(spare, toProfile: target)) {
            XCTAssertEqual($0 as? BrowserStateError, .lastWorkspaceInProfile)
        }
        XCTAssertThrowsError(try state.moveWorkspace(moving, toProfile: UUID())) {
            XCTAssertEqual($0 as? BrowserStateError, .missingProfile)
        }
    }

    func testPersistsThroughEncoding() throws {
        var (state, _, target, moving) = try twoProfiles()
        try state.moveWorkspace(moving, toProfile: target)
        let decoded = try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.workspaces.first { $0.id == moving }?.profileID, target)
    }
}
