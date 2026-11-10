import Foundation
import Testing
import BatoCore
@testable import BatoRuntime

@MainActor
private final class RecordingEngine: PageEngine {
    var supportedProfileIDs: Set<UUID> { [] }
    func supportsProfile(_ id: UUID) -> Bool { true }
    func create(_ page: LivePage, url: URL) -> Bool { true }
    func select(_ page: LivePage?) {}
    func requestClose(_ page: LivePage) {}
    var supportsPeek: Bool { false }
    func presentPeek(parent: LivePage, preview: LivePage, url: URL) -> Bool { false }
    func endPeek(restoreParent: Bool) -> PeekEndResult { .ended }
}

@MainActor
struct ProfileSpaceRuntimeTests {
    private func makeRuntime() throws -> (PageRuntime, UUID) {
        var state = BrowserState.initial()
        let created = try state.createProfile(name: "Work", color: "#527FAD", workspaceName: "Office")
        return (try PageRuntime(state: state, engine: RecordingEngine(), commit: { _ in }), created.profileID)
    }

    @Test func spaceCanJoinAnotherProfileAndBecomesCurrent() throws {
        let (runtime, work) = try makeRuntime()
        let launch = try #require(runtime.state.launchProfileID)
        #expect(runtime.addWorkspace(name: "Side", profileID: work))
        #expect(runtime.state.currentWorkspace.name == "Side")
        #expect(runtime.state.currentWorkspace.profileID == work)
        #expect(runtime.state.workspaces.filter { $0.profileID == launch }.count == 1)
    }

    @Test func spaceDefaultsToTheCurrentProfile() throws {
        let (runtime, _) = try makeRuntime()
        let current = runtime.state.currentWorkspace.profileID
        #expect(runtime.addWorkspace(name: "Same"))
        #expect(runtime.state.currentWorkspace.profileID == current)
    }

    @Test func unknownProfileIsRejected() throws {
        let (runtime, _) = try makeRuntime()
        let count = runtime.state.workspaces.count
        #expect(!runtime.addWorkspace(name: "Lost", profileID: UUID()))
        #expect(runtime.state.workspaces.count == count)
    }

    @Test func newProfileCarriesTheCreatedSpaceThemeAndIcon() throws {
        let (runtime, _) = try makeRuntime()
        var theme = SpaceTheme(color: "#7D647E")
        theme.intensity = 0.6
        #expect(runtime.createProfile(name: "Play", color: "#E1B4C6", workspaceName: "Games", theme: theme, icon: "🎮"))
        let space = runtime.state.currentWorkspace
        #expect(space.name == "Games")
        #expect(space.icon == "🎮")
        #expect(space.theme == theme)
        #expect(runtime.state.profiles.first { $0.id == space.profileID }?.name == "Play")
    }

    @Test func swipeOrderCrossesProfiles() throws {
        let (runtime, work) = try makeRuntime()
        let office = try #require(runtime.state.workspaces.first { $0.profileID == work })
        #expect(runtime.activateWorkspace(office.id))
        #expect(runtime.state.workspaces.map(\.profileID).contains(runtime.state.launchProfileID!))
        #expect(runtime.state.workspaces.count == 2)
    }
}
