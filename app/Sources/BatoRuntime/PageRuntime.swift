import Foundation
import BatoCore

/// Process-local identity. A fresh generation is required every time an entry is loaded.
public struct LivePage: Hashable, Sendable {
    public let entryID: UUID
    public let profileID: UUID
    public let generation: UUID

    public init(entryID: UUID, profileID: UUID, generation: UUID = UUID()) {
        self.entryID = entryID
        self.profileID = profileID
        self.generation = generation
    }
}

public enum PageNavigationCommand: Equatable, Sendable {
    case load(URL)
}

public enum PageEvent: Sendable {
    case navigation(LivePage, url: URL, title: String)
    case closed(LivePage)
    case closeCancelled(LivePage)
    case creationFailed(LivePage)
    /// Unsolicited window/application teardown unloads a page without deleting
    /// the saved session entry. Explicit page close uses `closed` instead.
    case unloaded(LivePage)
    case selected(LivePage)
    case selectionCleared
    case splitRatioChanged(left: LivePage, right: LivePage, ratio: Double)
    case splitSeparated(left: LivePage, right: LivePage)
    /// The engine ended the presentation itself; the preview page may still be live.
    case peekEnded(preview: LivePage, reason: PeekEndReason)
}

public enum PeekEndReason: Int32, Sendable {
    case previewClosed = 1, selectionChanged, fullscreen, modal, split, teardown, parentClosed, closing
}

public enum PeekEndResult: Sendable {
    case stale, ended, parentRestoreFailed
}

/// All calls and events use the main actor. Acceptance of create means the adapter
/// owns this token until a terminal event, including while creation is pending.
/// The adapter reports failed creation as creationFailed, not closed.
@MainActor
public protocol PageEngine: AnyObject {
    var supportedProfileIDs: Set<UUID> { get }
    /// Whether pages of this Profile can be opened now. An engine that creates contexts lazily
    /// answers true for a Profile it has not bound yet; the runtime asks again on every change.
    func supportsProfile(_ id: UUID) -> Bool
    /// The Profile of the selection about to be shown, so a nil selection hides the right context.
    func activateProfile(_ id: UUID)
    var supportsSplits: Bool { get }
    func presentSplit(left: LivePage, right: LivePage, focused: LivePage, ratio: Double) -> Bool
    func separateSplit() -> Bool
    func create(_ page: LivePage, url: URL) -> Bool
    /// nil hides any previously visible page. A token whose creation is pending
    /// shows blank/loading content until ready, never a previously selected page.
    func select(_ page: LivePage?)
    func requestClose(_ page: LivePage)
    var supportsPeek: Bool { get }
    /// Creates the preview page and presents it in one step, so it is never
    /// shown as an ordinary active tab. The engine owns the page until a terminal event.
    func presentPeek(parent: LivePage, preview: LivePage, url: URL) -> Bool
    /// Ends the current presentation. Without a parent restore the preview stays an ordinary active page.
    func endPeek(restoreParent: Bool) -> PeekEndResult
    /// Routes the preview's later events as an ordinary page's.
    func adoptPeekPreview(_ preview: LivePage)
    var supportsNavigation: Bool { get }
    /// Acts only on a page that is currently visible and focused; the engine refuses anything else.
    func perform(_ command: PageNavigationCommand, on page: LivePage) -> Bool
}

public extension PageEngine {
    func supportsProfile(_ id: UUID) -> Bool { supportedProfileIDs.contains(id) }
    func activateProfile(_ id: UUID) {}
    var supportsSplits: Bool { false }
    func presentSplit(left: LivePage, right: LivePage, focused: LivePage, ratio: Double) -> Bool { false }
    func separateSplit() -> Bool { true }
    var supportsPeek: Bool { false }
    func presentPeek(parent: LivePage, preview: LivePage, url: URL) -> Bool { false }
    func endPeek(restoreParent: Bool) -> PeekEndResult { .stale }
    func adoptPeekPreview(_ preview: LivePage) {}
    var supportsNavigation: Bool { false }
    func perform(_ command: PageNavigationCommand, on page: LivePage) -> Bool { false }
}

public enum PageRuntimeError: Error, Equatable {
    case unsupportedProfile
    case creationRejected
    case saveFailed
    case invalidCommand
}

/// Coordinates committed organization with an engine, without serializing engine
/// handles. Commit must save successfully before returning; it must not publish a
/// candidate and then throw. Live page closures can be cancelled by the engine.
@MainActor
public final class PageRuntime {
    public private(set) var state: BrowserState
    public private(set) var livePages: [UUID: LivePage] = [:]
    public private(set) var pendingClose: Set<LivePage> = []
    public private(set) var lastError: PageRuntimeError?
    public private(set) var peekSession = PeekSession()
    public var onStateChange: ((BrowserState) -> Void)?
    public var supportsSplits: Bool { engine.supportsSplits }
    public var canOpenPeek: Bool {
        engine.supportsPeek && peekSession.preview == nil && state.currentSplit == nil &&
            state.currentWorkspace.activeEntryID.flatMap { livePages[$0] }.map { !pendingClose.contains($0) } == true
    }
    /// The page navigation commands act on: the selected live page, or the focused side of a split.
    /// None while a Peek is presented, so a command can never reach the parent beneath the scrim
    /// or the transient preview.
    public var navigationTarget: LivePage? {
        guard engine.supportsNavigation, peekSession.preview == nil, let page = selectedLivePage,
              !pendingClose.contains(page) else { return nil }
        return page
    }
    public func canPerform(_ command: PageNavigationCommand) -> Bool {
        guard navigationTarget != nil else { return false }
        switch command {
        case .load(let url):
            return ["http", "https"].contains(url.scheme?.lowercased() ?? "") &&
                url.host?.isEmpty == false && url.user == nil && url.password == nil
        }
    }
    /// A caller that captured its target earlier passes it, so a selection change in between refuses the command.
    @discardableResult
    public func perform(_ command: PageNavigationCommand, on expected: LivePage? = nil) -> Bool {
        guard let page = navigationTarget, expected == nil || expected == page, canPerform(command),
              engine.perform(command, on: page) else {
            lastError = .invalidCommand
            return false
        }
        return true
    }
    /// Pure: link triggers call this synchronously from inside an engine navigation request.
    public func canOpenPeek(from parent: LivePage, url: URL) -> Bool {
        canOpenPeek && PeekSession.isEligibleLink(url) && state.currentWorkspace.activeEntryID == parent.entryID &&
            livePages[parent.entryID] == parent
    }
    private let engine: any PageEngine
    private var abandonedPreviews: Set<LivePage> = []
    private var pagesWithUncommittedNavigation: [LivePage: UUID] = [:]
    private let commit: (BrowserState) throws -> Void

    public init(state: BrowserState, engine: any PageEngine,
                commit: @escaping (BrowserState) throws -> Void) throws {
        try state.validate()
        guard engine.supportsProfile(state.currentWorkspace.profileID) else {
            throw PageRuntimeError.unsupportedProfile
        }
        self.state = state
        self.engine = engine
        self.commit = commit
    }

    /// Explicit so clients can finish callback wiring before creation begins.
    @discardableResult
    public func start() -> Bool { showSelection() }

    @discardableResult
    public func addTab(url: URL, title: String) -> Bool {
        change { _ = try $0.addTab(url: url, title: title) }
    }

    @discardableResult
    public func selectEntry(_ id: UUID) -> Bool {
        change { try $0.selectEntry(id) }
    }

    /// Resolve both identities against current organization before selecting an engine page.
    /// Modal hosts can defer engine work until their sheet has dismissed, then call start().
    @discardableResult
    public func activateEntry(_ id: UUID, inWorkspace workspaceID: UUID,
                              deferPageSelection: Bool = false) -> Bool {
        guard !pendingClose.contains(where: { $0.entryID == id }) else {
            lastError = .invalidCommand
            return false
        }
        return change(reconcileSelection: !deferPageSelection) {
            try $0.activateEntry(id, inWorkspace: workspaceID)
        }
    }

    @discardableResult
    public func activateWorkspace(_ id: UUID) -> Bool {
        change { try $0.activateWorkspace(id) }
    }

    @discardableResult
    public func addWorkspace(name: String) -> Bool {
        change { candidate in
            let id = try candidate.addWorkspace(name: name, profileID: candidate.currentWorkspace.profileID)
            try candidate.activateWorkspace(id)
        }
    }

    /// Adopts organization the caller has already saved. It must keep the current selection:
    /// organization imports and restores add or remove other workspaces, never the visible page.
    @discardableResult
    public func adoptSavedOrganization(_ saved: BrowserState) -> Bool {
        guard (try? saved.validate()) != nil,
              saved.activeWorkspaceID == state.activeWorkspaceID,
              saved.currentWorkspace.activeEntryID == state.currentWorkspace.activeEntryID,
              saved.currentSplit?.id == state.currentSplit?.id else {
            lastError = .invalidCommand
            return false
        }
        state = saved
        lastError = nil
        onStateChange?(saved)
        return true
    }

    /// Replaces organization with a restored backup the caller has already saved. Unlike
    /// `adoptSavedOrganization` it may change the selection, so it is only allowed while no page is live.
    @discardableResult
    public func adoptRestoredOrganization(_ saved: BrowserState) -> Bool {
        guard livePages.isEmpty, peekSession.preview == nil, (try? saved.validate()) != nil else {
            lastError = .invalidCommand
            return false
        }
        state = saved
        lastError = nil
        onStateChange?(saved)
        return true
    }

    /// A metadata edit must not refocus or recreate the current engine page.
    @discardableResult
    public func updateWorkspace(_ id: UUID, name: String, color: String) -> Bool {
        change(reconcileSelection: false) { try $0.updateWorkspace(id, name: name, color: color) }
    }

    /// Creates the Profile and enters its first workspace in one validated step, so a Profile the engine
    /// cannot open is never saved.
    @discardableResult
    public func createProfile(name: String, color: String, workspaceName: String,
                              deferPageSelection: Bool = false) -> Bool {
        change(reconcileSelection: !deferPageSelection) { candidate in
            let created = try candidate.createProfile(name: name, color: color, workspaceName: workspaceName)
            try candidate.activateWorkspace(created.workspaceID)
        }
    }

    /// Metadata only: the visible page and the Profile's engine context are untouched.
    @discardableResult
    public func updateProfile(_ id: UUID, name: String, color: String) -> Bool {
        change(reconcileSelection: false) { try $0.updateProfile(id, name: name, color: color) }
    }

    /// Workspace ordering must not change active pages or pending close operations.
    @discardableResult
    public func moveWorkspace(_ id: UUID, direction: WorkspaceMoveDirection) -> Bool {
        change(reconcileSelection: false) { try $0.moveWorkspace(id, direction: direction) }
    }

    @discardableResult
    public func createFolder(name: String, parentID: UUID? = nil) -> Bool {
        change(reconcileSelection: false) { _ = try $0.createFolder(name: name, parentID: parentID) }
    }

    @discardableResult
    public func renameFolder(_ id: UUID, name: String) -> Bool {
        change(reconcileSelection: false) { try $0.renameFolder(id, name: name) }
    }

    @discardableResult
    public func setFolderCollapsed(_ id: UUID, collapsed: Bool) -> Bool {
        change(reconcileSelection: false) { try $0.setFolderCollapsed(id, collapsed: collapsed) }
    }

    @discardableResult
    public func moveFolder(_ id: UUID, direction: FolderMoveDirection) -> Bool {
        change(reconcileSelection: false) { try $0.moveFolder(id, direction: direction) }
    }

    @discardableResult
    public func moveFolder(_ id: UUID, toParent parentID: UUID?) -> Bool {
        change(reconcileSelection: false) { try $0.moveFolder(id, toParent: parentID) }
    }

    @discardableResult
    public func dissolveFolder(_ id: UUID) -> Bool {
        guard let folder = state.currentWorkspace.folders.first(where: { $0.id == id }),
              !pendingClose.contains(where: { folder.pinIDs.contains($0.entryID) }) else {
            lastError = .invalidCommand
            return false
        }
        return change(reconcileSelection: false) { try $0.dissolveFolder(id) }
    }

    @discardableResult
    public func movePin(_ id: UUID, toFolder folderID: UUID?) -> Bool {
        guard !pendingClose.contains(where: { $0.entryID == id }) else {
            lastError = .invalidCommand
            return false
        }
        return change(reconcileSelection: false) { try $0.movePin(id, toFolder: folderID) }
    }

    @discardableResult
    public func createSplit(with id: UUID) -> Bool {
        guard supportsSplits, state.canCreateSplit(with: id),
              !pendingClose.contains(where: { $0.entryID == id || $0.entryID == state.currentWorkspace.activeEntryID }) else {
            lastError = .invalidCommand
            return false
        }
        return change { _ = try $0.createSplit(with: id) }
    }

    @discardableResult
    public func activateSplit(_ id: UUID, focusedEntryID: UUID? = nil) -> Bool {
        guard supportsSplits, let pair = state.currentWorkspace.splits.first(where: { $0.id == id }),
              !pendingClose.contains(where: { pair.contains($0.entryID) }) else {
            lastError = .invalidCommand
            return false
        }
        return change { try $0.activateSplit(id, focusedEntryID: focusedEntryID) }
    }

    @discardableResult
    public func deactivateSplit() -> Bool {
        change { try $0.deactivateSplit() }
    }

    @discardableResult
    public func dissolveSplit(_ id: UUID) -> Bool {
        change { try $0.dissolveSplit(id) }
    }

    @discardableResult
    public func pinSplit(_ id: UUID) -> Bool {
        guard let pair = state.currentWorkspace.splits.first(where: { $0.id == id }),
              !pendingClose.contains(where: { pair.contains($0.entryID) }),
              ![pair.leftEntryID, pair.rightEntryID].contains(where: { id in
                  guard let page = livePages[id] else { return false }
                  return pagesWithUncommittedNavigation[page] != nil
              }) else {
            lastError = .invalidCommand
            return false
        }
        return change(reconcileSelection: false) { try $0.pinSplit(id) }
    }

    @discardableResult
    public func updateSplitRatio(_ id: UUID, ratio: Double) -> Bool {
        change { try $0.updateSplitRatio(id, ratio: ratio) }
    }

    /// Reorders organization without changing page visibility or close semantics.
    @discardableResult
    public func moveEntry(_ id: UUID, direction: EntryMoveDirection) -> Bool {
        change(reconcileSelection: false) { try $0.moveEntry(id, direction: direction) }
    }

    /// Moving an active entry hides it after commit; background moves leave focus untouched.
    @discardableResult
    public func moveEntry(_ id: UUID, toWorkspace destinationID: UUID) -> Bool {
        guard !pendingClose.contains(where: { $0.entryID == id }) else {
            lastError = .invalidCommand
            return false
        }
        let movesSelection = state.currentWorkspace.activeEntryID == id || state.currentSplit?.contains(id) == true
        return change(reconcileSelection: movesSelection) {
            try $0.moveEntry(id, toWorkspace: destinationID)
        }
    }

    @discardableResult
    public func pinEntry(_ id: UUID) -> Bool {
        change { try $0.pinEntry(id) }
    }

    @discardableResult
    public func favoriteEntry(_ id: UUID) -> Bool {
        change { try $0.favoriteEntry(id) }
    }

    /// Drops saved status as an organization-only transaction. An in-flight
    /// close must finish or cancel before its saved/temporary semantics change.
    @discardableResult
    public func makeTemporary(_ id: UUID) -> Bool {
        guard !pendingClose.contains(where: { $0.entryID == id }) else {
            lastError = .invalidCommand
            return false
        }
        return change(reconcileSelection: state.currentSplit?.contains(id) == true) { try $0.makeTemporary(id) }
    }

    /// Whether a saved page's latest destination is safely represented by committed
    /// organization. Failed or unsupported navigation must not save an older URL.
    public func canUpdateSavedURL(_ id: UUID) -> Bool {
        guard let entry = state.visibleEntries.first(where: { $0.id == id }),
              entry.kind != .temporary, let page = livePages[id],
              page.entryID == id, page.profileID == state.currentWorkspace.profileID else { return false }
        return !pendingClose.contains(page) && pagesWithUncommittedNavigation[page] == nil
    }

    /// Adopts the current committed page destination without navigating/refocusing.
    @discardableResult
    public func updateSavedURL(_ id: UUID) -> Bool {
        guard canUpdateSavedURL(id) else {
            lastError = .invalidCommand
            return false
        }
        return change(reconcileSelection: false) { try $0.updateSavedURL(id) }
    }

    /// Unloaded entries close immediately after committing. Loaded entries remain
    /// in the organization until the matching engine closed event is received.
    @discardableResult
    public func closeEntry(_ id: UUID) -> Bool {
        guard state.visibleEntries.contains(where: { $0.id == id }) else {
            lastError = .invalidCommand
            return false
        }
        guard let page = livePages[id] else {
            return change { try $0.closeEntry(id) }
        }
        guard pendingClose.insert(page).inserted else { return true }
        engine.requestClose(page)
        return true
    }

    /// Previews the destination above the current live page without touching organization.
    @discardableResult
    public func openPeek(url: URL) -> Bool {
        guard canOpenPeek, let parentID = state.currentWorkspace.activeEntryID, let parent = livePages[parentID] else {
            lastError = .invalidCommand
            return false
        }
        let preview = LivePage(entryID: UUID(), profileID: parent.profileID)
        var session = peekSession
        guard session.open(parent: parent, page: preview, url: url) else {
            lastError = .invalidCommand
            return false
        }
        peekSession = session
        guard engine.presentPeek(parent: parent, preview: preview, url: url) else {
            _ = peekSession.handle(.creationFailed(preview))
            lastError = .creationRejected
            return false
        }
        return true
    }

    /// Revalidates the parent and destination: the page state may have changed since a link trigger fired.
    @discardableResult
    public func openPeek(from parent: LivePage, url: URL) -> Bool {
        guard canOpenPeek(from: parent, url: url) else {
            lastError = .invalidCommand
            return false
        }
        return openPeek(url: url)
    }

    /// Dismisses only the named preview, so a late scrim click for an ended Peek cannot close its successor.
    @discardableResult
    public func dismissPeek(preview: LivePage) -> Bool {
        peekSession.preview?.page == preview && dismissPeek()
    }

    /// Closure goes through the engine's before-unload confirmation; the preview
    /// stays owned until the engine reports it closed, and Cancel restores it.
    @discardableResult
    public func dismissPeek() -> Bool {
        guard let page = peekSession.requestDismissal() else { return false }
        engine.requestClose(page)
        return true
    }

    /// Adopts the live preview as the selected tab. Nothing is navigated, reloaded
    /// or recreated, and a failed save leaves the preview presented.
    @discardableResult
    public func promotePeek() -> Bool {
        guard let prepared = peekSession.preparePromotion(),
              state.currentWorkspace.activeEntryID == prepared.parent.entryID,
              state.currentWorkspace.profileID == prepared.page.profileID else {
            lastError = .invalidCommand
            return false
        }
        var candidate = state
        var session = peekSession
        do {
            _ = try candidate.addTab(id: prepared.page.entryID, url: prepared.url, title: prepared.title)
            try candidate.validate()
        } catch {
            lastError = .invalidCommand
            return false
        }
        guard session.completePromotion(prepared) else {
            lastError = .invalidCommand
            return false
        }
        let previous = peekSession
        peekSession = session
        guard save(candidate) else {
            peekSession = previous
            return false
        }
        livePages[prepared.page.entryID] = prepared.page
        engine.adoptPeekPreview(prepared.page)
        if engine.endPeek(restoreParent: false) != .ended { engine.select(selectedLivePage) }
        return true
    }

    private func handlePeekEnded(_ preview: LivePage, _ reason: PeekEndReason) {
        guard peekSession.preview?.page == preview else { return }
        peekSession.finish()
        switch reason {
        case .selectionChanged, .fullscreen, .modal, .split, .parentClosed:
            abandonedPreviews.insert(preview)
            retryAbandonedPreviews()
        case .previewClosed, .teardown, .closing:
            break
        }
    }

    /// Ends any presentation and closes its preview, restoring the parent. A host
    /// calls this before showing a window sheet, which the engine would otherwise
    /// treat as a modal end it cannot clean up while the sheet is attached.
    public func endPeek() { tearDownPeek(restoreParent: true) }

    /// The engine rejects selection and close while a sheet or modal is attached,
    /// so a rejected close leaves the preview here for the host to retry after it detaches.
    public func retryAbandonedPreviews() {
        guard !abandonedPreviews.isEmpty else { return }
        engine.select(selectedLivePage)
        for preview in abandonedPreviews { engine.requestClose(preview) }
    }

    private func tearDownPeek(restoreParent: Bool = false) {
        guard let preview = peekSession.preview?.page,
              engine.endPeek(restoreParent: restoreParent) != .stale else { return }
        peekSession.finish()
        abandonedPreviews.insert(preview)
        retryAbandonedPreviews()
    }

    public func receive(_ event: PageEvent) {
        if case let .peekEnded(preview, reason) = event { return handlePeekEnded(preview, reason) }
        if case let .closed(page) = event { abandonedPreviews.remove(page) }
        if case let .unloaded(page) = event { abandonedPreviews.remove(page) }
        if peekSession.handle(event) { return }
        switch event {
        case let .splitRatioChanged(left, right, ratio):
            guard livePages[left.entryID] == left, livePages[right.entryID] == right,
                  let pair = state.currentSplit,
                  pair.leftEntryID == left.entryID, pair.rightEntryID == right.entryID,
                  ratio.isFinite, ratio > 0, ratio < 1, abs(pair.dividerRatio - ratio) > 0.0001 else { return }
            _ = change(reconcileSelection: false) { try $0.updateSplitRatio(pair.id, ratio: ratio) }
        case let .splitSeparated(left, right):
            guard livePages[left.entryID] == left, livePages[right.entryID] == right,
                  let pair = state.currentSplit,
                  pair.leftEntryID == left.entryID, pair.rightEntryID == right.entryID else { return }
            _ = change(reconcileSelection: false) { try $0.deactivateSplit() }
        case let .selected(page):
            guard livePages[page.entryID] == page else { return }
            if state.currentWorkspace.activeEntryID == page.entryID { return }
            // Chromium already focused this visible split side. Re-presenting
            // would restore a persisted divider before its pending change event.
            let isCurrentSplitSide = state.currentSplit?.contains(page.entryID) == true
            let accepted = change(reconcileSelection: !isCurrentSplitSide) { candidate in
                if !candidate.visibleEntries.contains(where: { $0.id == page.entryID }) {
                    guard let owner = candidate.workspaces.first(where: {
                        $0.profileID == page.profileID && ($0.pins + $0.tabs).contains(where: { $0.id == page.entryID })
                    }) else { throw PageRuntimeError.invalidCommand }
                    try candidate.activateWorkspace(owner.id)
                }
                try candidate.selectEntry(page.entryID)
            }
            if !accepted { engine.select(selectedLivePage) }
        case .peekEnded:
            return
        case .selectionCleared:
            guard state.currentWorkspace.activeEntryID != nil else { return }
            let accepted = change { candidate in
                guard let index = candidate.workspaces.firstIndex(where: { $0.id == candidate.activeWorkspaceID }) else {
                    throw PageRuntimeError.invalidCommand
                }
                try candidate.deactivateSplit()
                candidate.workspaces[index].activeEntryID = nil
            }
            if !accepted { engine.select(selectedLivePage) }
        case let .unloaded(page):
            guard livePages[page.entryID] == page else { return }
            livePages.removeValue(forKey: page.entryID)
            pendingClose.remove(page)
            pagesWithUncommittedNavigation.removeValue(forKey: page)
            engine.select(selectedLivePage)
        case let .creationFailed(page):
            guard livePages[page.entryID] == page else { return }
            livePages.removeValue(forKey: page.entryID)
            pendingClose.remove(page)
            pagesWithUncommittedNavigation.removeValue(forKey: page)
            leaveFailedSplit(page)
            if lastError != .saveFailed { lastError = .creationRejected }
            engine.select(selectedLivePage)
        case let .navigation(page, url, title):
            guard livePages[page.entryID] == page else { return }
            // BrowserState validates URL scheme, host and embedded credentials.
            // Unsupported engine/internal URLs are ignored, never navigated back.
            let navigationAttempt = UUID()
            pagesWithUncommittedNavigation[page] = navigationAttempt
            var candidate = state
            guard (try? candidate.recordNavigation(entryID: page.entryID, url: url, title: title)) != nil else { return }
            if save(candidate), livePages[page.entryID] == page,
               pagesWithUncommittedNavigation[page] == navigationAttempt {
                pagesWithUncommittedNavigation.removeValue(forKey: page)
            }
        case let .closeCancelled(page):
            guard livePages[page.entryID] == page else { return }
            pendingClose.remove(page)
        case let .closed(page):
            guard livePages[page.entryID] == page else { return }
            livePages.removeValue(forKey: page.entryID)
            pendingClose.remove(page)
            pagesWithUncommittedNavigation.removeValue(forKey: page)
            // The entry may belong to a workspace that is no longer active.
            // Apply close in its owner workspace, then restore current selection.
            var candidate = state
            let active = candidate.activeWorkspaceID
            if let owner = candidate.workspaces.first(where: {
                $0.profileID == page.profileID && ($0.pins + $0.tabs).contains(where: { $0.id == page.entryID })
            }) {
                try? candidate.activateWorkspace(owner.id)
            } else if let owner = candidate.workspaces.first(where: { $0.profileID == page.profileID }) {
                try? candidate.activateWorkspace(owner.id)
            }
            do {
                try candidate.closeEntry(page.entryID)
                try candidate.activateWorkspace(active)
                _ = save(candidate)
            } catch {
                lastError = .invalidCommand
            }
            engine.select(selectedLivePage)
            // A failed save leaves the committed entry unloaded. Do not recreate
            // it automatically after a physical engine close.
        }
    }

    private var selectedLivePage: LivePage? {
        state.currentWorkspace.activeEntryID.flatMap { livePages[$0] }
    }

    private func change(reconcileSelection: Bool = true,
                        _ mutate: (inout BrowserState) throws -> Void) -> Bool {
        var candidate = state
        do {
            try mutate(&candidate)
            try candidate.validate()
            guard candidate.currentSplit == nil || supportsSplits else {
                lastError = .invalidCommand
                return false
            }
            guard engine.supportsProfile(candidate.currentWorkspace.profileID) else {
                lastError = .unsupportedProfile
                return false
            }
        } catch {
            lastError = .invalidCommand
            return false
        }
        let movesSelection = candidate.activeWorkspaceID != state.activeWorkspaceID ||
            candidate.currentWorkspace.activeEntryID != state.currentWorkspace.activeEntryID ||
            candidate.currentSplit?.id != state.currentSplit?.id
        guard save(candidate) else { return false }
        if movesSelection { tearDownPeek() }
        return reconcileSelection ? showSelection() : true
    }

    private func save(_ candidate: BrowserState) -> Bool {
        do {
            try commit(candidate)
            state = candidate
            lastError = nil
            onStateChange?(candidate)
            return true
        } catch {
            lastError = .saveFailed
            return false
        }
    }

    private func leaveFailedSplit(_ page: LivePage) {
        guard let pair = state.currentSplit, pair.contains(page.entryID) else { return }
        let survivor = pair.leftEntryID == page.entryID ? pair.rightEntryID : pair.leftEntryID
        _ = change(reconcileSelection: false) { candidate in
            try candidate.deactivateSplit()
            try candidate.selectEntry(survivor)
        }
        _ = engine.separateSplit()
    }

    private func ensurePage(_ id: UUID, profileID: UUID) -> LivePage? {
        if let page = livePages[id] { return page }
        guard let entry = state.visibleEntries.first(where: { $0.id == id }) else { return nil }
        let page = LivePage(entryID: id, profileID: profileID)
        livePages[id] = page
        guard engine.create(page, url: entry.savedURL ?? entry.lastURL), livePages[id] == page else {
            if livePages[id] == page { livePages.removeValue(forKey: id) }
            pagesWithUncommittedNavigation.removeValue(forKey: page)
            leaveFailedSplit(page)
            engine.select(selectedLivePage)
            lastError = .creationRejected
            return nil
        }
        return page
    }

    private func showSelection() -> Bool {
        let workspace = state.currentWorkspace
        guard engine.supportsProfile(workspace.profileID) else {
            lastError = .unsupportedProfile
            return false
        }
        engine.activateProfile(workspace.profileID)
        if let pair = state.currentSplit {
            guard supportsSplits else { lastError = .invalidCommand; return false }
            guard let left = ensurePage(pair.leftEntryID, profileID: workspace.profileID),
                  state.currentSplit?.id == pair.id,
                  let right = ensurePage(pair.rightEntryID, profileID: workspace.profileID),
                  let current = state.currentSplit, current.id == pair.id,
                  livePages[left.entryID] == left, livePages[right.entryID] == right,
                  let focusedID = state.currentWorkspace.activeEntryID,
                  let focused = livePages[focusedID], focused == left || focused == right,
                  engine.presentSplit(left: left, right: right, focused: focused, ratio: current.dividerRatio) else {
                lastError = .creationRejected
                return false
            }
            return true
        }
        guard engine.separateSplit() else { lastError = .creationRejected; return false }
        guard let id = workspace.activeEntryID,
              let entry = state.visibleEntries.first(where: { $0.id == id }) else {
            engine.select(nil)
            return true
        }
        if let page = livePages[id] {
            engine.select(page)
            return true
        }
        let page = LivePage(entryID: id, profileID: workspace.profileID)
        livePages[id] = page
        // A missing live page is a reopen: saved entries use their explicit
        // destination, while temporary entries resume their latest session URL.
        guard engine.create(page, url: entry.savedURL ?? entry.lastURL) else {
            if livePages[id] == page { livePages.removeValue(forKey: id) }
            pagesWithUncommittedNavigation.removeValue(forKey: page)
            lastError = .creationRejected
            engine.select(selectedLivePage)
            return false
        }
        // Creation may synchronously report failure/closure through the sink.
        if livePages[id] == page {
            // A synchronous callback can commit navigation, whose observer can
            // select another entry. Never restore the older selection afterward.
            engine.select(selectedLivePage)
        }
        return livePages[id] == page
    }
}
