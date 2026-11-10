import Foundation
import Testing
import BatoCore
@testable import BatoRuntime

@MainActor
private final class RecordingEngine: PageEngine {
    var supportedProfileIDs: Set<UUID>
    var closed: [LivePage] = []
    init(_ profileIDs: Set<UUID>) { supportedProfileIDs = profileIDs }
    func create(_ page: LivePage, url: URL) -> Bool { true }
    func select(_ page: LivePage?) {}
    func requestClose(_ page: LivePage) { closed.append(page) }
}

@MainActor
struct WorkspaceMoveProfileRuntimeTests {
    private struct SaveFailure: Error {}

    private func setup(commit: @escaping (BrowserState) throws -> Void = { _ in }) throws
        -> (PageRuntime, RecordingEngine, moving: UUID, target: UUID) {
        var state = BrowserState.initial()
        let moving = try state.addWorkspace(name: "Moving", profileID: state.profiles[0].id)
        let target = try state.addProfile(name: "Other")
        _ = try state.addWorkspace(name: "Home", profileID: target)
        let engine = RecordingEngine([state.profiles[0].id, target])
        return (try PageRuntime(state: state, engine: engine, commit: commit), engine, moving, target)
    }

    @Test func activeWorkspaceReopensItsTabInTheNewProfile() throws {
        var saved: BrowserState?
        let (runtime, engine, moving, target) = try setup(commit: { saved = $0 })
        #expect(runtime.activateWorkspace(moving))
        #expect(runtime.addTab(url: URL(string: "https://example.invalid/a")!, title: "A"))
        let tab = try #require(runtime.state.currentWorkspace.activeEntryID)
        let old = try #require(runtime.livePages[tab])
        #expect(runtime.moveWorkspace(moving, toProfile: target))
        #expect(engine.closed == [old])
        let reopened = try #require(runtime.livePages[tab])
        #expect(reopened.profileID == target)
        #expect(reopened != old)
        #expect(runtime.state.activeWorkspaceID == moving)
        #expect(saved?.workspaces.first { $0.id == moving }?.profileID == target)
        runtime.receive(.closed(old))
        #expect(runtime.state.currentWorkspace.tabs.map(\.id) == [tab])
    }

    @Test func backgroundWorkspaceClosesItsPagesWithoutShowingThem() throws {
        let (runtime, engine, moving, target) = try setup()
        #expect(runtime.activateWorkspace(moving))
        #expect(runtime.addTab(url: URL(string: "https://example.invalid/a")!, title: "A"))
        let tab = try #require(runtime.state.currentWorkspace.activeEntryID)
        let page = try #require(runtime.livePages[tab])
        let home = try #require(runtime.state.workspaces.first { $0.profileID == target }?.id)
        #expect(runtime.activateWorkspace(home))
        #expect(runtime.moveWorkspace(moving, toProfile: target))
        #expect(engine.closed.contains(page))
        #expect(runtime.livePages[tab] == nil)
        #expect(runtime.state.activeWorkspaceID == home)
    }

    @Test func refusesWhenTheSaveFails() throws {
        var fail = false
        let (runtime, engine, moving, target) = try setup(commit: { _ in if fail { throw SaveFailure() } })
        fail = true
        #expect(!runtime.moveWorkspace(moving, toProfile: target))
        #expect(runtime.state.workspaces.first { $0.id == moving }?.profileID != target)
        #expect(engine.closed.isEmpty)
    }
}
