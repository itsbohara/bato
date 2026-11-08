import Foundation

/// One row of the sidebar list: a page, or a split pair shown as a single row at the position of its first listed member.
public struct SidebarRow: Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        case page(PageEntry)
        case pair(PageSplit, left: PageEntry, right: PageEntry)
    }
    public var content: Content
    /// Index in the section's entry list of the entry that gives the row its position.
    public var modelIndex: Int
    /// That entry; for a pair it is whichever member is listed first, not necessarily the left pane.
    public var leadingEntryID: UUID

    /// Whichever member a click on the row selects when none is named.
    public var selectionEntryID: UUID {
        if case .pair(let split, _, _) = content { return split.leftEntryID }
        return leadingEntryID
    }
}

extension BrowserState {
    /// The entries a section lists, in model order, before pairs are collapsed.
    public func sidebarEntries(in section: SidebarSection) -> [PageEntry] {
        let workspace = currentWorkspace
        switch section {
        case .favorites:
            return profiles[currentProfileIndex].favorites
        case .tabs:
            return workspace.tabs
        case .pinned(let folderID?):
            return workspace.folder(folderID)?.pinIDs.compactMap { id in workspace.pins.first { $0.id == id } } ?? []
        case .pinned(nil):
            let filed = Set(workspace.folders.flatMap(\.pinIDs))
            return workspace.pins.filter { !filed.contains($0.id) }
        }
    }

    /// Rows the sidebar shows per section, in the order it draws them: Favorites, unfiled pins, folders
    /// (a collapsed folder lists nothing, nor do its subfolders), Tabs. A pair takes the first of its members
    /// to be drawn; its other member never gets a row. Shared by drawing and drop placement so both agree.
    public func sidebarRows() -> [SidebarSection: [SidebarRow]] {
        let workspace = currentWorkspace
        let local = workspace.pins + workspace.tabs
        var placedPairs = Set<UUID>()
        var result: [SidebarSection: [SidebarRow]] = [:]
        func rows(_ section: SidebarSection) {
            result[section] = sidebarEntries(in: section).enumerated().compactMap { index, entry in
                guard let split = workspace.splits.first(where: { $0.contains(entry.id) }),
                      let left = local.first(where: { $0.id == split.leftEntryID }),
                      let right = local.first(where: { $0.id == split.rightEntryID }) else {
                    return SidebarRow(content: .page(entry), modelIndex: index, leadingEntryID: entry.id)
                }
                guard placedPairs.insert(split.id).inserted else { return nil }
                return SidebarRow(content: .pair(split, left: left, right: right), modelIndex: index, leadingEntryID: entry.id)
            }
        }
        rows(.favorites)
        rows(.pinned(folder: nil))
        func visit(_ parent: UUID?) {
            for folder in workspace.subfolders(of: parent) {
                result[.pinned(folder: folder.id)] = []
                guard !folder.isCollapsed else { continue }
                rows(.pinned(folder: folder.id))
                visit(folder.id)
            }
        }
        visit(nil)
        rows(.tabs)
        return result
    }

    /// Where a drop at displayed row `index` lands in the section's entry list; nil appends.
    func modelPosition(forDisplayedRow index: Int, in rows: [SidebarRow]) -> Int? {
        index >= rows.count ? nil : rows[max(0, index)].modelIndex
    }

    /// Favorites, pins and tabs with each pair listed once, for stepping through the sidebar.
    var visibleEntriesCollapsingPairs: [PageEntry] {
        var seen = Set<UUID>()
        return visibleEntries.filter { entry in
            guard let split = split(containingEntry: entry.id) else { return true }
            return seen.insert(split.id).inserted
        }
    }

    /// The first listed member of the pair holding `id`, or `id` itself outside a pair.
    func leadingEntryID(ofPairContaining id: UUID) -> UUID {
        guard let split = split(containingEntry: id) else { return id }
        return visibleEntries.first { split.contains($0.id) }?.id ?? id
    }

    public func canPlaceSplit(_ id: UUID, in section: SidebarSection) -> Bool {
        guard currentWorkspace.splits.contains(where: { $0.id == id }) else { return false }
        switch section {
        case .favorites: return false
        case .tabs: return true
        case .pinned(let folder): return folder.map { currentWorkspace.folder($0) != nil } ?? true
        }
    }

    /// Moves both members of a pair together to displayed row `index` of the section, converting both to its
    /// kind (a saved pair dropped among tabs stops being pinned). Dropping where the pair already sits changes nothing.
    public mutating func placeSplit(_ id: UUID, in section: SidebarSection, at index: Int) throws {
        try transact { draft in
            guard draft.canPlaceSplit(id, in: section),
                  let split = draft.currentWorkspace.splits.first(where: { $0.id == id }) else {
                throw BrowserStateError.invalidSplit
            }
            let rows = draft.sidebarRows()[section] ?? []
            let anchor = draft.modelPosition(forDisplayedRow: index, in: rows).map { draft.sidebarEntries(in: section)[$0].id }
            if let anchor, split.contains(anchor) { return }
            let workspace = draft.currentWorkspaceIndex
            let local = draft.workspaces[workspace].pins + draft.workspaces[workspace].tabs
            guard var left = local.first(where: { $0.id == split.leftEntryID }),
                  var right = local.first(where: { $0.id == split.rightEntryID }) else {
                throw BrowserStateError.invalidSplit
            }
            draft.detachFromSidebar([left.id, right.id])
            let kind: EntryKind = section == .tabs ? .temporary : .pinned
            for index in [0, 1] {
                var entry = index == 0 ? left : right
                entry.kind = kind
                entry.savedURL = kind == .temporary ? nil : (entry.savedURL ?? entry.lastURL)
                if index == 0 { left = entry } else { right = entry }
            }
            if kind == .temporary, let at = draft.workspaces[workspace].splits.firstIndex(where: { $0.id == id }) {
                draft.workspaces[workspace].splits[at].isPinned = false
            }
            let list = draft.sidebarEntries(in: section)
            let position = anchor.flatMap { id in list.firstIndex { $0.id == id } } ?? list.count
            try draft.insertIntoSidebar([left, right], section: section, at: position)
        }
    }

    mutating func detachFromSidebar(_ ids: [UUID]) {
        let workspace = currentWorkspaceIndex
        let profile = currentProfileIndex
        profiles[profile].favorites.removeAll { ids.contains($0.id) }
        workspaces[workspace].pins.removeAll { ids.contains($0.id) }
        for folder in workspaces[workspace].folders.indices {
            workspaces[workspace].folders[folder].pinIDs.removeAll { ids.contains($0) }
        }
        workspaces[workspace].tabs.removeAll { ids.contains($0.id) }
    }

    /// Inserts already-detached entries, in order, at `position` of the section's list as it now stands.
    mutating func insertIntoSidebar(_ entries: [PageEntry], section: SidebarSection, at position: Int) throws {
        let workspace = currentWorkspaceIndex
        let profile = currentProfileIndex
        switch section {
        case .favorites:
            profiles[profile].favorites.insert(contentsOf: entries, at: min(position, profiles[profile].favorites.count))
        case .tabs:
            workspaces[workspace].tabs.insert(contentsOf: entries, at: min(position, workspaces[workspace].tabs.count))
        case .pinned(let folder?):
            let target = try currentFolderIndex(folder)
            let count = workspaces[workspace].folders[target].pinIDs.count
            workspaces[workspace].folders[target].pinIDs.insert(contentsOf: entries.map(\.id), at: min(position, count))
            workspaces[workspace].pins.append(contentsOf: entries)
        case .pinned(nil):
            let unfiled = sidebarEntries(in: section)
            if position < unfiled.count,
               let anchor = workspaces[workspace].pins.firstIndex(where: { $0.id == unfiled[position].id }) {
                workspaces[workspace].pins.insert(contentsOf: entries, at: anchor)
            } else {
                workspaces[workspace].pins.append(contentsOf: entries)
            }
        }
    }

    public func canMoveSplit(_ id: UUID, toWorkspace destinationID: UUID) -> Bool {
        guard let destination = workspaces.first(where: { $0.id == destinationID }),
              destinationID != currentWorkspace.id, destination.profileID == currentWorkspace.profileID else { return false }
        return currentWorkspace.splits.contains { $0.id == id }
    }

    /// Transfers a pair and both members to another workspace of the same Profile without changing the active workspace.
    public mutating func moveSplit(_ id: UUID, toWorkspace destinationID: UUID) throws {
        try transact { draft in
            guard draft.canMoveSplit(id, toWorkspace: destinationID),
                  let destination = draft.workspaces.firstIndex(where: { $0.id == destinationID }) else {
                throw BrowserStateError.invalidSplit
            }
            let source = draft.currentWorkspaceIndex
            guard let split = draft.workspaces[source].splits.first(where: { $0.id == id }) else { throw BrowserStateError.invalidSplit }
            let moving = (draft.workspaces[source].pins + draft.workspaces[source].tabs).filter { split.contains($0.id) }
            guard moving.count == 2 else { throw BrowserStateError.invalidSplit }
            draft.detachFromSidebar(moving.map(\.id))
            draft.workspaces[source].splits.removeAll { $0.id == id }
            if draft.workspaces[source].activeSplitID == id { draft.workspaces[source].activeSplitID = nil }
            if let active = draft.workspaces[source].activeEntryID, split.contains(active) {
                draft.workspaces[source].activeEntryID = nil
            }
            for entry in moving {
                if entry.kind == .pinned { draft.workspaces[destination].pins.append(entry) }
                else { draft.workspaces[destination].tabs.append(entry) }
            }
            draft.workspaces[destination].splits.append(split)
        }
    }

    /// Exchanges the panes; the divider keeps each page's share of the space.
    public mutating func swapSplitSides(_ id: UUID) throws {
        try transact { draft in
            guard let index = draft.currentWorkspace.splits.firstIndex(where: { $0.id == id }) else {
                throw BrowserStateError.invalidSplit
            }
            let workspace = draft.currentWorkspaceIndex
            let pair = draft.workspaces[workspace].splits[index]
            draft.workspaces[workspace].splits[index].leftEntryID = pair.rightEntryID
            draft.workspaces[workspace].splits[index].rightEntryID = pair.leftEntryID
            draft.workspaces[workspace].splits[index].dividerRatio = 1 - pair.dividerRatio
        }
    }

    public mutating func setSplitOrientation(_ id: UUID, to orientation: SplitOrientation) throws {
        try transact { draft in
            guard let index = draft.currentWorkspace.splits.firstIndex(where: { $0.id == id }) else {
                throw BrowserStateError.invalidSplit
            }
            draft.workspaces[draft.currentWorkspaceIndex].splits[index].orientation = orientation
        }
    }
}
