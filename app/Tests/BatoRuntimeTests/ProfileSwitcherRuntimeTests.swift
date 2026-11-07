import Foundation
import Testing
import BatoCore
@testable import BatoRuntime

/// Opens any Profile on demand when `bindsOnDemand`, like the host opening a window per Profile.
@MainActor
private final class OnDemandEngine: PageEngine {
    let launch: UUID
    var bindsOnDemand = true
    var activated: [UUID] = []
    var created: [LivePage] = []
    var selections = 0
    var supportedProfileIDs: Set<UUID> { [launch] }
    init(launch: UUID) { self.launch = launch }
    func supportsProfile(_ id: UUID) -> Bool { bindsOnDemand || id == launch }
    func activateProfile(_ id: UUID) { activated.append(id) }
    func create(_ page: LivePage, url: URL) -> Bool { created.append(page); return true }
    func select(_ page: LivePage?) { selections += 1 }
    func requestClose(_ page: LivePage) {}
    var supportsPeek: Bool { false }
    func presentPeek(parent: LivePage, preview: LivePage, url: URL) -> Bool { false }
    func endPeek(restoreParent: Bool) -> PeekEndResult { .ended }
}

@MainActor
struct ProfileSwitcherRuntimeTests {
    private let page = URL(string: "https://example.invalid/page")!

    @Test func createProfileIsRefusedAndNotSavedWhenTheEngineCannotOpenIt() throws {
        let state = BrowserState.initial()
        let engine = OnDemandEngine(launch: state.currentWorkspace.profileID)
        engine.bindsOnDemand = false
        var commits = 0
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in commits += 1 })
        #expect(!runtime.createProfile(name: "Work", color: "#527FAD", workspaceName: "Office"))
        #expect(runtime.state == state)
        #expect(commits == 0)
        #expect(runtime.lastError == .unsupportedProfile)
    }

    @Test func createProfileSavesOnceEntersItsWorkspaceAndRoutesItsFirstPage() throws {
        let state = BrowserState.initial()
        let engine = OnDemandEngine(launch: state.currentWorkspace.profileID)
        var commits = 0
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in commits += 1 })
        #expect(runtime.createProfile(name: "Work", color: "#527FAD", workspaceName: "Office"))
        #expect(commits == 1)
        let created = runtime.state.currentWorkspace
        #expect(created.name == "Office")
        #expect(created.profileID != state.currentWorkspace.profileID)
        #expect(engine.activated.last == created.profileID)
        #expect(runtime.addTab(url: page, title: "First"))
        #expect(engine.created.last?.profileID == created.profileID)
    }

    @Test func createProfileCanDeferEngineWorkUntilTheSheetHasClosed() throws {
        let state = BrowserState.initial()
        let engine = OnDemandEngine(launch: state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        let activations = engine.activated.count
        #expect(runtime.createProfile(name: "Work", color: "#527FAD", workspaceName: "Office", deferPageSelection: true))
        #expect(engine.activated.count == activations)
        #expect(runtime.start())
        #expect(engine.activated.last == runtime.state.currentWorkspace.profileID)
    }

    @Test func updateProfileKeepsSelectionAndSavesOnce() throws {
        let state = BrowserState.initial()
        let profile = state.currentWorkspace.profileID
        let engine = OnDemandEngine(launch: profile)
        var commits = 0
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in commits += 1 })
        let selections = engine.selections
        #expect(runtime.updateProfile(profile, name: "Home", color: "#6D8B70"))
        #expect(runtime.state.profiles[0].name == "Home")
        #expect(runtime.state.activeWorkspaceID == state.activeWorkspaceID)
        #expect(engine.selections == selections)
        #expect(commits == 1)
        #expect(!runtime.updateProfile(profile, name: " ", color: "#6D8B70"))
        #expect(commits == 1)
    }
}
