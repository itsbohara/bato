import Foundation
import XCTest
@testable import BatoCore

final class SpaceThemeTests: XCTestCase {
    func testFieldIsBlackAtTheCentreAndWhiteAtTheRim() {
        XCTAssertEqual(SpaceTheme.fieldColor(x: 0, y: 0), "#000000")
        XCTAssertEqual(SpaceTheme.fieldColor(x: 1, y: 0), "#FFFFFF")
    }

    func testFieldHueFollowsTheAngleClockwiseFromTheRight() {
        XCTAssertEqual(SpaceTheme.fieldColor(x: 0.5, y: 0), "#FF0000")
        XCTAssertEqual(SpaceTheme.fieldColor(x: 0, y: 0.5), "#80FF00")
        XCTAssertEqual(SpaceTheme.fieldColor(x: -0.5, y: 0), "#00FFFF")
    }

    func testPositionOfAColourLandsOnTheSameLightnessAndHue() {
        let position = SpaceTheme.fieldPosition(ofColor: "#FF0000")
        XCTAssertEqual(position.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(position.y, 0, accuracy: 0.001)
    }

    func testAddingStopsStopsAtThreeAndRemovingKeepsOne() {
        var theme = SpaceTheme(color: "#527FAD")
        XCTAssertTrue(theme.addStop())
        XCTAssertTrue(theme.addStop())
        XCTAssertFalse(theme.addStop())
        XCTAssertEqual(theme.stops.count, 3)
        XCTAssertTrue(theme.removeStop(at: 2))
        XCTAssertTrue(theme.removeStop(at: 1))
        XCTAssertFalse(theme.removeStop(at: 0))
        XCTAssertEqual(theme.stops.count, 1)
    }

    func testMovingAStopClampsToTheFieldAndRecolours() {
        var theme = SpaceTheme(color: "#527FAD")
        theme.moveStop(at: 0, toX: 3, y: 0)
        XCTAssertEqual(theme.stops[0].x, 1, accuracy: 0.0001)
        XCTAssertEqual(theme.stops[0].color, "#FFFFFF")
        XCTAssertTrue(theme.isValid)
    }

    func testPresetPagesAreFullAndValid() {
        XCTAssertEqual(SpaceTheme.presetPages.count, 4)
        for page in SpaceTheme.presetPages {
            XCTAssertEqual(page.count, 9)
            for preset in page { XCTAssertTrue(SpaceTheme(stops: preset.stops).isValid) }
        }
    }

    func testInvalidThemesAreRejected() {
        XCTAssertFalse(SpaceTheme(stops: []).isValid)
        XCTAssertFalse(SpaceTheme(stops: [.init(color: "blue", x: 0, y: 0)]).isValid)
        XCTAssertFalse(SpaceTheme(stops: [.init(color: "#112233", x: 2, y: 0)]).isValid)
        XCTAssertFalse(SpaceTheme(stops: [.init(color: "#112233", x: 0, y: 0)], intensity: 1.5).isValid)
    }

    func testOldWorkspaceDecodesWithoutAThemeAndDerivesAOneColourTheme() throws {
        let workspace = Workspace(profileID: UUID(), name: "Old", color: "#527FAD")
        let data = try JSONEncoder().encode(workspace)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("\"theme\""))
        let decoded = try JSONDecoder().decode(Workspace.self, from: data)
        XCTAssertNil(decoded.theme)
        XCTAssertEqual(decoded.effectiveTheme.stops.count, 1)
        XCTAssertEqual(decoded.effectiveTheme.primaryColor, "#527FAD")
        XCTAssertEqual(decoded.effectiveTheme.intensity, SpaceTheme.defaultIntensity)
    }

    func testThemeAndIconRoundTrip() throws {
        var theme = SpaceTheme(mode: .dark, stops: [.init(color: "#112233")], intensity: 0.8, grain: 0.4)
        theme.addStop()
        let workspace = Workspace(profileID: UUID(), name: "New", color: "#112233", theme: theme, icon: "🚀")
        let decoded = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
        XCTAssertEqual(decoded, workspace)
    }

    func testAddWorkspaceWithThemeUsesItsFirstColour() throws {
        var state = BrowserState.initial()
        let theme = SpaceTheme(mode: .light, stops: [.init(color: "#a88caa", x: 0.2, y: -0.4)], grain: 0.3)
        let id = try state.addWorkspace(name: "Themed", profileID: state.profiles[0].id, theme: theme, icon: "🚀")
        let workspace = try XCTUnwrap(state.workspaces.first { $0.id == id })
        XCTAssertEqual(workspace.color, "#A88CAA")
        XCTAssertEqual(workspace.theme?.mode, .light)
        XCTAssertEqual(workspace.icon, "🚀")
        XCTAssertNoThrow(try state.validate())
    }

    func testAddWorkspaceRejectsAnInvalidThemeWithoutChangingState() {
        var state = BrowserState.initial()
        let before = state
        XCTAssertThrowsError(try state.addWorkspace(name: "Bad", profileID: state.profiles[0].id, theme: SpaceTheme(stops: [])))
        XCTAssertEqual(state, before)
    }

    func testUpdatingTheThemeMovesTheWorkspaceColour() throws {
        var state = BrowserState.initial()
        let id = state.workspaces[0].id
        try state.updateWorkspaceTheme(id, theme: SpaceTheme(stops: [.init(color: "#112233", x: 0.1, y: 0.1)]))
        XCTAssertEqual(state.workspaces[0].color, "#112233")
        XCTAssertNotNil(state.workspaces[0].theme)
    }

    func testRecolouringThroughTheOldEditorDropsTheTheme() throws {
        var state = BrowserState.initial()
        let id = state.workspaces[0].id
        try state.updateWorkspaceTheme(id, theme: SpaceTheme(stops: [.init(color: "#112233", x: 0.1, y: 0.1)]))
        try state.updateWorkspace(id, name: "Personal", color: "#527FAD")
        XCTAssertNil(state.workspaces[0].theme)
    }

    func testStateWithAnInvalidStoredThemeFailsValidation() throws {
        var state = BrowserState.initial()
        state.workspaces[0].theme = SpaceTheme(stops: [])
        XCTAssertThrowsError(try state.validate())
    }
}
