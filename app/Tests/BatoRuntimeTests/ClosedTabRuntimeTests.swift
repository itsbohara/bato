import Foundation
import Testing
import BatoCore
@testable import BatoRuntime

@MainActor
private final class ClosingEngine: PageEngine {
    var supportedProfileIDs: Set<UUID>
    var created: [(LivePage, URL)] = []
    init(_ profileID: UUID) { supportedProfileIDs = [profileID] }
    func create(_ page: LivePage, url: URL) -> Bool { created.append((page, url)); return true }
    func select(_ page: LivePage?) {}
    func requestClose(_ page: LivePage) {}
}

@MainActor
struct ClosedTabRuntimeTests {
    private func url(_ name: String) -> URL { URL(string: "https://example.invalid/\(name)")! }

    @Test func closingLiveTemporaryTabThenReopeningRestoresItsPositionAndLoadsIt() throws {
        var state = BrowserState.initial()
        _ = try state.addTab(url: url("a"), title: "A")
        let middle = try state.addTab(url: url("b"), title: "B")
        _ = try state.addTab(url: url("c"), title: "C")
        let engine = ClosingEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        #expect(runtime.start())
        #expect(runtime.selectEntry(middle))
        let page = try #require(runtime.livePages[middle])
        #expect(!runtime.canReopenClosedTab)
        #expect(runtime.closeEntry(middle))
        #expect(!runtime.canReopenClosedTab)
        runtime.receive(.closed(page))
        #expect(runtime.canReopenClosedTab)
        #expect(runtime.state.currentWorkspace.tabs.map(\.title) == ["A", "C"])
        #expect(runtime.reopenClosedTab())
        #expect(runtime.state.currentWorkspace.tabs.map(\.title) == ["A", "B", "C"])
        let reopened = try #require(runtime.state.currentWorkspace.activeEntryID)
        #expect(runtime.state.currentWorkspace.tabs[1].id == reopened)
        #expect(engine.created.last?.1 == url("b"))
        #expect(!runtime.canReopenClosedTab)
        #expect(!runtime.reopenClosedTab())
    }

    @Test func unloadedTabsAndRepeatedReopensComeBackNewestFirst() throws {
        var state = BrowserState.initial()
        let first = try state.addTab(url: url("a"), title: "A")
        let second = try state.addTab(url: url("b"), title: "B")
        let engine = ClosingEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        #expect(runtime.closeEntry(first))
        // Closing the unloaded first tab selected and loaded the second.
        let loaded = try #require(runtime.livePages[second])
        #expect(runtime.closeEntry(second))
        runtime.receive(.closed(loaded))
        #expect(runtime.state.currentWorkspace.tabs.isEmpty)
        #expect(runtime.reopenClosedTab())
        #expect(runtime.state.currentWorkspace.tabs.map(\.title) == ["B"])
        #expect(runtime.reopenClosedTab())
        #expect(runtime.state.currentWorkspace.tabs.map(\.title) == ["A", "B"])
    }

    @Test func savedPinsAreNeverRecordedAndHistoryIsPerProfile() throws {
        var state = BrowserState.initial()
        let pin = try state.addTab(url: url("pin"), title: "Pin")
        try state.pinEntry(pin)
        let tab = try state.addTab(url: url("t"), title: "T")
        let other = try state.addProfile(name: "Work")
        let work = try state.addWorkspace(name: "Work", profileID: other)
        let engine = ClosingEngine(state.currentWorkspace.profileID)
        engine.supportedProfileIDs.insert(other)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        #expect(runtime.start())
        #expect(runtime.closeEntry(pin))
        #expect(!runtime.canReopenClosedTab)
        let loaded = try #require(runtime.livePages[tab])
        #expect(runtime.closeEntry(tab))
        runtime.receive(.closed(loaded))
        #expect(runtime.canReopenClosedTab)
        #expect(runtime.activateWorkspace(work))
        #expect(!runtime.canReopenClosedTab)
        #expect(!runtime.reopenClosedTab())
        #expect(runtime.activateWorkspace(state.activeWorkspaceID))
        #expect(runtime.reopenClosedTab())
    }

    @Test func tabSelectionFollowsSidebarOrderAndSkipsClosingPages() throws {
        var state = BrowserState.initial()
        let ids = try (0..<3).map { try state.addTab(url: url("\($0)"), title: "\($0)") }
        let engine = ClosingEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        #expect(runtime.start())
        #expect(runtime.state.currentWorkspace.activeEntryID == ids[2])
        #expect(runtime.selectAdjacentEntry(step: 1))
        #expect(runtime.state.currentWorkspace.activeEntryID == ids[0])
        #expect(runtime.selectAdjacentEntry(step: -1))
        #expect(runtime.state.currentWorkspace.activeEntryID == ids[2])
        #expect(runtime.selectEntry(forShortcut: 2))
        #expect(runtime.state.currentWorkspace.activeEntryID == ids[1])
        #expect(!runtime.selectEntry(forShortcut: 8))
        #expect(runtime.selectEntry(forShortcut: 9))
        #expect(runtime.state.currentWorkspace.activeEntryID == ids[2])
        #expect(runtime.closeEntry(ids[0]))
        #expect(runtime.selectAdjacentEntry(step: 1) == false || runtime.state.currentWorkspace.activeEntryID != ids[0])
    }

    @Test func reopeningByMenuPositionPicksThatClosedTabAndKeepsTheOthers() throws {
        var state = BrowserState.initial()
        let first = try state.addTab(url: url("a"), title: "A")
        let second = try state.addTab(url: url("b"), title: "B")
        let runtime = try PageRuntime(state: state, engine: ClosingEngine(state.currentWorkspace.profileID), commit: { _ in })
        #expect(runtime.closeEntry(first))
        let loaded = try #require(runtime.livePages[second])
        #expect(runtime.closeEntry(second))
        runtime.receive(.closed(loaded))
        #expect(!runtime.reopenClosedTab(at: 2))
        #expect(runtime.reopenClosedTab(at: 1))
        #expect(runtime.state.currentWorkspace.tabs.map(\.title) == ["A"])
        #expect(runtime.reopenClosedTab(at: 0))
        #expect(runtime.state.currentWorkspace.tabs.map(\.title).sorted() == ["A", "B"])
        #expect(!runtime.canReopenClosedTab)
    }

    @Test func historyIsReportedOnChangeAndRestoredIntoANewRuntime() throws {
        var state = BrowserState.initial()
        let first = try state.addTab(url: url("a"), title: "A")
        let profileID = state.currentWorkspace.profileID
        let runtime = try PageRuntime(state: state, engine: ClosingEngine(profileID), commit: { _ in })
        var reported: [UUID: ClosedTabStack] = [:]
        runtime.closedTabsDidChange = { reported = $0 }
        #expect(runtime.closeEntry(first))
        #expect(reported[profileID]?.tabs.map(\.title) == ["A"])

        let relaunched = try PageRuntime(state: state, engine: ClosingEngine(profileID), commit: { _ in })
        relaunched.restoreClosedTabs(reported)
        #expect(relaunched.canReopenClosedTab)
        #expect(relaunched.reopenClosedTab())
        #expect(relaunched.state.currentWorkspace.tabs.map(\.title) == ["A", "A"])
    }

    @Test func restoreDropsUnknownProfilesAndUnreopenableURLs() throws {
        let state = BrowserState.initial()
        let profileID = state.currentWorkspace.profileID
        let workspaceID = state.currentWorkspace.id
        let runtime = try PageRuntime(state: state, engine: ClosingEngine(profileID), commit: { _ in })
        let stranger = UUID()
        runtime.restoreClosedTabs([
            profileID: ClosedTabStack(tabs: [
                ClosedTab(profileID: profileID, workspaceID: workspaceID, title: "file", url: URL(string: "file:///etc/hosts")!, index: 0)]),
            stranger: ClosedTabStack(tabs: [
                ClosedTab(profileID: stranger, workspaceID: UUID(), title: "gone", url: url("x"), index: 0)]),
        ])
        #expect(!runtime.canReopenClosedTab)
    }
}
