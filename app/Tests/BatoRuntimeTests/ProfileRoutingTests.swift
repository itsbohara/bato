import Foundation
import Testing
import BatoCore
@testable import BatoRuntime

/// Binds Profiles on demand, like the host engine opening one context per Profile.
@MainActor
private final class ContextEngine: PageEngine {
    var supportedProfileIDs: Set<UUID>
    var activated: [UUID] = []
    var created: [(LivePage, URL)] = []
    var selections: [LivePage?] = []
    var splits: [(LivePage, LivePage)] = []
    var peeks: [(parent: LivePage, preview: LivePage)] = []
    var supportsSplits: Bool { true }
    var supportsPeek: Bool { true }
    init(_ profiles: Set<UUID>) { supportedProfileIDs = profiles }
    func activateProfile(_ id: UUID) { activated.append(id) }
    func create(_ page: LivePage, url: URL) -> Bool {
        guard supportsProfile(page.profileID) else { return false }
        created.append((page, url))
        return true
    }
    func select(_ page: LivePage?) { selections.append(page) }
    func requestClose(_ page: LivePage) {}
    func presentSplit(left: LivePage, right: LivePage, focused: LivePage, ratio: Double,
                      orientation: SplitOrientation) -> Bool {
        guard left.profileID == right.profileID, supportsProfile(left.profileID) else { return false }
        splits.append((left, right))
        return true
    }
    func presentPeek(parent: LivePage, preview: LivePage, url: URL) -> Bool {
        guard parent.profileID == preview.profileID, supportsProfile(preview.profileID) else { return false }
        peeks.append((parent, preview))
        return true
    }
    func endPeek(restoreParent: Bool) -> PeekEndResult { .ended }
}

@MainActor
struct ProfileRoutingTests {
    private let page = URL(string: "https://example.invalid/page")!

    private struct Fixture {
        var state = BrowserState.initial()
        var firstWorkspace: UUID
        var firstProfile: UUID
        var secondWorkspace: UUID
        var secondProfile: UUID
        var firstEntry: UUID
        var secondEntry: UUID
    }

    private func fixture() throws -> Fixture {
        var state = BrowserState.initial()
        let firstWorkspace = state.activeWorkspaceID
        let firstProfile = state.currentWorkspace.profileID
        let firstEntry = try state.addTab(url: page, title: "First")
        let secondProfile = try state.addProfile(name: "Second")
        let secondWorkspace = try state.addWorkspace(name: "Second space", profileID: secondProfile)
        try state.activateWorkspace(secondWorkspace)
        let secondEntry = try state.addTab(url: page, title: "Second")
        try state.activateWorkspace(firstWorkspace)
        return Fixture(state: state, firstWorkspace: firstWorkspace, firstProfile: firstProfile,
                       secondWorkspace: secondWorkspace, secondProfile: secondProfile,
                       firstEntry: firstEntry, secondEntry: secondEntry)
    }

    @Test func pagesAreCreatedForTheirWorkspaceProfileAndReusedOnReturn() throws {
        let f = try fixture()
        let engine = ContextEngine([f.firstProfile, f.secondProfile])
        let runtime = try PageRuntime(state: f.state, engine: engine, commit: { _ in })
        #expect(runtime.start())
        #expect(runtime.activateWorkspace(f.secondWorkspace))
        #expect(runtime.activateEntry(f.secondEntry, inWorkspace: f.secondWorkspace))
        #expect(engine.created.map(\.0.profileID) == [f.firstProfile, f.secondProfile])
        #expect(engine.created.map(\.0.entryID) == [f.firstEntry, f.secondEntry])
        #expect(engine.activated == [f.firstProfile, f.secondProfile, f.secondProfile])
        #expect(runtime.activateWorkspace(f.firstWorkspace))
        #expect(engine.created.count == 2)
        #expect(engine.selections.last == runtime.livePages[f.firstEntry])
        #expect(runtime.livePages[f.firstEntry]?.profileID == f.firstProfile)
        #expect(runtime.livePages[f.secondEntry]?.profileID == f.secondProfile)
    }

    @Test func unsupportedProfileBecomesSupportedWithoutRestartingTheRuntime() throws {
        let f = try fixture()
        let engine = ContextEngine([f.firstProfile])
        var commits = 0
        let runtime = try PageRuntime(state: f.state, engine: engine, commit: { _ in commits += 1 })
        #expect(runtime.start())
        let before = runtime.state
        let saves = commits
        #expect(!runtime.activateWorkspace(f.secondWorkspace))
        #expect(runtime.lastError == .unsupportedProfile)
        #expect(runtime.state == before)
        #expect(commits == saves)
        #expect(engine.created.count == 1)
        engine.supportedProfileIDs.insert(f.secondProfile)
        #expect(runtime.activateWorkspace(f.secondWorkspace))
        #expect(runtime.lastError == nil)
        #expect(runtime.state.currentWorkspace.profileID == f.secondProfile)
        #expect(engine.created.last?.0.profileID == f.secondProfile)
        engine.supportedProfileIDs.remove(f.secondProfile)
        #expect(runtime.activateWorkspace(f.firstWorkspace))
        #expect(!runtime.activateWorkspace(f.secondWorkspace))
        #expect(runtime.lastError == .unsupportedProfile)
    }

    @Test func launchWithUnsupportedProfileThrows() throws {
        let f = try fixture()
        #expect(throws: PageRuntimeError.unsupportedProfile) {
            _ = try PageRuntime(state: f.state, engine: ContextEngine([f.secondProfile]), commit: { _ in })
        }
    }

    @Test func splitsNeverPairAnEntryFromAnotherProfile() throws {
        let f = try fixture()
        let engine = ContextEngine([f.firstProfile, f.secondProfile])
        let runtime = try PageRuntime(state: f.state, engine: engine, commit: { _ in })
        #expect(runtime.start())
        #expect(!runtime.createSplit(with: f.secondEntry))
        #expect(runtime.lastError == .invalidCommand)
        #expect(runtime.state.currentSplit == nil)
        #expect(engine.splits.isEmpty)
        #expect(!runtime.moveEntry(f.firstEntry, toWorkspace: f.secondWorkspace))
        #expect(runtime.state.workspaces.first { $0.id == f.firstWorkspace }?.tabs.map(\.id) == [f.firstEntry])
    }

    @Test func splitInsideASecondProfileUsesOnlyThatProfile() throws {
        var f = try fixture()
        try f.state.activateWorkspace(f.secondWorkspace)
        let partner = try f.state.addTab(url: page, title: "Partner")
        let engine = ContextEngine([f.firstProfile, f.secondProfile])
        let runtime = try PageRuntime(state: f.state, engine: engine, commit: { _ in })
        #expect(runtime.start())
        #expect(runtime.createSplit(with: f.secondEntry))
        let pair = try #require(engine.splits.last)
        #expect(pair.0.profileID == f.secondProfile && pair.1.profileID == f.secondProfile)
        #expect(Set([pair.0.entryID, pair.1.entryID]) == [f.secondEntry, partner])
    }

    @Test func peekStaysInTheParentProfile() throws {
        var f = try fixture()
        try f.state.activateWorkspace(f.secondWorkspace)
        try f.state.selectEntry(f.secondEntry)
        let engine = ContextEngine([f.firstProfile, f.secondProfile])
        let runtime = try PageRuntime(state: f.state, engine: engine, commit: { _ in })
        #expect(runtime.start())
        #expect(runtime.openPeek(url: URL(string: "https://example.invalid/peek")!))
        let presented = try #require(engine.peeks.last)
        #expect(presented.parent.profileID == f.secondProfile)
        #expect(presented.preview.profileID == f.secondProfile)
        #expect(presented.parent.entryID == f.secondEntry)
        #expect(!engine.peeks.contains { $0.preview.profileID == f.firstProfile })
    }
}

@MainActor
struct LaunchProfileTests {
    private let page = URL(string: "https://example.invalid/page")!

    @Test func launchProfileIsTheFirstProfileWhateverIsSelected() throws {
        var state = BrowserState.initial()
        let launch = try #require(state.profiles.first?.id)
        let second = try state.addProfile(name: "Second")
        let space = try state.addWorkspace(name: "Second space", profileID: second)
        #expect(state.launchProfileID == launch)
        try state.activateWorkspace(space)
        #expect(state.currentWorkspace.profileID == second)
        #expect(state.launchProfileID == launch)
        _ = try state.addProfile(name: "Third")
        #expect(state.launchProfileID == launch)
    }

    @Test func startingOnAnotherProfileCreatesItsPageInThatProfileAndLaunchPagesLater() throws {
        var state = BrowserState.initial()
        let launchWorkspace = state.activeWorkspaceID
        let launch = try #require(state.launchProfileID)
        _ = try state.addTab(url: page, title: "Launch page")
        let second = try state.addProfile(name: "Second")
        let space = try state.addWorkspace(name: "Second space", profileID: second)
        try state.activateWorkspace(space)
        _ = try state.addTab(url: page, title: "Second page")
        let engine = StartupEngine(launch: launch, lazy: [second])
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        #expect(runtime.start())
        #expect(engine.created.map(\.profileID) == [second])
        #expect(runtime.activateWorkspace(launchWorkspace))
        #expect(engine.created.map(\.profileID) == [second, launch])
        #expect(engine.activated == [second, launch])
    }
}

@MainActor
private final class StartupEngine: PageEngine {
    let launch: UUID
    let lazy: Set<UUID>
    var created: [LivePage] = []
    var activated: [UUID] = []
    var supportedProfileIDs: Set<UUID> { [launch] }
    init(launch: UUID, lazy: Set<UUID>) { self.launch = launch; self.lazy = lazy }
    func supportsProfile(_ id: UUID) -> Bool { id == launch || lazy.contains(id) }
    func activateProfile(_ id: UUID) { activated.append(id) }
    func create(_ page: LivePage, url: URL) -> Bool { created.append(page); return true }
    func select(_ page: LivePage?) {}
    func requestClose(_ page: LivePage) {}
}
