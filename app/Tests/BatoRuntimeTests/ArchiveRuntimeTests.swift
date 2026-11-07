import Foundation
import Testing
import BatoCore
@testable import BatoRuntime

@MainActor
private final class ArchivingEngine: PageEngine {
    var supportedProfileIDs: Set<UUID>
    var closeRequests: [LivePage] = []
    init(_ profileID: UUID) { supportedProfileIDs = [profileID] }
    func create(_ page: LivePage, url: URL) -> Bool { true }
    func select(_ page: LivePage?) {}
    func requestClose(_ page: LivePage) { closeRequests.append(page) }
}

@MainActor
private final class Clock {
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func advance(hours: Double) { now = now.addingTimeInterval(hours * 3600) }
}

@MainActor
struct ArchiveRuntimeTests {
    private func url(_ name: String) -> URL { URL(string: "https://example.invalid/\(name)")! }

    private func makeRuntime(_ state: BrowserState, clock: Clock) throws -> (PageRuntime, ArchivingEngine) {
        let engine = ArchivingEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        runtime.clock = { clock.now }
        return (runtime, engine)
    }

    @Test func idleTabsArchiveOnlyAfterThePeriodAsTheClockAdvances() throws {
        var state = BrowserState.initial()
        let idle = try state.addTab(url: url("idle"), title: "Idle")
        let current = try state.addTab(url: url("current"), title: "Current")
        let clock = Clock()
        let (runtime, _) = try makeRuntime(state, clock: clock)
        #expect(runtime.archiveIdleTabs() == 0)
        #expect(runtime.setArchivePeriod(.day))
        #expect(runtime.archiveIdleTabs() == 0)
        clock.advance(hours: 23)
        #expect(runtime.archiveIdleTabs() == 0)
        clock.advance(hours: 2)
        #expect(runtime.archiveIdleTabs() == 1)
        #expect(runtime.state.currentWorkspace.tabs.map(\.id) == [current])
        #expect(runtime.state.archive.records.map(\.id) == [idle])
        #expect(runtime.state.archive.records.first?.archivedAt == clock.now)
    }

    @Test func switchingTabsKeepsTheLeftTabClockFromWhenItWasLastSelected() throws {
        var state = BrowserState.initial()
        let first = try state.addTab(url: url("a"), title: "A")
        let second = try state.addTab(url: url("b"), title: "B")
        let clock = Clock()
        let (runtime, _) = try makeRuntime(state, clock: clock)
        #expect(runtime.selectEntry(first))
        #expect(runtime.setArchivePeriod(.twelveHours))
        clock.advance(hours: 10)
        #expect(runtime.selectEntry(second))
        clock.advance(hours: 3)
        // The first tab was last used 3 hours ago, the second just now.
        #expect(runtime.archiveIdleTabs() == 0)
        clock.advance(hours: 10)
        let page = try #require(runtime.livePages[first])
        #expect(runtime.archiveIdleTabs() == 1)
        runtime.receive(.closed(page))
        #expect(runtime.state.currentWorkspace.tabs.map(\.id) == [second])
    }

    @Test func loadedTabIsArchivedOnlyOnceTheEngineClosesIt() throws {
        var state = BrowserState.initial()
        let tab = try state.addTab(url: url("a"), title: "A")
        _ = try state.addTab(url: url("b"), title: "B")
        let clock = Clock()
        let (runtime, engine) = try makeRuntime(state, clock: clock)
        #expect(runtime.start())
        #expect(runtime.selectEntry(tab))
        let page = try #require(runtime.livePages[tab])
        #expect(runtime.selectEntry(runtime.state.currentWorkspace.tabs[1].id))
        #expect(runtime.archiveTab(tab))
        #expect(engine.closeRequests == [page])
        #expect(runtime.state.archive.records.isEmpty)
        runtime.receive(.closed(page))
        #expect(runtime.state.archive.records.map(\.id) == [tab])
        #expect(!runtime.canReopenClosedTab)
    }

    @Test func cancelledCloseKeepsTheTabAndArchivesNothing() throws {
        var state = BrowserState.initial()
        let tab = try state.addTab(url: url("a"), title: "A")
        _ = try state.addTab(url: url("b"), title: "B")
        let (runtime, _) = try makeRuntime(state, clock: Clock())
        #expect(runtime.start())
        #expect(runtime.selectEntry(tab))
        let page = try #require(runtime.livePages[tab])
        #expect(runtime.archiveTab(tab))
        runtime.receive(.closeCancelled(page))
        #expect(runtime.state.archive.records.isEmpty)
        #expect(runtime.state.currentWorkspace.tabs.count == 2)
        // A later ordinary close is not treated as an archive.
        #expect(runtime.closeEntry(tab))
        runtime.receive(.closed(page))
        #expect(runtime.state.archive.records.isEmpty)
    }

    @Test func restoreReturnsTheTabToItsWorkspaceAndLoadsIt() throws {
        var state = BrowserState.initial()
        let home = state.activeWorkspaceID
        let tab = try state.addTab(url: url("a"), title: "A")
        let other = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        let (runtime, _) = try makeRuntime(state, clock: Clock())
        #expect(runtime.archiveTab(tab))
        #expect(runtime.activateWorkspace(other))
        #expect(runtime.restoreArchivedTab(tab))
        #expect(runtime.state.activeWorkspaceID == home)
        #expect(runtime.state.currentWorkspace.activeEntryID == tab)
        #expect(runtime.livePages[tab] != nil)
        #expect(!runtime.restoreArchivedTab(tab))
    }
}
