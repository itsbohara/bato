import Foundation
import XCTest
@testable import BatoCore

final class NewSpaceTests: XCTestCase {
    private let palette = ["#B47879", "#527FAD", "#6D8B70"]

    func testAddWorkspaceKeepsTheChosenColourUppercased() throws {
        var state = BrowserState.initial()
        let id = try state.addWorkspace(name: "Research", profileID: state.profiles[0].id, color: "#527fad")
        XCTAssertEqual(state.workspaces.first { $0.id == id }?.color, "#527FAD")
    }

    func testAddWorkspaceRejectsAnInvalidColourWithoutChangingState() throws {
        var state = BrowserState.initial()
        let before = state
        XCTAssertThrowsError(try state.addWorkspace(name: "Bad", profileID: state.profiles[0].id, color: "blue"))
        XCTAssertEqual(state, before)
    }

    func testNextColourSkipsOnesTheProfileAlreadyUses() throws {
        var state = BrowserState.initial()
        let profile = state.profiles[0].id
        XCTAssertEqual(state.nextWorkspaceColor(in: palette, profileID: profile), "#527FAD")
        _ = try state.addWorkspace(name: "Two", profileID: profile, color: "#527FAD")
        XCTAssertEqual(state.nextWorkspaceColor(in: palette, profileID: profile), "#6D8B70")
    }

    func testNextColourFallsBackToTheFirstWhenEveryOneIsUsed() throws {
        var state = BrowserState.initial()
        let profile = state.profiles[0].id
        _ = try state.addWorkspace(name: "Two", profileID: profile, color: "#527FAD")
        _ = try state.addWorkspace(name: "Three", profileID: profile, color: "#6D8B70")
        XCTAssertEqual(state.nextWorkspaceColor(in: palette, profileID: profile), "#B47879")
    }
}
