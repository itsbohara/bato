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
}

/// All calls and events use the main actor. Acceptance of create means the adapter
/// owns this token until a terminal event, including while creation is pending.
/// The adapter reports failed creation as creationFailed, not closed.
@MainActor
public protocol PageEngine: AnyObject {
    var supportedProfileIDs: Set<UUID> { get }
    func create(_ page: LivePage, url: URL) -> Bool
    /// nil hides any previously visible page. A token whose creation is pending
    /// shows blank/loading content until ready, never a previously selected page.
    func select(_ page: LivePage?)
    func requestClose(_ page: LivePage)
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
    public var onStateChange: ((BrowserState) -> Void)?
    private let engine: any PageEngine
    private let commit: (BrowserState) throws -> Void

    public init(state: BrowserState, engine: any PageEngine,
                commit: @escaping (BrowserState) throws -> Void) throws {
        try state.validate()
        guard engine.supportedProfileIDs.contains(state.currentWorkspace.profileID) else {
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

    /// A metadata edit must not refocus or recreate the current engine page.
    @discardableResult
    public func updateWorkspace(_ id: UUID, name: String, color: String) -> Bool {
        change(reconcileSelection: false) { try $0.updateWorkspace(id, name: name, color: color) }
    }

    @discardableResult
    public func pinEntry(_ id: UUID) -> Bool {
        change { try $0.pinEntry(id) }
    }

    @discardableResult
    public func favoriteEntry(_ id: UUID) -> Bool {
        change { try $0.favoriteEntry(id) }
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

    public func receive(_ event: PageEvent) {
        switch event {
        case let .selected(page):
            guard livePages[page.entryID] == page else { return }
            if state.currentWorkspace.activeEntryID == page.entryID { return }
            let accepted = change { candidate in
                if !candidate.visibleEntries.contains(where: { $0.id == page.entryID }) {
                    guard let owner = candidate.workspaces.first(where: {
                        $0.profileID == page.profileID && ($0.pins + $0.tabs).contains(where: { $0.id == page.entryID })
                    }) else { throw PageRuntimeError.invalidCommand }
                    try candidate.activateWorkspace(owner.id)
                }
                try candidate.selectEntry(page.entryID)
            }
            if !accepted { engine.select(selectedLivePage) }
        case .selectionCleared:
            guard state.currentWorkspace.activeEntryID != nil else { return }
            let accepted = change { candidate in
                guard let index = candidate.workspaces.firstIndex(where: { $0.id == candidate.activeWorkspaceID }) else {
                    throw PageRuntimeError.invalidCommand
                }
                candidate.workspaces[index].activeEntryID = nil
            }
            if !accepted { engine.select(selectedLivePage) }
        case let .unloaded(page):
            guard livePages[page.entryID] == page else { return }
            livePages.removeValue(forKey: page.entryID)
            pendingClose.remove(page)
            engine.select(selectedLivePage)
        case let .creationFailed(page):
            guard livePages[page.entryID] == page else { return }
            livePages.removeValue(forKey: page.entryID)
            pendingClose.remove(page)
            lastError = .creationRejected
            engine.select(selectedLivePage)
        case let .navigation(page, url, title):
            guard livePages[page.entryID] == page else { return }
            // BrowserState validates URL scheme, host and embedded credentials.
            // Unsupported engine/internal URLs are ignored, never navigated back.
            var candidate = state
            guard (try? candidate.recordNavigation(entryID: page.entryID, url: url, title: title)) != nil else { return }
            _ = save(candidate)
        case let .closeCancelled(page):
            guard livePages[page.entryID] == page else { return }
            pendingClose.remove(page)
        case let .closed(page):
            guard livePages[page.entryID] == page else { return }
            livePages.removeValue(forKey: page.entryID)
            pendingClose.remove(page)
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
            guard engine.supportedProfileIDs.contains(candidate.currentWorkspace.profileID) else {
                lastError = .unsupportedProfile
                return false
            }
        } catch {
            lastError = .invalidCommand
            return false
        }
        guard save(candidate) else { return false }
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

    private func showSelection() -> Bool {
        let workspace = state.currentWorkspace
        guard engine.supportedProfileIDs.contains(workspace.profileID) else {
            lastError = .unsupportedProfile
            return false
        }
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
        guard engine.create(page, url: entry.lastURL) else {
            if livePages[id] == page { livePages.removeValue(forKey: id) }
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
