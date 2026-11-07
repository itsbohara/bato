import Foundation
import Testing
import BatoCore
@testable import BatoRuntime

@MainActor
private final class RecordingEngine: PageEngine {
    var supportedProfileIDs: Set<UUID>
    var created: [(LivePage, URL)] = []
    var selections: [LivePage?] = []
    init(_ profiles: Set<UUID>) { supportedProfileIDs = profiles }
    func create(_ page: LivePage, url: URL) -> Bool { created.append((page, url)); return true }
    func select(_ page: LivePage?) { selections.append(page) }
    func requestClose(_ page: LivePage) {}
}

@MainActor
struct EssentialsRuntimeTests {
    @Test func openingHistoryTwiceReusesOneTabInTheCurrentProfile() throws {
        let state = BrowserState.initial()
        let engine = RecordingEngine([state.currentWorkspace.profileID])
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        #expect(runtime.openEssential(.history))
        #expect(engine.created.map(\.1) == [BrowserEssential.history.url])
        #expect(engine.created.first?.0.profileID == state.currentWorkspace.profileID)
        #expect(runtime.openEssential(.downloads))
        #expect(runtime.openEssential(.history))
        #expect(engine.created.map(\.1) == [BrowserEssential.history.url, BrowserEssential.downloads.url])
        #expect(runtime.state.currentWorkspace.tabs.count == 2)
        #expect(engine.selections.last == runtime.livePages[runtime.state.openEssentialEntry(.history)!.id])
    }

    @Test func eachProfileOpensItsOwnHistoryPage() throws {
        var state = BrowserState.initial()
        let first = state.activeWorkspaceID
        let firstProfile = state.currentWorkspace.profileID
        let secondProfile = try state.addProfile(name: "Second")
        let second = try state.addWorkspace(name: "Second space", profileID: secondProfile)
        let engine = RecordingEngine([firstProfile, secondProfile])
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        #expect(runtime.openEssential(.history))
        #expect(runtime.activateWorkspace(second))
        #expect(runtime.openEssential(.history))
        #expect(engine.created.map(\.0.profileID) == [firstProfile, secondProfile])
        #expect(runtime.activateWorkspace(first))
        #expect(runtime.openEssential(.history))
        #expect(engine.created.count == 2)
    }
}
