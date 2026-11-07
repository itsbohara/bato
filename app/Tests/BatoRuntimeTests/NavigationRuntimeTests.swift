import Foundation
import Testing
import BatoCore
@testable import BatoRuntime

@MainActor
private final class NavigationEngine: PageEngine {
    let supportedProfileIDs: Set<UUID>
    var supportsNavigation = true
    var supportsSplits = true
    var supportsPeek = true
    var acceptsCommands = true
    var commands: [(PageNavigationCommand, LivePage)] = []
    init(_ profileID: UUID) { supportedProfileIDs = [profileID] }
    func create(_ page: LivePage, url: URL) -> Bool { true }
    func select(_ page: LivePage?) {}
    func requestClose(_ page: LivePage) {}
    func presentSplit(left: LivePage, right: LivePage, focused: LivePage, ratio: Double) -> Bool { true }
    func presentPeek(parent: LivePage, preview: LivePage, url: URL) -> Bool { true }
    func endPeek(restoreParent: Bool) -> PeekEndResult { .ended }
    func perform(_ command: PageNavigationCommand, on page: LivePage) -> Bool {
        commands.append((command, page))
        return acceptsCommands
    }
}

@MainActor
struct NavigationRuntimeTests {
    private let first = URL(string: "https://example.invalid/first")!
    private let second = URL(string: "https://example.invalid/second")!

    private func make(started: Bool = true, entries: Int = 1) throws -> (PageRuntime, NavigationEngine) {
        var state = BrowserState.initial()
        for index in 0..<entries { _ = try state.addTab(url: index == 0 ? first : second, title: "Page \(index)") }
        let engine = NavigationEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        if started { #expect(runtime.start()) }
        return (runtime, engine)
    }

    private func active(_ runtime: PageRuntime) throws -> LivePage {
        let id = try #require(runtime.state.currentWorkspace.activeEntryID)
        return try #require(runtime.livePages[id])
    }

    @Test func unloadedEntriesAndUnsupportedEnginesAreDisabled() throws {
        let (unloaded, engine) = try make(started: false)
        #expect(unloaded.navigationTarget == nil)
        #expect(!unloaded.canPerform(.load(first)))
        #expect(!unloaded.perform(.load(first)))
        #expect(engine.commands.isEmpty)
        let (live, unsupported) = try make()
        unsupported.supportsNavigation = false
        #expect(live.navigationTarget == nil && !live.canPerform(.load(first)))
    }

    @Test func loadAcceptsOnlyCredentialFreeWebAddresses() throws {
        let (runtime, engine) = try make()
        #expect(runtime.perform(.load(second)))
        for text in ["javascript:alert(1)", "file:///etc/hosts", "https://user:pass@example.invalid/"] {
            #expect(!runtime.perform(.load(URL(string: text)!)))
        }
        #expect(engine.commands.count == 1)
    }

    @Test func capturedTargetIsRefusedAfterSelectionChanges() throws {
        let (runtime, engine) = try make(entries: 2)
        let newer = try active(runtime)
        let olderID = try #require(runtime.state.currentWorkspace.tabs.first { $0.id != newer.entryID }?.id)
        #expect(runtime.perform(.load(first), on: newer))
        #expect(runtime.selectEntry(olderID))
        let older = try active(runtime)
        #expect(!runtime.perform(.load(first), on: newer))
        #expect(runtime.perform(.load(first), on: older))
        #expect(engine.commands.map(\.1) == [newer, older])
    }

    @Test func rejectedEngineCommandReportsFailure() throws {
        let (runtime, engine) = try make()
        engine.acceptsCommands = false
        #expect(!runtime.perform(.load(second)))
        #expect(runtime.lastError == .invalidCommand)
    }

    @Test func peekDisablesCommandsUntilPromotionTargetsThePreview() throws {
        let (runtime, engine) = try make()
        #expect(runtime.openPeek(url: second))
        let preview = try #require(runtime.peekSession.preview).page
        #expect(runtime.navigationTarget == nil)
        #expect(!runtime.canPerform(.load(second)) && !runtime.perform(.load(second)))
        #expect(engine.commands.isEmpty)
        #expect(runtime.promotePeek())
        #expect(runtime.navigationTarget == preview)
        #expect(runtime.perform(.load(first)))
        #expect(engine.commands.last?.1 == preview)
    }

    @Test func splitCommandsFollowTheFocusedSide() throws {
        var state = BrowserState.initial()
        let left = try state.addTab(url: first, title: "Left")
        _ = try state.addTab(url: second, title: "Right")
        _ = try state.createSplit(with: left)
        let engine = NavigationEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: { _ in })
        #expect(runtime.start())
        let focused = try active(runtime)
        let other = try #require(runtime.livePages.values.first { $0 != focused })
        #expect(runtime.perform(.load(first)))
        runtime.receive(.selected(other))
        #expect(runtime.navigationTarget == other)
        #expect(runtime.perform(.load(second)))
        #expect(engine.commands.map(\.1) == [focused, other])
    }
}
