import Foundation
import Testing
import BatoCore
@testable import BatoRuntime

@MainActor
private final class FakeEngine: PageEngine {
    var supportedProfileIDs: Set<UUID>
    var created: [(LivePage, URL)] = []
    var selections: [LivePage?] = []
    var visible: LivePage?
    var closes: [LivePage] = []
    var acceptsCreate = true
    var onCreate: ((LivePage) -> Void)?
    init(_ profileID: UUID) { supportedProfileIDs = [profileID] }
    func create(_ page: LivePage, url: URL) -> Bool {
        created.append((page, url))
        onCreate?(page)
        return acceptsCreate
    }
    func select(_ page: LivePage?) { selections.append(page); visible = page }
    func requestClose(_ page: LivePage) { closes.append(page) }
}

@MainActor
struct PageRuntimeTests {
    private let start = URL(string: "https://example.invalid/start")!
    private let next = URL(string: "https://example.invalid/next")!
    private enum Failure: Error { case disk }

    @Test func restoreIsLazyAndSelectionReusesPages() throws {
        var state = BrowserState.initial()
        let first = try state.addTab(url: start, title: "First")
        let second = try state.addTab(url: next, title: "Second")
        let engine = FakeEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        #expect(engine.created.isEmpty)
        #expect(runtime.start())
        #expect(engine.created.map { $0.0.entryID } == [second])
        #expect(runtime.selectEntry(first))
        #expect(runtime.selectEntry(second))
        #expect(engine.created.map { $0.0.entryID } == [second, first])
    }

    @Test func saveFailurePreventsPublicationAndEngineEffects() throws {
        let state = BrowserState.initial()
        let engine = FakeEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in throw Failure.disk })
        var notifications = 0
        runtime.onStateChange = { _ in notifications += 1 }
        #expect(!runtime.addTab(url: start, title: "New"))
        #expect(runtime.state == state)
        #expect(engine.created.isEmpty)
        #expect(engine.selections.isEmpty)
        #expect(notifications == 0)
        #expect(runtime.lastError == .saveFailed)
    }

    @Test func closeWaitsForEngineAndCancellationPreservesEntry() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: start, title: "Temporary")
        let engine = FakeEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        runtime.start()
        let page = try #require(runtime.livePages[id])
        #expect(runtime.closeEntry(id))
        #expect(runtime.state == state)
        #expect(engine.closes == [page])
        runtime.receive(.closeCancelled(page))
        #expect(runtime.pendingClose.isEmpty)
        #expect(runtime.livePages[id] == page)
        #expect(runtime.state == state)
        runtime.closeEntry(id)
        runtime.receive(.closed(page))
        #expect(runtime.livePages[id] == nil)
        #expect(runtime.state.visibleEntries.isEmpty)
    }

    @Test func savedCloseResetsDestinationAndOldGenerationCannotUpdateReopenedPage() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: start, title: "Pin")
        try state.pinEntry(id)
        let engine = FakeEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        runtime.start()
        let old = try #require(runtime.livePages[id])
        runtime.receive(.navigation(old, url: next, title: "Next"))
        #expect(runtime.state.visibleEntries[0].savedURL == start)
        runtime.closeEntry(id)
        runtime.receive(.closed(old))
        #expect(runtime.state.visibleEntries[0].lastURL == start)
        #expect(runtime.state.currentWorkspace.activeEntryID == nil)
        runtime.selectEntry(id)
        let fresh = try #require(runtime.livePages[id])
        #expect(fresh != old)
        let before = runtime.state
        runtime.receive(.navigation(old, url: next, title: "Stale"))
        runtime.receive(.closed(old))
        #expect(runtime.state == before)
        #expect(runtime.livePages[id] == fresh)
        #expect(engine.created.last?.1 == start)
    }

    @Test func sharedFavoriteReusesPageButUnboundProfileHasNoEffects() throws {
        var state = BrowserState.initial()
        let firstWorkspace = state.activeWorkspaceID
        let favorite = try state.addTab(url: start, title: "Favorite")
        try state.favoriteEntry(favorite)
        let other = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        let separate = try state.addProfile(name: "Separate")
        let isolated = try state.addWorkspace(name: "Isolated", profileID: separate)
        let engine = FakeEngine(state.currentWorkspace.profileID)
        var commits = 0
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in commits += 1 })
        runtime.start()
        runtime.activateWorkspace(other)
        runtime.selectEntry(favorite)
        runtime.activateWorkspace(firstWorkspace)
        #expect(engine.created.count == 1)
        let before = runtime.state
        let effects = engine.selections.count
        let saves = commits
        #expect(!runtime.activateWorkspace(isolated))
        #expect(runtime.state == before)
        #expect(engine.selections.count == effects)
        #expect(commits == saves)
        #expect(runtime.lastError == .unsupportedProfile)
    }

    @Test func invalidNavigationIsIgnoredAndBackgroundNavigationKeepsWorkspace() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: start, title: "First")
        let other = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        let engine = FakeEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        runtime.start()
        let page = try #require(runtime.livePages[id])
        runtime.activateWorkspace(other)
        let before = runtime.state
        for address in ["chrome://extensions", "https://user:secret@example.invalid/"] {
            runtime.receive(.navigation(page, url: URL(string: address)!, title: "Ignored"))
            #expect(runtime.state == before)
        }
        runtime.receive(.navigation(page, url: next, title: "Next"))
        #expect(runtime.state.activeWorkspaceID == other)
        #expect(runtime.state.workspaces[0].tabs[0].lastURL == next)
    }

    @Test func physicalCloseWithFailedSaveLeavesEntryUnloadedWithoutRecreation() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: start, title: "First")
        let engine = FakeEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in throw Failure.disk })
        runtime.start()
        let page = try #require(runtime.livePages[id])
        runtime.closeEntry(id)
        runtime.receive(.closed(page))
        #expect(runtime.state == state)
        #expect(runtime.livePages[id] == nil)
        #expect(engine.created.count == 1)
        #expect(runtime.lastError == .saveFailed)
        #expect(engine.visible == nil)
    }

    @Test func creationFailureDoesNotRemoveOrganizationEntry() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: start, title: "First")
        let engine = FakeEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        runtime.start()
        let page = try #require(runtime.livePages[id])
        runtime.receive(.creationFailed(page))
        #expect(runtime.state == state)
        #expect(runtime.livePages.isEmpty)
        #expect(runtime.lastError == .creationRejected)
    }

    @Test func synchronousCreationFailureCannotLeaveASelectedDeadToken() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: start, title: "First")
        let engine = FakeEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        engine.onCreate = { page in runtime.receive(.creationFailed(page)) }
        #expect(!runtime.start())
        #expect(runtime.state.currentWorkspace.activeEntryID == id)
        #expect(runtime.livePages.isEmpty)
        #expect(engine.visible == nil)
    }

    @Test func synchronousCallbackObserverCannotBeOverriddenByOlderSelection() throws {
        var state = BrowserState.initial()
        let first = try state.addTab(url: start, title: "First")
        let second = try state.addTab(url: next, title: "Second")
        try state.selectEntry(first)
        let engine = FakeEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        runtime.onStateChange = { state in
            if state.currentWorkspace.activeEntryID == first { runtime.selectEntry(second) }
        }
        engine.onCreate = { page in
            if page.entryID == first { runtime.receive(.navigation(page, url: next, title: "Next")) }
        }
        #expect(runtime.start())
        #expect(runtime.state.currentWorkspace.activeEntryID == second)
        #expect(engine.selections.last!?.entryID == second)
    }

    @Test func rejectedForegroundCreationHidesPreviousPage() throws {
        var state = BrowserState.initial()
        let first = try state.addTab(url: start, title: "First")
        let second = try state.addTab(url: next, title: "Second")
        try state.selectEntry(first)
        let engine = FakeEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        runtime.start()
        #expect(engine.visible?.entryID == first)
        engine.acceptsCreate = false
        #expect(!runtime.selectEntry(second))
        #expect(runtime.state.currentWorkspace.activeEntryID == second)
        #expect(engine.visible == nil)
        #expect(runtime.livePages[first] != nil)
    }

    @Test func asynchronousFailureHidesForegroundButPreservesBackgroundSelection() throws {
        var state = BrowserState.initial()
        let first = try state.addTab(url: start, title: "First")
        let second = try state.addTab(url: next, title: "Second")
        try state.selectEntry(first)
        let engine = FakeEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        runtime.start()
        let firstPage = try #require(runtime.livePages[first])
        runtime.selectEntry(second)
        let secondPage = try #require(runtime.livePages[second])
        runtime.receive(.creationFailed(firstPage))
        #expect(engine.visible == secondPage)
        runtime.receive(.creationFailed(secondPage))
        #expect(engine.visible == nil)
        #expect(runtime.state.currentWorkspace.activeEntryID == second)
    }

    @Test func failedSaveAfterPhysicalCloseHidesEngineAutoactivatedSibling() throws {
        var state = BrowserState.initial()
        let first = try state.addTab(url: start, title: "First")
        let second = try state.addTab(url: next, title: "Second")
        try state.selectEntry(first)
        let engine = FakeEngine(state.currentWorkspace.profileID)
        var fails = false
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in
            if fails { throw Failure.disk }
        })
        runtime.start()
        let sibling = try #require(runtime.livePages[first])
        runtime.selectEntry(second)
        let closing = try #require(runtime.livePages[second])
        let before = runtime.state
        runtime.closeEntry(second)
        fails = true
        engine.visible = sibling // The real engine may autoactivate a sibling.
        runtime.receive(.closed(closing))
        #expect(runtime.state == before)
        #expect(runtime.livePages[first] == sibling)
        #expect(engine.visible == nil)
        #expect(runtime.lastError == .saveFailed)
        #expect(engine.created.count == 2)
    }

    @Test func navigationBeforeCloseCancellationRetainsLatestDestination() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: start, title: "First")
        let engine = FakeEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        runtime.start()
        let page = try #require(runtime.livePages[id])
        runtime.closeEntry(id)
        runtime.receive(.navigation(page, url: next, title: "Next"))
        runtime.receive(.closeCancelled(page))
        #expect(runtime.state.visibleEntries[0].lastURL == next)
        #expect(runtime.livePages[id] == page)
        #expect(runtime.pendingClose.isEmpty)
    }
}
