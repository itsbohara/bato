import Foundation
import Testing
import BatoCore
@testable import BatoRuntime

@MainActor
private final class DestroyingEngine: PageEngine {
    let launch: UUID
    var destroyAccepted = true
    var destroyed: [UUID] = []
    var supportedProfileIDs: Set<UUID> { [launch] }
    init(launch: UUID) { self.launch = launch }
    func supportsProfile(_ id: UUID) -> Bool { true }
    func create(_ page: LivePage, url: URL) -> Bool { true }
    func select(_ page: LivePage?) {}
    func requestClose(_ page: LivePage) {}
    var supportsPeek: Bool { false }
    func presentPeek(parent: LivePage, preview: LivePage, url: URL) -> Bool { false }
    func endPeek(restoreParent: Bool) -> PeekEndResult { .ended }
    func destroyProfile(_ id: UUID) -> Bool {
        if destroyAccepted { destroyed.append(id) }
        return destroyAccepted
    }
}

@MainActor
struct ProfileDeleteRuntimeTests {
    private func runtime(engine: DestroyingEngine? = nil) throws -> (PageRuntime, DestroyingEngine, UUID) {
        var state = BrowserState.initial()
        let engine = engine ?? DestroyingEngine(launch: state.currentWorkspace.profileID)
        let created = try state.createProfile(name: "Work", color: "#527FAD", workspaceName: "Office")
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        return (runtime, engine, created.profileID)
    }

    @Test func launchProfileCanNeverBeDeleted() throws {
        let (runtime, engine, _) = try runtime()
        let launch = try #require(runtime.state.launchProfileID)
        #expect(!runtime.deleteProfile(launch))
        #expect(engine.destroyed.isEmpty)
        #expect(runtime.state.profiles.count == 2)
    }

    @Test func deleteSavesWithSnapshotThenDestroysEngineData() throws {
        let (runtime, engine, work) = try runtime()
        var order: [String] = []
        runtime.snapshotCommit = { _ in order.append("snapshot") }
        #expect(runtime.deleteProfile(work))
        #expect(order == ["snapshot"])
        #expect(engine.destroyed == [work])
        #expect(!runtime.state.profiles.contains { $0.id == work })
        #expect(!runtime.state.workspaces.contains { $0.profileID == work })
    }

    @Test func deletingTheCurrentProfileMovesToTheLaunchProfile() throws {
        let (runtime, _, work) = try runtime()
        let office = try #require(runtime.state.workspaces.first { $0.profileID == work })
        #expect(runtime.activateWorkspace(office.id))
        #expect(runtime.deleteProfile(work))
        #expect(runtime.state.currentWorkspace.profileID == runtime.state.launchProfileID)
    }

    @Test func engineRefusalRestoresTheOrganization() throws {
        let (runtime, engine, work) = try runtime()
        engine.destroyAccepted = false
        let before = runtime.state
        #expect(!runtime.deleteProfile(work))
        #expect(runtime.state == before)
    }

    @Test func lossSummaryCountsWhatGoesAway() throws {
        var state = BrowserState.initial()
        let created = try state.createProfile(name: "Work", color: "#527FAD", workspaceName: "Office")
        let loss = try #require(state.lossOfDeleting(profile: created.profileID))
        #expect(loss.workspaces == 1 && loss.pages == 0 && loss.favorites == 0 && loss.archived == 0)
    }
}
