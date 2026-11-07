import Foundation
import Testing
import BatoCore
@testable import BatoRuntime

@MainActor
private final class RecordingEngine: PageEngine {
    var supportedProfileIDs: Set<UUID>
    var closed: [LivePage] = []
    init(_ profileID: UUID) { supportedProfileIDs = [profileID] }
    func create(_ page: LivePage, url: URL) -> Bool { true }
    func select(_ page: LivePage?) {}
    func requestClose(_ page: LivePage) { closed.append(page) }
}

@MainActor
struct WorkspaceDeleteRuntimeTests {
    private func url(_ name: String) -> URL { URL(string: "https://example.invalid/\(name)")! }

    private func runtime(commit: @escaping (BrowserState) throws -> Void = { _ in }) throws
        -> (PageRuntime, RecordingEngine, first: UUID, second: UUID) {
        var state = BrowserState.initial()
        let first = state.activeWorkspaceID
        let second = try state.addWorkspace(name: "Second", profileID: state.profiles[0].id)
        let engine = RecordingEngine(state.profiles[0].id)
        return (try PageRuntime(state: state, engine: engine, commit: commit), engine, first, second)
    }

    @Test func refusesTheOnlyWorkspaceOfAProfile() throws {
        let (runtime, _, first, second) = try runtime()
        #expect(runtime.deleteWorkspace(second))
        let before = runtime.state
        #expect(!runtime.deleteWorkspace(first))
        #expect(runtime.state == before)
    }

    @Test func snapshotIsTakenBeforeTheOrganizationChanges() throws {
        var order: [String] = []
        let (runtime, _, _, second) = try runtime(commit: { _ in order.append("plain") })
        runtime.snapshotCommit = { state in
            order.append("snapshot:\(state.workspaces.count)")
        }
        #expect(runtime.deleteWorkspace(second))
        #expect(order == ["snapshot:1"])
    }

    @Test func failedSnapshotLeavesTheWorkspaceInPlace() throws {
        struct Failure: Error {}
        let (runtime, _, _, second) = try runtime()
        runtime.snapshotCommit = { _ in throw Failure() }
        #expect(!runtime.deleteWorkspace(second))
        #expect(runtime.lastError == .saveFailed)
        #expect(runtime.state.workspaces.contains { $0.id == second })
    }

    @Test func closesLivePagesOfTheDeletedWorkspaceAndSelectsASibling() throws {
        let (runtime, engine, first, second) = try runtime()
        #expect(runtime.activateWorkspace(second))
        #expect(runtime.addTab(url: url("a"), title: "A"))
        let tab = try #require(runtime.state.currentWorkspace.activeEntryID)
        let page = try #require(runtime.livePages[tab])
        #expect(runtime.deleteWorkspace(second))
        #expect(engine.closed == [page])
        #expect(runtime.livePages[tab] == nil)
        #expect(runtime.state.activeWorkspaceID == first)
        runtime.receive(.closed(page))
        #expect(runtime.state.workspaces.map(\.id) == [first])
    }
}
