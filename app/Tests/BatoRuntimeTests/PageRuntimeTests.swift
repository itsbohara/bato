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

    @Test func workspaceCustomizationCommitsWithoutPageEffectsOrClosingChanges() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: start, title: "Current")
        let other = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        let engine = FakeEngine(state.currentWorkspace.profileID)
        var committed: [BrowserState] = []
        let runtime = try PageRuntime(state: state, engine: engine, commit: { committed.append($0) })
        #expect(runtime.start())
        let page = try #require(runtime.livePages[id])
        #expect(runtime.closeEntry(id))
        let selections = engine.selections
        var publications: [BrowserState] = []
        runtime.onStateChange = { candidate in
            // Publication follows the successful persistent commit.
            #expect(committed.last == candidate)
            publications.append(candidate)
        }

        #expect(runtime.updateWorkspace(state.activeWorkspaceID, name: " Research ", color: "#a1b2c3"))
        #expect(runtime.updateWorkspace(other, name: "Work", color: "#000000"))
        #expect(committed.count == 2)
        #expect(publications == committed)
        #expect(runtime.state.currentWorkspace.name == "Research")
        #expect(runtime.state.currentWorkspace.color == "#A1B2C3")
        #expect(runtime.state.currentWorkspace.activeEntryID == id)
        #expect(runtime.livePages == [id: page])
        #expect(runtime.pendingClose == [page])
        #expect(engine.created.count == 1)
        #expect(engine.selections == selections)
        #expect(engine.closes == [page])

        // A cancelled page close still operates on the same page after editing.
        runtime.receive(.closeCancelled(page))
        #expect(runtime.pendingClose.isEmpty)
        #expect(runtime.state.currentWorkspace.activeEntryID == id)
    }

    @Test func workspaceCustomizationDoesNotLoadAnUnloadedSelection() throws {
        var state = BrowserState.initial()
        _ = try state.addTab(url: start, title: "Unloaded")
        let engine = FakeEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        #expect(runtime.updateWorkspace(state.activeWorkspaceID, name: "Work", color: "#123456"))
        #expect(engine.created.isEmpty)
        #expect(engine.selections.isEmpty)
        #expect(engine.closes.isEmpty)
        #expect(runtime.livePages.isEmpty)
    }

    @Test func failedWorkspaceCustomizationKeepsCommittedStateAndPage() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: start, title: "Current")
        let engine = FakeEngine(state.currentWorkspace.profileID)
        var saveAttempts = 0
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in
            saveAttempts += 1
            throw Failure.disk
        })
        #expect(runtime.start())
        let page = try #require(runtime.livePages[id])
        let selections = engine.selections
        var publications = 0
        runtime.onStateChange = { _ in publications += 1 }

        #expect(!runtime.updateWorkspace(state.activeWorkspaceID, name: "Work", color: "#123456"))
        #expect(runtime.lastError == .saveFailed)
        #expect(saveAttempts == 1)
        #expect(runtime.state == state)
        #expect(publications == 0)
        #expect(runtime.livePages == [id: page])
        #expect(engine.created.count == 1)
        #expect(engine.selections == selections)
        #expect(engine.closes.isEmpty)

        #expect(!runtime.updateWorkspace(state.activeWorkspaceID, name: " ", color: "#123456"))
        #expect(runtime.lastError == .invalidCommand)
        #expect(saveAttempts == 1)
        #expect(runtime.state == state)
        #expect(publications == 0)
    }

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

    @Test func savedConversionKeepsLivePageAndThenUsesConfirmedTemporaryClose() throws {
        for kind in [EntryKind.pinned, .favorite] {
            var state = BrowserState.initial()
            let id = try state.addTab(url: start, title: "Saved")
            if kind == .pinned { try state.pinEntry(id) } else { try state.favoriteEntry(id) }
            let engine = FakeEngine(state.currentWorkspace.profileID)
            var committed: [BrowserState] = []
            let runtime = try PageRuntime(state: state, engine: engine, commit: { committed.append($0) })
            runtime.start()
            let page = try #require(runtime.livePages[id])
            runtime.receive(.navigation(page, url: next, title: "Current"))
            let selections = engine.selections
            var publications: [BrowserState] = []
            runtime.onStateChange = { candidate in
                #expect(committed.last == candidate)
                publications.append(candidate)
            }
            #expect(runtime.makeTemporary(id))
            let converted = runtime.state
            #expect(publications == [converted])
            #expect(converted.currentWorkspace.tabs.first?.id == id)
            #expect(converted.currentWorkspace.tabs.first?.lastURL == next)
            #expect(converted.currentWorkspace.tabs.first?.savedURL == nil)
            #expect(converted.currentWorkspace.activeEntryID == id)
            #expect(runtime.livePages[id] == page)
            #expect(engine.visible == page)
            #expect(engine.created.count == 1)
            #expect(engine.selections == selections)
            #expect(engine.closes.isEmpty)
            #expect(runtime.closeEntry(id))
            #expect(runtime.state == converted)
            runtime.receive(.closeCancelled(page))
            #expect(runtime.state == converted)
            #expect(runtime.pendingClose.isEmpty)
            #expect(runtime.livePages[id] == page)
            #expect(runtime.closeEntry(id))
            runtime.receive(.closed(page))
            #expect(runtime.state.visibleEntries.isEmpty)
            #expect(runtime.livePages.isEmpty)
            #expect(engine.closes == [page, page])
            runtime.receive(.navigation(page, url: start, title: "Stale"))
            #expect(runtime.state.visibleEntries.isEmpty)
        }
    }

    @Test func backgroundSavedConversionDoesNotSelectOrRecreateItsPage() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: start, title: "Saved")
        try state.pinEntry(id)
        let selected = try state.addTab(url: next, title: "Selected")
        let engine = FakeEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        runtime.start()
        runtime.selectEntry(id)
        runtime.selectEntry(selected)
        let pages = runtime.livePages
        let selections = engine.selections
        #expect(runtime.makeTemporary(id))
        #expect(runtime.state.currentWorkspace.activeEntryID == selected)
        #expect(runtime.livePages == pages)
        #expect(engine.visible == pages[selected])
        #expect(engine.created.count == 2)
        #expect(engine.selections == selections)
        #expect(engine.closes.isEmpty)
    }

    @Test func unloadedSavedConversionDoesNotLoadAndRejectsNonSavedCommands() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: start, title: "Pin")
        try state.pinEntry(id)
        try state.recordNavigation(entryID: id, url: next, title: "Latest")
        let engine = FakeEngine(state.currentWorkspace.profileID)
        var saves = 0
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in saves += 1 })
        #expect(runtime.makeTemporary(id))
        #expect(runtime.livePages.isEmpty)
        #expect(engine.created.isEmpty)
        #expect(engine.selections.isEmpty)
        #expect(engine.closes.isEmpty)
        #expect(runtime.state.currentWorkspace.tabs.first?.lastURL == next)
        let converted = runtime.state
        #expect(!runtime.makeTemporary(id))
        #expect(!runtime.makeTemporary(UUID()))
        #expect(runtime.state == converted)
        #expect(saves == 1)
        #expect(runtime.start())
        #expect(engine.created.first?.1 == next)
    }

    @Test func pendingSavedCloseCannotChangeItsSavedSemanticsUntilCancelled() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: start, title: "Pin")
        try state.pinEntry(id)
        let engine = FakeEngine(state.currentWorkspace.profileID)
        var saves = 0
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in saves += 1 })
        runtime.start()
        let page = try #require(runtime.livePages[id])
        #expect(runtime.closeEntry(id))
        let before = runtime.state
        let selections = engine.selections
        #expect(!runtime.makeTemporary(id))
        #expect(runtime.lastError == .invalidCommand)
        #expect(runtime.state == before)
        #expect(saves == 0)
        #expect(runtime.pendingClose == [page])
        #expect(runtime.livePages[id] == page)
        #expect(engine.closes == [page])
        #expect(engine.selections == selections)
        runtime.receive(.closeCancelled(page))
        #expect(runtime.makeTemporary(id))
        #expect(runtime.state.currentWorkspace.tabs.first?.id == id)
    }

    @Test func failedSavedConversionPreservesSavedEntryAndLivePage() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: start, title: "Favorite")
        try state.favoriteEntry(id)
        let engine = FakeEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in throw Failure.disk })
        runtime.start()
        let page = try #require(runtime.livePages[id])
        let selections = engine.selections
        var publications = 0
        runtime.onStateChange = { _ in publications += 1 }
        #expect(!runtime.makeTemporary(id))
        #expect(runtime.lastError == .saveFailed)
        #expect(runtime.state == state)
        #expect(runtime.livePages[id] == page)
        #expect(publications == 0)
        #expect(engine.visible == page)
        #expect(engine.created.count == 1)
        #expect(engine.selections == selections)
        #expect(engine.closes.isEmpty)
    }

    @Test func explicitSavedDestinationPersistsWithoutEngineEffectsAndReopensAtUpdatedURL() throws {
        for kind in [EntryKind.pinned, .favorite] {
            var state = BrowserState.initial()
            let id = try state.addTab(url: start, title: "Saved")
            if kind == .pinned { try state.pinEntry(id) } else { try state.favoriteEntry(id) }
            let engine = FakeEngine(state.currentWorkspace.profileID)
            var committed: [BrowserState] = []
            let runtime = try PageRuntime(state: state, engine: engine, commit: { committed.append($0) })
            #expect(runtime.start())
            let old = try #require(runtime.livePages[id])
            runtime.receive(.navigation(old, url: next, title: "Next"))
            #expect(runtime.state.visibleEntries[0].savedURL == start)
            let selections = engine.selections
            var published: [BrowserState] = []
            runtime.onStateChange = { value in
                #expect(committed.last == value)
                published.append(value)
            }
            #expect(runtime.updateSavedURL(id))
            #expect(runtime.state.visibleEntries[0].savedURL == next)
            #expect(committed.last == runtime.state)
            #expect(published == [runtime.state])
            #expect(runtime.livePages[id] == old)
            #expect(engine.created.count == 1)
            #expect(engine.selections == selections)
            #expect(engine.closes.isEmpty)
            #expect(runtime.closeEntry(id))
            runtime.receive(.closed(old))
            #expect(runtime.state.visibleEntries[0].lastURL == next)
            #expect(runtime.selectEntry(id))
            let fresh = try #require(runtime.livePages[id])
            #expect(fresh != old)
            #expect(engine.created.last?.1 == next)
            let reopened = runtime.state
            runtime.receive(.navigation(old, url: start, title: "Stale"))
            runtime.receive(.closed(old))
            #expect(runtime.state == reopened)
            #expect(runtime.livePages[id] == fresh)
        }
    }

    @Test func savedDestinationUpdateAppliesToSharedFavoriteWithoutChangingWorkspace() throws {
        var state = BrowserState.initial()
        let owner = state.activeWorkspaceID
        let id = try state.addTab(url: start, title: "Favorite")
        try state.favoriteEntry(id)
        let other = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        let engine = FakeEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        runtime.start()
        let page = try #require(runtime.livePages[id])
        runtime.receive(.navigation(page, url: next, title: "Next"))
        runtime.activateWorkspace(other)
        let selections = engine.selections
        #expect(runtime.updateSavedURL(id))
        #expect(runtime.state.activeWorkspaceID == other)
        #expect(runtime.state.currentWorkspace.activeEntryID == nil)
        #expect(runtime.state.profiles[0].favorites[0].savedURL == next)
        #expect(runtime.state.workspaces.first(where: { $0.id == owner })?.activeEntryID == id)
        #expect(runtime.livePages[id] == page)
        #expect(engine.selections == selections)
        #expect(engine.created.count == 1)
    }

    @Test func savedDestinationUpdateRejectsUnloadedTemporaryClosingMissingAndInvisiblePages() throws {
        var state = BrowserState.initial()
        let temporary = try state.addTab(url: start, title: "Temporary")
        let pin = try state.addTab(url: start, title: "Pin")
        try state.pinEntry(pin)
        let other = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        let engine = FakeEngine(state.currentWorkspace.profileID)
        var saves = 0
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in saves += 1 })
        #expect(!runtime.updateSavedURL(pin))
        #expect(!runtime.updateSavedURL(temporary))
        #expect(!runtime.updateSavedURL(UUID()))
        #expect(saves == 0)
        #expect(engine.created.isEmpty)
        #expect(runtime.start())
        let page = try #require(runtime.livePages[pin])
        #expect(runtime.closeEntry(pin))
        let closing = runtime.state
        let selections = engine.selections
        #expect(!runtime.updateSavedURL(pin))
        #expect(runtime.lastError == .invalidCommand)
        #expect(runtime.state == closing)
        #expect(saves == 0)
        #expect(runtime.pendingClose == [page])
        #expect(engine.selections == selections)
        runtime.receive(.closeCancelled(page))
        #expect(runtime.selectEntry(temporary))
        let before = runtime.state
        let count = saves
        #expect(!runtime.updateSavedURL(temporary)) // Loaded, but not a saved entry.
        #expect(runtime.state == before)
        #expect(saves == count)
        #expect(runtime.activateWorkspace(other))
        let inactive = runtime.state
        let inactiveSaves = saves
        #expect(!runtime.updateSavedURL(pin)) // Live, but not visible in this workspace.
        #expect(runtime.state == inactive)
        #expect(saves == inactiveSaves)
    }

    @Test func unsupportedOrFailedLatestNavigationCannotSaveAnOlderDestination() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: start, title: "Pin")
        try state.pinEntry(id)
        let engine = FakeEngine(state.currentWorkspace.profileID)
        var fails = false
        var saves = 0
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in
            saves += 1
            if fails { throw Failure.disk }
        })
        runtime.start()
        let page = try #require(runtime.livePages[id])
        runtime.receive(.navigation(page, url: next, title: "Next"))
        #expect(runtime.canUpdateSavedURL(id))
        let before = runtime.state
        for address in ["chrome://settings", "https://user:secret@example.invalid/"] {
            runtime.receive(.navigation(page, url: URL(string: address)!, title: "Unsupported"))
            #expect(!runtime.canUpdateSavedURL(id))
            let count = saves
            #expect(!runtime.updateSavedURL(id))
            #expect(saves == count)
            #expect(runtime.state == before)
        }
        runtime.receive(.navigation(page, url: next, title: "Next"))
        #expect(runtime.canUpdateSavedURL(id))
        fails = true
        runtime.receive(.navigation(page, url: start, title: "Unsaved navigation"))
        #expect(!runtime.canUpdateSavedURL(id))
        let count = saves
        fails = false // Fixing storage alone cannot make the stale URL current.
        #expect(!runtime.updateSavedURL(id))
        #expect(saves == count)
        #expect(runtime.state.visibleEntries[0].savedURL == start)
        runtime.receive(.navigation(page, url: next, title: "Recovered"))
        #expect(runtime.canUpdateSavedURL(id))
        #expect(runtime.updateSavedURL(id))
        #expect(runtime.state.visibleEntries[0].savedURL == next)

        // The rejection belongs to this generation, not a later reload.
        runtime.receive(.navigation(page, url: URL(string: "chrome://settings")!, title: "Unsupported"))
        runtime.receive(.unloaded(page))
        #expect(!runtime.canUpdateSavedURL(id))
        #expect(runtime.selectEntry(id))
        let fresh = try #require(runtime.livePages[id])
        #expect(fresh != page)
        #expect(runtime.canUpdateSavedURL(id))
        runtime.receive(.navigation(page, url: URL(string: "chrome://settings")!, title: "Stale"))
        #expect(runtime.canUpdateSavedURL(id))
    }

    @Test func newerRejectedNavigationDuringPublicationKeepsSavedDestinationBlocked() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: start, title: "Pin")
        try state.pinEntry(id)
        let engine = FakeEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        runtime.start()
        let page = try #require(runtime.livePages[id])
        runtime.onStateChange = { _ in
            runtime.receive(.navigation(page, url: URL(string: "chrome://settings")!, title: "Internal"))
        }
        runtime.receive(.navigation(page, url: next, title: "Next"))
        #expect(runtime.state.visibleEntries[0].lastURL == next)
        #expect(!runtime.canUpdateSavedURL(id))
        #expect(!runtime.updateSavedURL(id))
        #expect(runtime.state.visibleEntries[0].savedURL == start)
        runtime.onStateChange = nil
        runtime.receive(.navigation(page, url: next, title: "Recovered"))
        #expect(runtime.canUpdateSavedURL(id))
    }

    @Test func failedSavedDestinationCommitPreservesPriorDestinationAndLivePage() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: start, title: "Pin")
        try state.pinEntry(id)
        let engine = FakeEngine(state.currentWorkspace.profileID)
        var fails = false
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in
            if fails { throw Failure.disk }
        })
        runtime.start()
        let page = try #require(runtime.livePages[id])
        runtime.receive(.navigation(page, url: next, title: "Next"))
        let before = runtime.state
        let selections = engine.selections
        var publications = 0
        runtime.onStateChange = { _ in publications += 1 }
        fails = true
        #expect(!runtime.updateSavedURL(id))
        #expect(runtime.lastError == .saveFailed)
        #expect(runtime.state == before)
        #expect(runtime.state.visibleEntries[0].savedURL == start)
        #expect(runtime.livePages[id] == page)
        #expect(publications == 0)
        #expect(engine.created.count == 1)
        #expect(engine.selections == selections)
        #expect(engine.closes.isEmpty)
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
    @Test func unsolicitedTeardownPreservesOrganizationAndRejectsLateCallbacks() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: start, title: "Preserved session")
        let engine = FakeEngine(state.currentWorkspace.profileID)
        var saves = 0
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in saves += 1 })
        runtime.start()
        let old = try #require(runtime.livePages[id])
        runtime.receive(.unloaded(old))
        #expect(runtime.state == state)
        #expect(runtime.livePages.isEmpty)
        #expect(engine.visible == nil)
        #expect(saves == 0)
        runtime.receive(.navigation(old, url: next, title: "Late"))
        runtime.receive(.closed(old))
        #expect(runtime.state == state)
        #expect(saves == 0)
        runtime.selectEntry(id)
        #expect(runtime.livePages[id] != old)
    }

    @Test func engineTabSelectionAtomicallyRestoresOwnerWorkspace() throws {
        var state = BrowserState.initial()
        let owner = state.activeWorkspaceID
        let first = try state.addTab(url: start, title: "First")
        let engine = FakeEngine(state.currentWorkspace.profileID)
        var saved: [BrowserState] = []
        let runtime = try PageRuntime(state: state, engine: engine, commit: { saved.append($0) })
        runtime.start()
        let page = try #require(runtime.livePages[first])
        runtime.addWorkspace(name: "Other")
        let other = runtime.state.activeWorkspaceID
        runtime.receive(.selected(page))
        #expect(runtime.state.activeWorkspaceID == owner)
        #expect(runtime.state.currentWorkspace.activeEntryID == first)
        #expect(saved.last?.activeWorkspaceID != other)
        #expect(engine.created.count == 1)
        let count = saved.count
        runtime.receive(.selected(page))
        #expect(saved.count == count)
        runtime.receive(.selectionCleared)
        #expect(runtime.state.currentWorkspace.activeEntryID == nil)
        #expect(runtime.state.visibleEntries.count == 1)
        #expect(runtime.livePages[first] == page)
    }

    @Test func failedExternalSelectionRestoresCommittedEnginePage() throws {
        var state = BrowserState.initial()
        let first = try state.addTab(url: start, title: "First")
        let second = try state.addTab(url: next, title: "Second")
        let engine = FakeEngine(state.currentWorkspace.profileID)
        var fails = false
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in if fails { throw Failure.disk } })
        runtime.start()
        runtime.selectEntry(first)
        let firstPage = try #require(runtime.livePages[first])
        let secondPage = try #require(runtime.livePages[second])
        fails = true
        engine.visible = secondPage
        runtime.receive(.selected(secondPage))
        #expect(runtime.state.currentWorkspace.activeEntryID == first)
        #expect(engine.visible == firstPage)
        runtime.receive(.selectionCleared)
        #expect(runtime.state.currentWorkspace.activeEntryID == first)
        #expect(engine.visible == firstPage)
    }

}
