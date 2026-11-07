import Foundation
import Testing
import BatoCore
@testable import BatoRuntime

@MainActor
private final class RecordingEngine: PageEngine {
    var supportedProfileIDs: Set<UUID>
    var created: [(LivePage, URL)] = []
    var selected: [LivePage?] = []
    init(_ profileID: UUID) { supportedProfileIDs = [profileID] }
    func create(_ page: LivePage, url: URL) -> Bool { created.append((page, url)); return true }
    func select(_ page: LivePage?) { selected.append(page) }
    func requestClose(_ page: LivePage) {}
}

@MainActor
struct TabCommandsRuntimeTests {
    private func url(_ name: String) -> URL { URL(string: "https://example.invalid/\(name)")! }

    private func runtime(titles: [String]) throws -> (PageRuntime, RecordingEngine, [UUID]) {
        var state = BrowserState.initial()
        let ids = try titles.map { try state.addTab(url: url($0), title: $0) }
        let engine = RecordingEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        return (runtime, engine, ids)
    }

    @Test func closingTheSelectedTabSelectsTheNextOneAndLoadsIt() throws {
        let (runtime, engine, ids) = try runtime(titles: ["a", "b", "c"])
        #expect(runtime.selectEntry(ids[1]))
        let page = try #require(runtime.livePages[ids[1]])
        #expect(runtime.closeEntry(ids[1]))
        // Chromium selects its own neighbour first; the sidebar neighbour must win.
        runtime.receive(.selectionCleared)
        #expect(runtime.state.currentWorkspace.activeEntryID == ids[1])
        runtime.receive(.closed(page))
        #expect(runtime.state.currentWorkspace.activeEntryID == ids[2])
        #expect(engine.created.contains { $0.0.entryID == ids[2] })
    }

    @Test func closingTheLastTabSelectsThePreviousOne() throws {
        let (runtime, _, ids) = try runtime(titles: ["a", "b"])
        #expect(runtime.selectEntry(ids[1]))
        let page = try #require(runtime.livePages[ids[1]])
        #expect(runtime.closeEntry(ids[1]))
        runtime.receive(.closed(page))
        #expect(runtime.state.currentWorkspace.activeEntryID == ids[0])
    }

    @Test func closingTheOnlyTabLeavesNothingSelected() throws {
        let (runtime, _, ids) = try runtime(titles: ["a"])
        #expect(runtime.selectEntry(ids[0]))
        let page = try #require(runtime.livePages[ids[0]])
        #expect(runtime.closeEntry(ids[0]))
        runtime.receive(.closed(page))
        #expect(runtime.state.currentWorkspace.activeEntryID == nil)
    }

    @Test func closingABackgroundTabKeepsTheSelection() throws {
        let (runtime, _, ids) = try runtime(titles: ["a", "b", "c"])
        #expect(runtime.selectEntry(ids[0]))
        #expect(runtime.selectEntry(ids[1]))
        let background = try #require(runtime.livePages[ids[0]])
        #expect(runtime.closeEntry(ids[0]))
        runtime.receive(.closed(background))
        #expect(runtime.state.currentWorkspace.activeEntryID == ids[1])
    }

    @Test func duplicateOpensAnotherTemporaryTabOnTheSameAddress() throws {
        let (runtime, _, ids) = try runtime(titles: ["a", "b"])
        #expect(runtime.selectEntry(ids[0]))
        #expect(runtime.duplicateSelectedEntry())
        #expect(runtime.state.currentWorkspace.tabs.map(\.lastURL) == [url("a"), url("b"), url("a")])
    }

    @Test func pinTabPinsATemporaryTabAndUnpinsAPin() throws {
        let (runtime, _, ids) = try runtime(titles: ["a", "b"])
        #expect(runtime.selectEntry(ids[1]))
        #expect(runtime.togglePinSelectedEntry())
        #expect(runtime.state.currentWorkspace.pins.map(\.id) == [ids[1]])
        #expect(runtime.togglePinSelectedEntry())
        #expect(runtime.state.currentWorkspace.pins.isEmpty)
        #expect(runtime.state.currentWorkspace.tabs.map(\.id).contains(ids[1]))
    }

    @Test func closeOtherAndCloseBelowOnlyTouchTemporaryTabs() throws {
        var state = BrowserState.initial()
        let pin = try state.addTab(url: url("pin"), title: "Pin")
        try state.pinEntry(pin)
        let ids = try ["a", "b", "c", "d"].map { try state.addTab(url: url($0), title: $0) }
        let engine = RecordingEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        #expect(runtime.selectEntry(ids[1]))
        #expect(runtime.closeTemporaryTabsBelowSelection())
        #expect(runtime.state.currentWorkspace.tabs.map(\.title) == ["a", "b"])
        #expect(runtime.closeOtherTemporaryTabs())
        #expect(runtime.state.currentWorkspace.tabs.map(\.title) == ["b"])
        #expect(runtime.state.currentWorkspace.pins.map(\.id) == [pin])
        #expect(!runtime.closeOtherTemporaryTabs())
    }
}
