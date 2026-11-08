import Foundation
import Testing
import BatoCore
@testable import BatoRuntime

@MainActor
private final class GatedEngine: PageEngine {
    var supportedProfileIDs: Set<UUID>
    var accepting = false
    var selections: [LivePage?] = []
    init(_ profiles: Set<UUID>) { supportedProfileIDs = profiles }
    var windowPending = false
    var windowRequests: [UUID] = []
    func requestWindowIfMissing(for profileID: UUID) -> Bool {
        guard windowPending else { return false }
        windowRequests.append(profileID)
        return true
    }
    func separateSplit() -> Bool { accepting }
    func create(_ page: LivePage, url: URL) -> Bool { true }
    func select(_ page: LivePage?) { selections.append(page) }
    func requestClose(_ page: LivePage) {}
}

@MainActor
struct EmptySpaceRuntimeTests {
    @Test func aRejectedEmptySelectionIsRetriedAndClearsTheError() throws {
        let state = BrowserState.initial()
        let engine = GatedEngine([state.currentWorkspace.profileID])
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        #expect(runtime.addWorkspace(name: "Empty", color: "#527FAD") == false)
        #expect(runtime.lastError == .creationRejected)
        #expect(runtime.state.showsEmptySpace)
        engine.accepting = true
        #expect(runtime.start())
        #expect(runtime.lastError == nil)
        #expect(engine.selections.last == .some(nil))
    }

    @Test func aSpaceWithoutAnActiveTabShowsTheEmptyState() throws {
        var state = BrowserState.initial()
        _ = try state.addTab(url: URL(string: "https://example.test/")!, title: "Example")
        #expect(!state.showsEmptySpace)
        let id = try state.addWorkspace(name: "Empty", profileID: state.currentWorkspace.profileID, color: "#527FAD")
        try state.activateWorkspace(id)
        #expect(state.showsEmptySpace)
    }

    @Test func closeTabsToTheRightFollowsSidebarOrder() throws {
        let state = BrowserState.initial()
        let engine = GatedEngine([state.currentWorkspace.profileID])
        engine.accepting = true
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        #expect(!runtime.canCloseTemporaryTabsBelowSelection)
        #expect(runtime.addTab(url: URL(string: "https://one.test/")!, title: "One"))
        #expect(runtime.addTab(url: URL(string: "https://two.test/")!, title: "Two"))
        #expect(!runtime.canCloseTemporaryTabsBelowSelection)
        let first = runtime.state.visibleEntries[0].id
        #expect(runtime.selectEntry(first))
        #expect(runtime.canCloseTemporaryTabsBelowSelection)
    }

    @Test func anEmptySpaceInAWindowlessProfileRequestsItsWindowInsteadOfShowingAnother() throws {
        var state = BrowserState.initial()
        let profile = try state.addProfile(name: "Fresh")
        let id = try state.addWorkspace(name: "Fresh space", profileID: profile, color: "#527FAD")
        let engine = GatedEngine([state.currentWorkspace.profileID, profile])
        engine.accepting = true
        engine.windowPending = true
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        #expect(runtime.activateWorkspace(id))
        #expect(engine.windowRequests == [profile])
        #expect(engine.selections.isEmpty)
        engine.windowPending = false
        #expect(runtime.start())
        #expect(engine.selections.count == 1)
    }
}
