import Foundation

/// How long a temporary tab may sit unused before it is archived.
public enum ArchivePeriod: String, Codable, CaseIterable, Sendable {
    case twelveHours, day, week, month, never

    public var interval: TimeInterval? {
        switch self {
        case .twelveHours: 12 * 3600
        case .day: 24 * 3600
        case .week: 7 * 24 * 3600
        case .month: 30 * 24 * 3600
        case .never: nil
        }
    }

    public var title: String {
        switch self {
        case .twelveHours: "After 12 hours"
        case .day: "After 24 hours"
        case .week: "After 7 days"
        case .month: "After 30 days"
        case .never: "Never"
        }
    }
}

/// A temporary tab that was archived, with where it sat so restoring can put it back.
public struct ArchiveRecord: Identifiable, Codable, Equatable, Sendable {
    /// The archived tab's own identity, which a restore gives back to the tab.
    public var id: UUID
    public var profileID: UUID
    public var workspaceID: UUID
    public var title: String
    public var url: URL
    public var index: Int
    public var archivedAt: Date

    public init(id: UUID, profileID: UUID, workspaceID: UUID, title: String, url: URL, index: Int, archivedAt: Date) {
        self.id = id
        self.profileID = profileID
        self.workspaceID = workspaceID
        self.title = title
        self.url = url
        self.index = index
        self.archivedAt = archivedAt
    }
}

/// The global archive period and the archived tabs. A default value is not encoded, so documents
/// that never used the archive keep their bytes.
public struct ArchiveState: Codable, Equatable, Sendable {
    public var period: ArchivePeriod
    public var records: [ArchiveRecord]

    public init(period: ArchivePeriod = .never, records: [ArchiveRecord] = []) {
        self.period = period
        self.records = records
    }

    public var isDefault: Bool { self == ArchiveState() }

    /// Newest first, optionally narrowed to one Profile and a case-insensitive title or address match.
    public func records(inProfile profileID: UUID, matching query: String = "") -> [ArchiveRecord] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return records.filter { $0.profileID == profileID }.filter { record in
            query.isEmpty || [record.title, record.url.absoluteString].contains {
                $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }.sorted { $0.archivedAt > $1.archivedAt }
    }
}

extension BrowserState {
    /// The workspace's own period, else the global one.
    public func archivePeriod(of workspace: Workspace) -> ArchivePeriod {
        workspace.archivePeriod ?? archive.period
    }

    /// Archive data needs version 3. Documents that never use it stay at their old version.
    public mutating func setArchivePeriod(_ period: ArchivePeriod) throws {
        try applyArchiveChange { $0.archive.period = period }
    }

    /// `nil` makes the workspace follow the global period again.
    public mutating func setArchivePeriod(_ period: ArchivePeriod?, forWorkspace id: UUID) throws {
        try applyArchiveChange { draft in
            guard let index = draft.workspaces.firstIndex(where: { $0.id == id }) else {
                throw BrowserStateError.missingWorkspace
            }
            draft.workspaces[index].archivePeriod = period
        }
    }

    /// Moves a temporary tab of any workspace into the archive. Saved entries are never archived.
    @discardableResult
    public mutating func archiveTab(_ id: UUID, at now: Date) throws -> UUID {
        try applyArchiveChange { draft in
            for index in draft.workspaces.indices {
                guard let position = draft.workspaces[index].tabs.firstIndex(where: { $0.id == id }) else { continue }
                let workspace = draft.workspaces[index]
                let entry = workspace.tabs[position]
                draft.archive.records.append(ArchiveRecord(
                    id: entry.id, profileID: workspace.profileID, workspaceID: workspace.id,
                    title: entry.title, url: entry.lastURL, index: position, archivedAt: now))
                draft.removeTemporaryTab(id)
                return
            }
            throw BrowserStateError.missingEntry
        }
        return id
    }

    /// Puts an archived tab back at its old position in its original workspace, or in the first
    /// workspace of its Profile when that one is gone, and selects it.
    @discardableResult
    public mutating func restoreArchivedTab(_ id: UUID) throws -> UUID {
        try applyArchiveChange { draft in
            guard let position = draft.archive.records.firstIndex(where: { $0.id == id }) else {
                throw BrowserStateError.missingEntry
            }
            let record = draft.archive.records.remove(at: position)
            guard let workspace = draft.workspaces.firstIndex(where: { $0.id == record.workspaceID && $0.profileID == record.profileID })
                    ?? draft.workspaces.firstIndex(where: { $0.profileID == record.profileID }) else {
                throw BrowserStateError.missingWorkspace
            }
            let entry = PageEntry(id: record.id, title: record.title, lastURL: record.url, kind: .temporary)
            let slot = min(max(record.index, 0), draft.workspaces[workspace].tabs.count)
            draft.workspaces[workspace].tabs.insert(entry, at: slot)
            draft.activeWorkspaceID = draft.workspaces[workspace].id
            draft.selectTabInPlace(entry.id)
        }
        return id
    }

    public mutating func deleteArchivedTab(_ id: UUID) throws {
        try applyArchiveChange { draft in
            guard draft.archive.records.contains(where: { $0.id == id }) else { throw BrowserStateError.missingEntry }
            draft.archive.records.removeAll { $0.id == id }
        }
    }

    /// What "Clear" archives: every Today tab of the current workspace except the selected one and, when the
    /// selection is half of a pair, its partner.
    public func clearableTabIDs() -> [UUID] {
        let workspace = currentWorkspace
        let kept = keptTabIDs(in: workspace)
        return workspace.tabs.map(\.id).filter { !kept.contains($0) }
    }

    /// What "Tidy" archives: Today tabs repeating the address of another Today tab. The selected tab (and its
    /// pair partner) wins its group, else the first one; tabs in any pair are left alone.
    public func duplicateTabIDs() -> [UUID] {
        let workspace = currentWorkspace
        let kept = keptTabIDs(in: workspace)
        let paired = Set(workspace.splits.flatMap { [$0.leftEntryID, $0.rightEntryID] })
        var winners: [String: UUID] = [:]
        for tab in workspace.tabs where kept.contains(tab.id) { winners[tab.lastURL.absoluteString] = tab.id }
        var duplicates: [UUID] = []
        for tab in workspace.tabs where !paired.contains(tab.id) {
            let key = tab.lastURL.absoluteString
            if let winner = winners[key] {
                if winner != tab.id { duplicates.append(tab.id) }
            } else {
                winners[key] = tab.id
            }
        }
        return duplicates
    }

    private func keptTabIDs(in workspace: Workspace) -> Set<UUID> {
        guard let active = workspace.activeEntryID else { return [] }
        var kept: Set<UUID> = [active]
        if let split = workspace.splits.first(where: { $0.contains(active) }) {
            kept.formUnion([split.leftEntryID, split.rightEntryID])
        }
        return kept
    }

    /// True when any workspace archives idle tabs, so activity tracking is worth writing.
    public var archivesIdleTabs: Bool {
        workspaces.contains { archivePeriod(of: $0).interval != nil }
    }

    /// Records "in use now" on the selected temporary tab and starts the clock for tabs with no
    /// record yet, in workspaces that archive. Does nothing when no workspace archives, so such
    /// documents never change.
    public mutating func stampActivity(at now: Date) {
        guard archivesIdleTabs else { return }
        var next = self
        for index in next.workspaces.indices where archivePeriod(of: next.workspaces[index]).interval != nil {
            let active = next.workspaces[index].id == next.activeWorkspaceID ? next.workspaces[index].activeEntryID : nil
            for tab in next.workspaces[index].tabs.indices {
                let isActive = next.workspaces[index].tabs[tab].id == active
                if isActive || next.workspaces[index].tabs[tab].lastActiveAt == nil {
                    next.workspaces[index].tabs[tab].lastActiveAt = now
                }
            }
        }
        guard next != self else { return }
        next.version = max(next.version, Self.archiveVersion)
        self = next
    }

    /// Temporary tabs that have been idle for their workspace's whole period. The selected tab of the
    /// current workspace and tabs in a split are never idle.
    public func idleTabIDs(at now: Date) -> [UUID] {
        var idle: [UUID] = []
        for workspace in workspaces {
            guard let interval = archivePeriod(of: workspace).interval else { continue }
            let inSplit = Set(workspace.splits.flatMap { [$0.leftEntryID, $0.rightEntryID] })
            let selected = workspace.id == activeWorkspaceID ? workspace.activeEntryID : nil
            for tab in workspace.tabs where tab.id != selected && !inSplit.contains(tab.id) {
                if let last = tab.lastActiveAt, now.timeIntervalSince(last) >= interval { idle.append(tab.id) }
            }
        }
        return idle
    }

    private mutating func applyArchiveChange(_ change: (inout BrowserState) throws -> Void) throws {
        var draft = self
        try draft.validate()
        try change(&draft)
        draft.version = max(draft.version, Self.archiveVersion)
        try draft.validate()
        self = draft
    }
}
