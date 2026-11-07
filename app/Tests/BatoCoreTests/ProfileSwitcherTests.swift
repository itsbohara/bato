import Foundation
import XCTest
@testable import BatoCore

final class ProfileSwitcherTests: XCTestCase {
    func testCreateProfileAddsProfileAndFirstWorkspaceTogether() throws {
        var state = BrowserState.initial()
        let before = state.activeWorkspaceID
        let created = try state.createProfile(name: "  Research ", color: "#527fad", workspaceName: " Reading ")
        XCTAssertEqual(state.profiles.last?.id, created.profileID)
        XCTAssertEqual(state.profiles.last?.name, "Research")
        XCTAssertEqual(state.profiles.last?.color, "#527FAD")
        let workspace = try XCTUnwrap(state.workspaces.first { $0.id == created.workspaceID })
        XCTAssertEqual(workspace.profileID, created.profileID)
        XCTAssertEqual(workspace.name, "Reading")
        XCTAssertEqual(workspace.color, "#527FAD")
        XCTAssertEqual(state.activeWorkspaceID, before)
        XCTAssertEqual(state.launchProfileID, state.profiles.first?.id)
        try state.validate()
    }

    func testCreateProfileFailuresLeaveStateUntouched() throws {
        var state = BrowserState.initial()
        let original = state
        XCTAssertThrowsError(try state.createProfile(name: " ", color: "#527FAD", workspaceName: "A")) {
            XCTAssertEqual($0 as? BrowserStateError, .emptyName)
        }
        XCTAssertThrowsError(try state.createProfile(name: "A", color: "#527FAD", workspaceName: " ")) {
            XCTAssertEqual($0 as? BrowserStateError, .emptyName)
        }
        XCTAssertThrowsError(try state.createProfile(name: "A", color: "blue", workspaceName: "A")) {
            XCTAssertEqual($0 as? BrowserStateError, .invalidColor)
        }
        XCTAssertThrowsError(try state.createProfile(name: " personal ", color: "#527FAD", workspaceName: "A")) {
            XCTAssertEqual($0 as? BrowserStateError, .duplicateProfileName)
        }
        XCTAssertEqual(state, original)
    }

    func testUpdateProfileRenamesRecolorsAndKeepsIdentity() throws {
        var state = BrowserState.initial()
        let id = try XCTUnwrap(state.launchProfileID)
        try state.updateProfile(id, name: " Home ", color: "#6d8b70")
        XCTAssertEqual(state.profiles[0].id, id)
        XCTAssertEqual(state.profiles[0].name, "Home")
        XCTAssertEqual(state.profiles[0].color, "#6D8B70")
        XCTAssertEqual(state.launchProfileID, id)
        try state.updateProfile(id, name: "HOME", color: "#6D8B70")
    }

    func testUpdateProfileRejectsInvalidInputAtomically() throws {
        var state = BrowserState.initial()
        let other = try state.createProfile(name: "Work", color: "#527FAD", workspaceName: "Work")
        let original = state
        let launch = try XCTUnwrap(state.launchProfileID)
        XCTAssertThrowsError(try state.updateProfile(launch, name: "work", color: "#527FAD")) {
            XCTAssertEqual($0 as? BrowserStateError, .duplicateProfileName)
        }
        XCTAssertThrowsError(try state.updateProfile(launch, name: "", color: "#527FAD"))
        XCTAssertThrowsError(try state.updateProfile(launch, name: "X", color: "#12"))
        XCTAssertThrowsError(try state.updateProfile(UUID(), name: "X", color: "#527FAD")) {
            XCTAssertEqual($0 as? BrowserStateError, .missingProfile)
        }
        XCTAssertEqual(state, original)
        XCTAssertNotEqual(other.profileID, launch)
    }

    func testProfileColorIsOptionalAndLegacyDocumentsKeepTheirBytes() throws {
        let state = BrowserState.initial()
        let encoded = try JSONEncoder().encode(state)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let profiles = try XCTUnwrap(json["profiles"] as? [[String: Any]])
        XCTAssertNil(profiles[0]["color"])
        let decoded = try JSONDecoder().decode(BrowserState.self, from: encoded)
        XCTAssertNil(decoded.profiles[0].color)
        XCTAssertEqual(decoded.displayColor(of: decoded.profiles[0]), decoded.workspaces[0].color)
        var colored = state
        colored.profiles[0].color = "#8975A8"
        XCTAssertEqual(try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(colored)), colored)
        colored.profiles[0].color = "purple"
        XCTAssertThrowsError(try colored.validate()) { XCTAssertEqual($0 as? BrowserStateError, .invalidColor) }
    }

    func testSwitcherGroupsWorkspacesByProfileAndShortcutsFollowThatOrder() throws {
        var state = BrowserState.initial()
        let launch = try XCTUnwrap(state.launchProfileID)
        XCTAssertFalse(state.hasMultipleProfiles)
        let work = try state.createProfile(name: "Work", color: "#527FAD", workspaceName: "Office")
        let second = try state.addWorkspace(name: "Home", profileID: launch)
        XCTAssertTrue(state.hasMultipleProfiles)
        let groups = state.profileGroups
        XCTAssertEqual(groups.map(\.profile.name), ["Personal", "Work"])
        XCTAssertEqual(groups.map(\.isLaunch), [true, false])
        XCTAssertEqual(groups[0].workspaces.map(\.id), [state.workspaces[0].id, second])
        XCTAssertEqual(groups[1].workspaces.map(\.id), [work.workspaceID])
        XCTAssertEqual(state.workspaces.map(\.id).last, second)
        XCTAssertEqual(state.switcherWorkspaceIDs, [state.workspaces[0].id, second, work.workspaceID])
        XCTAssertEqual(state.switcherWorkspaceID(forShortcut: 3), work.workspaceID)
        XCTAssertNil(state.switcherWorkspaceID(forShortcut: 0))
        XCTAssertNil(state.switcherWorkspaceID(forShortcut: 4))
    }

    func testDisplayColorPrefersProfileColorThenFirstWorkspace() throws {
        var state = BrowserState.initial()
        let imported = try state.addProfile(name: "Imported")
        XCTAssertEqual(state.displayColor(of: state.profiles[1]), "#B47879")
        try state.addWorkspace(name: "W", profileID: imported)
        state.workspaces[1].color = "#76818F"
        XCTAssertEqual(state.displayColor(of: state.profiles[1]), "#76818F")
        state.profiles[1].color = "#B38847"
        XCTAssertEqual(state.displayColor(of: state.profiles[1]), "#B38847")
    }
}
