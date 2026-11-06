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

    @Test func stateEventsDriveCommandAvailability() throws {
        let (runtime, engine) = try make()
        let page = try active(runtime)
        #expect(runtime.navigationState == PageNavigationState())
        #expect(!runtime.canPerform(.back) && !runtime.canPerform(.forward) && !runtime.canPerform(.stop))
        #expect(runtime.canPerform(.reload))
        runtime.receive(.navigationState(page, PageNavigationState(canGoBack: true, isLoading: true)))
        #expect(runtime.canPerform(.back) && !runtime.canPerform(.forward))
        #expect(runtime.canPerform(.stop) && !runtime.canPerform(.reload))
        #expect(runtime.perform(.back))
        #expect(runtime.perform(.stop))
        #expect(!runtime.perform(.reload))
        #expect(engine.commands.map(\.0) == [.back, .stop])
        #expect(engine.commands.allSatisfy { $0.1 == page })
    }

    @Test func failureCodeIsReportedUntilTheNextStateReplacesIt() throws {
        let (runtime, _) = try make()
        let page = try active(runtime)
        runtime.receive(.navigationState(page, PageNavigationState(failureCode: -105)))
        #expect(runtime.navigationState?.failureCode == -105)
        runtime.receive(.navigationState(page, PageNavigationState(isLoading: true)))
        #expect(runtime.navigationState?.failureCode == nil)
    }

    @Test func failureAndAttemptedDestinationSurviveTheErrorPagesLoadingCycle() throws {
        let (runtime, _) = try make()
        let page = try active(runtime)
        #expect(runtime.displayedURL == first)
        runtime.receive(.navigationState(page, PageNavigationState(isLoading: true, attemptedURL: second)))
        #expect(runtime.displayedURL == second)
        let failed = PageNavigationState(failureCode: -102, attemptedURL: second)
        runtime.receive(.navigationState(page, failed))
        for loading in [true, false] {
            var cycle = failed
            cycle.isLoading = loading
            runtime.receive(.navigationState(page, cycle))
            #expect(runtime.navigationState?.failureCode == -102)
            #expect(runtime.displayedURL == second)
        }
        runtime.receive(.navigationState(page, PageNavigationState(isLoading: true, attemptedURL: first)))
        #expect(runtime.navigationState?.failureCode == nil)
        runtime.receive(.navigationState(page, PageNavigationState()))
        #expect(runtime.displayedURL == first)
    }

    @Test func displayedURLFallsBackToTheEntryWhenUnloadedAndFollowsThePeekParent() throws {
        let (unloaded, _) = try make(started: false)
        #expect(unloaded.displayedURL == first)
        let (runtime, _) = try make()
        let parent = try active(runtime)
        runtime.receive(.navigationState(parent, PageNavigationState(isLoading: true, attemptedURL: second)))
        #expect(runtime.openPeek(url: second))
        #expect(runtime.displayedURL == second)
        #expect(runtime.navigationTarget == nil)
    }

    @Test func staleGenerationAndTerminalEventsNeverReachState() throws {
        let (runtime, _) = try make()
        let page = try active(runtime)
        let stale = LivePage(entryID: page.entryID, profileID: page.profileID)
        runtime.receive(.navigationState(stale, PageNavigationState(canGoBack: true)))
        #expect(runtime.navigationStates[stale] == nil)
        #expect(!runtime.canPerform(.back))
        runtime.receive(.navigationState(page, PageNavigationState(canGoBack: true)))
        runtime.receive(.unloaded(page))
        #expect(runtime.navigationStates.isEmpty)
        runtime.receive(.navigationState(page, PageNavigationState(canGoBack: true)))
        #expect(runtime.navigationStates.isEmpty)
    }

    @Test func unloadedEntriesAndUnsupportedEnginesAreDisabled() throws {
        let (unloaded, engine) = try make(started: false)
        #expect(unloaded.navigationTarget == nil && unloaded.navigationState == nil)
        for command in [PageNavigationCommand.back, .forward, .reload, .stop, .load(first)] {
            #expect(!unloaded.canPerform(command))
            #expect(!unloaded.perform(command))
        }
        #expect(engine.commands.isEmpty)
        let (live, unsupported) = try make()
        unsupported.supportsNavigation = false
        #expect(live.navigationTarget == nil && !live.canPerform(.reload))
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
        #expect(runtime.perform(.reload, on: newer))
        #expect(runtime.selectEntry(olderID))
        let older = try active(runtime)
        #expect(!runtime.perform(.reload, on: newer))
        #expect(runtime.perform(.reload, on: older))
        #expect(engine.commands.map(\.1) == [newer, older])
    }

    @Test func rejectedEngineCommandReportsFailure() throws {
        let (runtime, engine) = try make()
        engine.acceptsCommands = false
        #expect(!runtime.perform(.reload))
        #expect(runtime.lastError == .invalidCommand)
    }

    @Test func peekDisablesCommandsWhileHeaderKeepsReflectingTheParent() throws {
        let (runtime, engine) = try make()
        let parent = try active(runtime)
        runtime.receive(.navigationState(parent, PageNavigationState(canGoBack: true, failureCode: -2)))
        #expect(runtime.openPeek(url: second))
        let preview = try #require(runtime.peekSession.preview).page
        runtime.receive(.navigationState(preview, PageNavigationState(canGoForward: true)))
        #expect(runtime.navigationTarget == nil)
        #expect(runtime.navigationState?.canGoBack == true && runtime.navigationState?.failureCode == -2)
        #expect(!runtime.canPerform(.back) && !runtime.canPerform(.reload) && !runtime.canPerform(.load(second)))
        #expect(!runtime.perform(.back))
        #expect(engine.commands.isEmpty)
        #expect(runtime.promotePeek())
        #expect(runtime.navigationTarget == preview)
        #expect(runtime.navigationState?.canGoForward == true)
        #expect(runtime.perform(.forward))
        #expect(engine.commands.last?.1 == preview)
    }

    @Test func closedPreviewStateIsDropped() throws {
        let (runtime, _) = try make()
        #expect(runtime.openPeek(url: second))
        let preview = try #require(runtime.peekSession.preview).page
        runtime.receive(.navigationState(preview, PageNavigationState(isLoading: true)))
        #expect(runtime.navigationStates[preview] != nil)
        runtime.receive(.closed(preview))
        #expect(runtime.navigationStates[preview] == nil)
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
        runtime.receive(.navigationState(focused, PageNavigationState(canGoBack: true)))
        runtime.receive(.navigationState(other, PageNavigationState(canGoForward: true)))
        #expect(runtime.canPerform(.back) && !runtime.canPerform(.forward))
        #expect(runtime.perform(.back))
        runtime.receive(.selected(other))
        #expect(runtime.navigationTarget == other)
        #expect(!runtime.canPerform(.back) && runtime.canPerform(.forward))
        #expect(runtime.perform(.forward))
        #expect(engine.commands.map(\.1) == [focused, other])
    }
}
