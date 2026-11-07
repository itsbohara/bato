import Foundation
import Testing
import BatoCore
@testable import BatoRuntime

@MainActor
private final class PeekEngine: PageEngine {
    let supportedProfileIDs: Set<UUID>
    var supportsPeek = true
    var acceptsPeek = true
    var endResult = PeekEndResult.ended
    var created: [LivePage] = []
    var presented: [(parent: LivePage, preview: LivePage, url: URL)] = []
    var ends: [Bool] = []
    var adopted: [LivePage] = []
    var closes: [LivePage] = []
    var selections: [LivePage?] = []
    init(_ profileID: UUID) { supportedProfileIDs = [profileID] }
    func create(_ page: LivePage, url: URL) -> Bool { created.append(page); return true }
    func select(_ page: LivePage?) { selections.append(page) }
    func requestClose(_ page: LivePage) { closes.append(page) }
    func presentPeek(parent: LivePage, preview: LivePage, url: URL) -> Bool {
        presented.append((parent, preview, url))
        return acceptsPeek
    }
    func endPeek(restoreParent: Bool) -> PeekEndResult { ends.append(restoreParent); return endResult }
    func adoptPeekPreview(_ preview: LivePage) { adopted.append(preview) }
}

@MainActor
struct PeekRuntimeTests {
    private let start = URL(string: "https://example.invalid/start")!
    private let target = URL(string: "https://example.invalid/target")!
    private enum Failure: Error { case disk }

    private func make(commit: @escaping (BrowserState) throws -> Void = { _ in }) throws -> (PageRuntime, PeekEngine, LivePage) {
        var state = BrowserState.initial()
        _ = try state.addTab(url: start, title: "Parent")
        let engine = PeekEngine(state.currentWorkspace.profileID)
        let runtime = try PageRuntime(state: state, engine: engine, commit: commit)
        #expect(runtime.start())
        return (runtime, engine, try #require(runtime.livePages.values.first))
    }

    @Test func openRequiresEligibleLinkLiveParentAndSingleSession() throws {
        let (runtime, engine, parent) = try make()
        let organization = runtime.state
        #expect(!runtime.openPeek(url: URL(string: "javascript:alert(1)")!))
        #expect(runtime.openPeek(url: target))
        let preview = try #require(runtime.peekSession.preview)
        #expect(engine.presented.count == 1)
        #expect(engine.presented[0].parent == parent)
        #expect(engine.presented[0].preview == preview.page)
        #expect(preview.page.entryID != parent.entryID)
        #expect(!runtime.openPeek(url: start))
        #expect(!runtime.canOpenPeek)
        #expect(engine.presented.count == 1)
        #expect(runtime.peekSession.preview == preview)
        #expect(runtime.state == organization)
        #expect(runtime.livePages.count == 1)
    }

    @Test func engineRefusalLeavesNoSession() throws {
        let (runtime, engine, _) = try make()
        engine.acceptsPeek = false
        #expect(!runtime.openPeek(url: target))
        #expect(runtime.peekSession.preview == nil)
        #expect(runtime.lastError == .creationRejected)
        engine.supportsPeek = false
        #expect(!runtime.openPeek(url: target))
        #expect(engine.presented.count == 1)
    }

    @Test func previewEventsNeverReachOrganization() throws {
        var saves = 0
        let (runtime, _, _) = try make(commit: { _ in saves += 1 })
        #expect(runtime.openPeek(url: target))
        let preview = try #require(runtime.peekSession.preview?.page)
        let organization = runtime.state
        let committed = saves
        let destination = URL(string: "https://example.invalid/redirected")!
        runtime.receive(.navigation(preview, url: destination, title: "Moved"))
        runtime.receive(.selected(preview))
        #expect(runtime.peekSession.preview?.url == destination)
        #expect(runtime.peekSession.preview?.title == "Moved")
        #expect(runtime.state == organization)
        #expect(saves == committed)
        let stale = LivePage(entryID: preview.entryID, profileID: preview.profileID)
        runtime.receive(.navigation(stale, url: start, title: "Stale"))
        runtime.receive(.closed(stale))
        #expect(runtime.peekSession.preview?.page == preview)
        #expect(runtime.peekSession.preview?.url == destination)
    }

    @Test func staleOrUnknownEndedEventsAreIgnored() throws {
        let (runtime, engine, _) = try make()
        #expect(runtime.openPeek(url: target))
        let preview = try #require(runtime.peekSession.preview?.page)
        runtime.receive(.peekEnded(preview: LivePage(entryID: preview.entryID, profileID: preview.profileID),
                                   reason: .selectionChanged))
        #expect(runtime.peekSession.preview?.page == preview)
        #expect(engine.closes.isEmpty)
    }

    @Test func engineEndedReasonsDecideWhetherPreviewIsClosed() throws {
        for reason in [PeekEndReason.previewClosed, .teardown, .closing] {
            let (runtime, engine, _) = try make()
            #expect(runtime.openPeek(url: target))
            let preview = try #require(runtime.peekSession.preview?.page)
            runtime.receive(.peekEnded(preview: preview, reason: reason))
            #expect(runtime.peekSession.preview == nil)
            #expect(engine.closes.isEmpty)
            #expect(engine.ends.isEmpty)
        }
        for reason in [PeekEndReason.selectionChanged, .fullscreen, .modal, .split, .parentClosed] {
            let (runtime, engine, parent) = try make()
            #expect(runtime.openPeek(url: target))
            let preview = try #require(runtime.peekSession.preview?.page)
            runtime.receive(.peekEnded(preview: preview, reason: reason))
            #expect(runtime.peekSession.preview == nil)
            #expect(engine.closes == [preview])
            #expect(engine.selections.last == parent)
            #expect(engine.ends.isEmpty)
            runtime.receive(.peekEnded(preview: preview, reason: reason))
            #expect(engine.closes == [preview])
        }
    }

    @Test func switchingWorkspaceEndsPeekWithoutRestoringParentAndClosesPreview() throws {
        let (runtime, engine, _) = try make()
        #expect(runtime.openPeek(url: target))
        let preview = try #require(runtime.peekSession.preview?.page)
        #expect(runtime.addWorkspace(name: "Other"))
        #expect(engine.ends == [false])
        #expect(engine.closes == [preview])
        #expect(runtime.peekSession.preview == nil)
        #expect(runtime.livePages[preview.entryID] == nil)
    }

    @Test func staleEndDuringTeardownDefersToEngineEndedEvent() throws {
        let (runtime, engine, _) = try make()
        engine.endResult = .stale
        #expect(runtime.openPeek(url: target))
        let preview = try #require(runtime.peekSession.preview?.page)
        #expect(runtime.addWorkspace(name: "Other"))
        #expect(engine.closes.isEmpty)
        #expect(runtime.peekSession.preview?.page == preview)
        runtime.receive(.peekEnded(preview: preview, reason: .selectionChanged))
        #expect(runtime.peekSession.preview == nil)
        #expect(engine.closes == [preview])
    }

    @Test func dismissalStaysPendingUntilEngineConfirmsClosure() throws {
        let (runtime, engine, _) = try make()
        #expect(runtime.openPeek(url: target))
        let preview = try #require(runtime.peekSession.preview?.page)
        #expect(runtime.dismissPeek())
        #expect(engine.closes == [preview])
        #expect(runtime.peekSession.preview?.isPendingDismissal == true)
        #expect(!runtime.dismissPeek())
        #expect(!runtime.promotePeek())
        #expect(engine.closes == [preview])
        runtime.receive(.closeCancelled(preview))
        #expect(runtime.peekSession.preview?.isPendingDismissal == false)
        #expect(runtime.dismissPeek())
        #expect(engine.closes == [preview, preview])
        runtime.receive(.closed(preview))
        #expect(runtime.peekSession.preview == nil)
        runtime.receive(.peekEnded(preview: preview, reason: .previewClosed))
        #expect(engine.closes == [preview, preview])
        #expect(runtime.canOpenPeek)
    }

    @Test func promotionKeepsExactIdentityWithoutCreatingOrNavigating() throws {
        var saved: [BrowserState] = []
        let (runtime, engine, parent) = try make(commit: { saved.append($0) })
        #expect(runtime.openPeek(url: target))
        let preview = try #require(runtime.peekSession.preview?.page)
        let destination = URL(string: "https://example.invalid/final")!
        runtime.receive(.navigation(preview, url: destination, title: "Final"))
        let created = engine.created
        let saves = saved.count
        #expect(runtime.promotePeek())
        #expect(runtime.peekSession.preview == nil)
        #expect(saved.count == saves + 1)
        let entry = try #require(runtime.state.currentWorkspace.tabs.first { $0.id == preview.entryID })
        #expect(entry.lastURL == destination)
        #expect(entry.title == "Final")
        #expect(runtime.state.currentWorkspace.activeEntryID == preview.entryID)
        #expect(runtime.livePages[preview.entryID] == preview)
        #expect(runtime.livePages[parent.entryID] == parent)
        #expect(engine.adopted == [preview])
        #expect(engine.ends == [false])
        #expect(engine.created == created)
        #expect(engine.closes.isEmpty)
        runtime.receive(.navigation(preview, url: start, title: "Ordinary"))
        #expect(runtime.state.currentWorkspace.tabs.first { $0.id == preview.entryID }?.lastURL == start)
    }

    @Test func staleEndAfterPromotionResynchronizesEngineSelection() throws {
        let (runtime, engine, _) = try make()
        engine.endResult = .stale
        #expect(runtime.openPeek(url: target))
        let preview = try #require(runtime.peekSession.preview?.page)
        #expect(runtime.promotePeek())
        #expect(engine.selections.last == preview)
    }

    @Test func failedPromotionSaveKeepsPreviewOwnedAndUsable() throws {
        var diskFull = false
        let (runtime, engine, _) = try make(commit: { _ in if diskFull { throw Failure.disk } })
        #expect(runtime.openPeek(url: target))
        diskFull = true
        let before = runtime.peekSession.preview
        let organization = runtime.state
        let live = runtime.livePages
        #expect(!runtime.promotePeek())
        #expect(runtime.lastError == .saveFailed)
        #expect(runtime.peekSession.preview == before)
        #expect(runtime.state == organization)
        #expect(runtime.livePages == live)
        #expect(engine.adopted.isEmpty)
        #expect(engine.ends.isEmpty)
        #expect(runtime.dismissPeek())
    }

    @Test func promotionRefusesWhenParentIsNoLongerSelected() throws {
        let (runtime, engine, _) = try make()
        #expect(runtime.openPeek(url: target))
        let preview = try #require(runtime.peekSession.preview?.page)
        runtime.receive(.peekEnded(preview: preview, reason: .previewClosed))
        #expect(!runtime.promotePeek())
        #expect(engine.adopted.isEmpty)
    }

    @Test func rejectedCleanupIsRetriedUntilTheEngineConfirmsClosure() throws {
        let (runtime, engine, parent) = try make()
        #expect(runtime.openPeek(url: target))
        let preview = try #require(runtime.peekSession.preview?.page)
        runtime.receive(.peekEnded(preview: preview, reason: .modal))
        #expect(engine.closes == [preview])
        runtime.receive(.closeCancelled(preview))
        runtime.retryAbandonedPreviews()
        #expect(engine.closes == [preview, preview])
        #expect(engine.selections.suffix(2) == [parent, parent])
        runtime.receive(.closed(preview))
        runtime.retryAbandonedPreviews()
        #expect(engine.closes == [preview, preview])
    }

    @Test func endingPeekRestoresParentAndClosesPreviewBeforeASheet() throws {
        let (runtime, engine, parent) = try make()
        runtime.endPeek()
        #expect(engine.ends.isEmpty)
        #expect(runtime.openPeek(url: target))
        let preview = try #require(runtime.peekSession.preview?.page)
        runtime.endPeek()
        #expect(engine.ends == [true])
        #expect(engine.closes == [preview])
        #expect(engine.selections.last == parent)
        #expect(runtime.peekSession.preview == nil)
        #expect(runtime.canOpenPeek)
    }

    @Test func staleEndBeforeASheetLeavesCleanupToTheEngineEvent() throws {
        let (runtime, engine, _) = try make()
        engine.endResult = .stale
        #expect(runtime.openPeek(url: target))
        let preview = try #require(runtime.peekSession.preview?.page)
        runtime.endPeek()
        #expect(engine.closes.isEmpty)
        runtime.receive(.peekEnded(preview: preview, reason: .modal))
        #expect(engine.closes == [preview])
    }

    @Test func scrimClickDismissesThroughBeforeUnloadAndIgnoresStalePreview() throws {
        let (runtime, engine, _) = try make()
        #expect(runtime.openPeek(url: target))
        let first = try #require(runtime.peekSession.preview?.page)
        runtime.receive(.closed(first))
        runtime.receive(.peekEnded(preview: first, reason: .previewClosed))
        #expect(runtime.openPeek(url: target))
        let second = try #require(runtime.peekSession.preview?.page)
        #expect(!runtime.dismissPeek(preview: first))
        #expect(engine.closes.isEmpty)
        #expect(runtime.peekSession.preview?.isPendingDismissal == false)
        #expect(runtime.dismissPeek(preview: second))
        #expect(engine.closes == [second])
        #expect(runtime.peekSession.preview?.isPendingDismissal == true)
        #expect(!runtime.dismissPeek(preview: second))
        runtime.receive(.closeCancelled(second))
        #expect(runtime.peekSession.preview?.page == second)
    }

    @Test func linkEligibilityRequiresLiveActiveParentWithoutPeekAndEligibleURL() throws {
        let (runtime, engine, parent) = try make()
        let organization = runtime.state
        #expect(runtime.canOpenPeek(from: parent, url: target))
        #expect(!runtime.canOpenPeek(from: parent, url: URL(string: "javascript:alert(1)")!))
        #expect(!runtime.canOpenPeek(from: parent, url: URL(string: "https://user:secret@example.invalid/")!))
        #expect(!runtime.canOpenPeek(from: LivePage(entryID: UUID(), profileID: parent.profileID), url: target))
        #expect(!runtime.canOpenPeek(from: LivePage(entryID: parent.entryID, profileID: parent.profileID), url: target))
        engine.supportsPeek = false
        #expect(!runtime.canOpenPeek(from: parent, url: target))
        engine.supportsPeek = true
        #expect(runtime.state == organization)
        #expect(engine.presented.isEmpty)
        #expect(runtime.openPeek(url: target))
        #expect(!runtime.canOpenPeek(from: parent, url: target))
    }

    @Test func linkEligibilityRejectsParentFromAnotherWorkspace() throws {
        let (runtime, _, parent) = try make()
        #expect(runtime.addWorkspace(name: "Other"))
        #expect(!runtime.canOpenPeek(from: parent, url: target))
    }

    @Test func linkRequestOpensPeekForParentAndRevalidates() throws {
        let (runtime, engine, parent) = try make()
        #expect(runtime.openPeek(from: parent, url: target))
        #expect(engine.presented.count == 1)
        #expect(engine.presented[0].parent == parent)
        #expect(engine.presented[0].url == target)
        #expect(runtime.peekSession.preview?.url == target)
        #expect(!runtime.openPeek(from: parent, url: start))
        #expect(engine.presented.count == 1)
        let preview = try #require(runtime.peekSession.preview?.page)
        runtime.receive(.closed(preview))
        runtime.receive(.peekEnded(preview: preview, reason: .previewClosed))
        #expect(runtime.addWorkspace(name: "Other"))
        #expect(!runtime.openPeek(from: parent, url: target))
        #expect(engine.presented.count == 1)
        #expect(runtime.peekSession.preview == nil)
    }

    @Test func secondPeekIsRefusedWithADistinctError() throws {
        let (runtime, engine, parent) = try make()
        #expect(runtime.openPeek(url: target))
        #expect(!runtime.openPeek(from: parent, url: start))
        #expect(runtime.lastError == .peekAlreadyOpen)
        #expect(!runtime.openPeek(url: start))
        #expect(runtime.lastError == .peekAlreadyOpen)
        #expect(engine.presented.count == 1)
    }
}
