import Foundation

public enum WorkspaceMoveDirection: Sendable {
    case up, down
}

public enum FolderMoveDirection: Equatable, Sendable {
    case up, down
}

public enum EntryMoveDirection: Sendable {
    case up, down
}

public enum EntryKind: String, Codable, Sendable {
    case favorite, pinned, temporary
}

public struct PageEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var savedURL: URL?
    public var lastURL: URL
    public var kind: EntryKind

    public init(id: UUID = UUID(), title: String, savedURL: URL? = nil, lastURL: URL, kind: EntryKind) {
        self.id = id
        self.title = title
        self.savedURL = savedURL
        self.lastURL = lastURL
        self.kind = kind
    }
}

/// A transient organization search result; engine-loaded state stays in the runtime.
public struct PageSearchResult: Identifiable, Equatable, Sendable {
    public var id: UUID { entryID }
    public let entryID: UUID
    public let workspaceID: UUID
    public let workspaceName: String
    public let entry: PageEntry

    public init(entryID: UUID, workspaceID: UUID, workspaceName: String, entry: PageEntry) {
        self.entryID = entryID
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
        self.entry = entry
    }
}

public struct BrowserProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var favorites: [PageEntry]

    public init(id: UUID = UUID(), name: String, favorites: [PageEntry] = []) {
        self.id = id
        self.name = name
        self.favorites = favorites
    }
}

/// Ordered organization metadata. The complete saved entries remain in Workspace.pins.
public struct PageFolder: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var isCollapsed: Bool
    public var pinIDs: [UUID]

    public init(id: UUID = UUID(), name: String, isCollapsed: Bool = false, pinIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.isCollapsed = isCollapsed
        self.pinIDs = pinIDs
    }
}

/// Stable organization references; Chromium split identifiers are never persisted.
public struct PageSplit: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var leftEntryID: UUID
    public var rightEntryID: UUID
    public var dividerRatio: Double
    public var isPinned: Bool

    public init(id: UUID = UUID(), leftEntryID: UUID, rightEntryID: UUID,
                dividerRatio: Double = 0.5, isPinned: Bool = false) {
        self.id = id
        self.leftEntryID = leftEntryID
        self.rightEntryID = rightEntryID
        self.dividerRatio = dividerRatio
        self.isPinned = isPinned
    }

    public func contains(_ id: UUID) -> Bool { leftEntryID == id || rightEntryID == id }
}

public struct Workspace: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var profileID: UUID
    public var name: String
    public var color: String
    public var pins: [PageEntry]
    public var folders: [PageFolder]
    public var tabs: [PageEntry]
    public var activeEntryID: UUID?
    public var splits: [PageSplit]
    public var activeSplitID: UUID?

    public init(id: UUID = UUID(), profileID: UUID, name: String, color: String = "#B47879", pins: [PageEntry] = [], folders: [PageFolder] = [], tabs: [PageEntry] = [], activeEntryID: UUID? = nil, splits: [PageSplit] = [], activeSplitID: UUID? = nil) {
        self.id = id
        self.profileID = profileID
        self.name = name
        self.color = color
        self.pins = pins
        self.folders = folders
        self.tabs = tabs
        self.activeEntryID = activeEntryID
        self.splits = splits
        self.activeSplitID = activeSplitID
    }

    public func folder(containingPin id: UUID) -> PageFolder? {
        folders.first { $0.pinIDs.contains(id) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, profileID, name, color, pins, folders, tabs, activeEntryID, splits, activeSplitID
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        profileID = try values.decode(UUID.self, forKey: .profileID)
        name = try values.decode(String.self, forKey: .name)
        color = try values.decode(String.self, forKey: .color)
        pins = try values.decode([PageEntry].self, forKey: .pins)
        folders = try values.decodeIfPresent([PageFolder].self, forKey: .folders) ?? []
        tabs = try values.decode([PageEntry].self, forKey: .tabs)
        splits = try values.decodeIfPresent([PageSplit].self, forKey: .splits) ?? []
        activeSplitID = try values.decodeIfPresent(UUID.self, forKey: .activeSplitID)
        activeEntryID = try values.decodeIfPresent(UUID.self, forKey: .activeEntryID)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(profileID, forKey: .profileID)
        try values.encode(name, forKey: .name)
        try values.encode(color, forKey: .color)
        try values.encode(pins, forKey: .pins)
        // Older documents have no folder field. Empty metadata keeps their shape.
        if !folders.isEmpty { try values.encode(folders, forKey: .folders) }
        try values.encode(tabs, forKey: .tabs)
        if !splits.isEmpty { try values.encode(splits, forKey: .splits) }
        try values.encodeIfPresent(activeSplitID, forKey: .activeSplitID)
        try values.encodeIfPresent(activeEntryID, forKey: .activeEntryID)
    }
}

public enum BrowserStateError: Error, Equatable, LocalizedError {
    case unsupportedVersion(Int)
    case emptyName
    case invalidURL
    case invalidColor
    case duplicateIdentity
    case missingProfile
    case missingWorkspace
    case invalidEntryOwnership
    case invalidSavedURL
    case missingEntry
    case invalidSelection
    case missingFolder
    case invalidFolder
    case invalidSplit

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "This organization was saved by an unsupported version of Bato."
        case .emptyName: "Profiles and workspaces need a name."
        case .invalidURL: "Enter a complete HTTP or HTTPS address."
        case .invalidColor: "The workspace color must be a six-digit hex color."
        case .duplicateIdentity: "The organization contains duplicate identifiers."
        case .missingProfile: "The workspace's Profile could not be found."
        case .missingWorkspace: "The selected workspace could not be found."
        case .invalidEntryOwnership: "A page is stored in the wrong sidebar section."
        case .invalidSavedURL: "The saved page destination is invalid."
        case .missingEntry: "The selected page could not be found."
        case .invalidSelection: "The selected page does not belong to this workspace or its Profile."
        case .missingFolder: "The selected folder could not be found."
        case .invalidSplit: "Choose two distinct workspace pages and a divider ratio greater than zero and less than one."
        case .invalidFolder: "Folders need a name of 1–80 characters and unique pins from their workspace."
        }
    }
}

/// Organization only. Live engine pages and their loaded/unloaded state belong to the runtime adapter.
public struct BrowserState: Codable, Equatable, Sendable {
    public var version: Int
    public var profiles: [BrowserProfile]
    public var workspaces: [Workspace]
    public var activeWorkspaceID: UUID

    public init(version: Int = 1, profiles: [BrowserProfile], workspaces: [Workspace], activeWorkspaceID: UUID) {
        self.version = version
        self.profiles = profiles
        self.workspaces = workspaces
        self.activeWorkspaceID = activeWorkspaceID
    }

    public static func initial() -> BrowserState {
        let profile = BrowserProfile(name: "Personal")
        let workspace = Workspace(profileID: profile.id, name: "Personal")
        return BrowserState(profiles: [profile], workspaces: [workspace], activeWorkspaceID: workspace.id)
    }

    /// Use only after validation, including immediately after decoding persisted state.
    public var currentWorkspace: Workspace {
        guard let workspace = workspaces.first(where: { $0.id == activeWorkspaceID }) else {
            preconditionFailure("Validate BrowserState before accessing its current workspace")
        }
        return workspace
    }

    public var currentSplit: PageSplit? {
        currentWorkspace.splits.first { $0.id == currentWorkspace.activeSplitID }
    }

    public func split(containingEntry id: UUID) -> PageSplit? {
        currentWorkspace.splits.first { $0.contains(id) }
    }

    public func canCreateSplit(with id: UUID) -> Bool {
        guard let focused = currentWorkspace.activeEntryID, focused != id else { return false }
        let ids = Set((currentWorkspace.pins + currentWorkspace.tabs).map(\.id))
        return ids.contains(focused) && ids.contains(id)
            && split(containingEntry: focused) == nil && split(containingEntry: id) == nil
    }

    public var visibleEntries: [PageEntry] {
        let workspace = currentWorkspace
        let favorites = profiles.first(where: { $0.id == workspace.profileID })?.favorites ?? []
        return favorites + workspace.pins + workspace.tabs
    }

    /// Search the current Profile without loading pages or duplicating shared Favorites.
    public func searchPages(matching query: String) -> [PageSearchResult] {
        let current = currentWorkspace
        let favorites = profiles.first(where: { $0.id == current.profileID })?.favorites ?? []
        var results = favorites.map {
            PageSearchResult(entryID: $0.id, workspaceID: current.id, workspaceName: current.name, entry: $0)
        }
        for workspace in workspaces where workspace.profileID == current.profileID {
            results += (workspace.pins + workspace.tabs).map {
                PageSearchResult(entryID: $0.id, workspaceID: workspace.id, workspaceName: workspace.name, entry: $0)
            }
        }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return results }
        return results.filter { result in
            [result.entry.title, result.entry.lastURL.absoluteString,
             result.entry.savedURL?.absoluteString ?? "", result.workspaceName].contains {
                $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    public func validate() throws {
        guard version == 1 else { throw BrowserStateError.unsupportedVersion(version) }
        var identities = Set<UUID>()
        func claim(_ id: UUID) throws {
            guard identities.insert(id).inserted else { throw BrowserStateError.duplicateIdentity }
        }
        func validateEntry(_ entry: PageEntry, kind: EntryKind) throws {
            try claim(entry.id)
            guard entry.kind == kind else { throw BrowserStateError.invalidEntryOwnership }
            try Self.validateURL(entry.lastURL)
            if kind == .temporary {
                guard entry.savedURL == nil else { throw BrowserStateError.invalidSavedURL }
            } else {
                guard let savedURL = entry.savedURL else { throw BrowserStateError.invalidSavedURL }
                try Self.validateURL(savedURL)
            }
        }
        for profile in profiles {
            try claim(profile.id)
            try Self.validateName(profile.name)
            for entry in profile.favorites { try validateEntry(entry, kind: .favorite) }
        }
        let profileIDs = Set(profiles.map(\.id))
        for workspace in workspaces {
            try claim(workspace.id)
            try Self.validateName(workspace.name)
            guard profileIDs.contains(workspace.profileID) else { throw BrowserStateError.missingProfile }
            guard workspace.color.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else {
                throw BrowserStateError.invalidColor
            }
            for entry in workspace.pins { try validateEntry(entry, kind: .pinned) }
            for entry in workspace.tabs { try validateEntry(entry, kind: .temporary) }
            let pinIDs = Set(workspace.pins.map(\.id))
            var filedPins = Set<UUID>()
            for folder in workspace.folders {
                try claim(folder.id)
                try Self.validateFolderName(folder.name)
                for id in folder.pinIDs {
                    guard pinIDs.contains(id), filedPins.insert(id).inserted else {
                        throw BrowserStateError.invalidFolder
                    }
                }
            }
            let localEntries = workspace.pins + workspace.tabs
            let localIDs = Set(localEntries.map(\.id))
            var splitMembers = Set<UUID>()
            for split in workspace.splits {
                try claim(split.id)
                guard split.leftEntryID != split.rightEntryID,
                      localIDs.contains(split.leftEntryID), localIDs.contains(split.rightEntryID),
                      splitMembers.insert(split.leftEntryID).inserted,
                      splitMembers.insert(split.rightEntryID).inserted,
                      split.dividerRatio.isFinite, split.dividerRatio > 0, split.dividerRatio < 1,
                      !split.isPinned || localEntries.filter({ split.contains($0.id) }).allSatisfy({ $0.kind == .pinned }) else {
                    throw BrowserStateError.invalidSplit
                }
            }
            if let activeSplit = workspace.activeSplitID {
                guard let split = workspace.splits.first(where: { $0.id == activeSplit }),
                      let focused = workspace.activeEntryID, split.contains(focused) else {
                    throw BrowserStateError.invalidSplit
                }
            }
            if let activeID = workspace.activeEntryID {
                let favorites = profiles.first(where: { $0.id == workspace.profileID })!.favorites
                guard (favorites + workspace.pins + workspace.tabs).contains(where: { $0.id == activeID }) else {
                    throw BrowserStateError.invalidSelection
                }
            }
        }
        guard workspaces.contains(where: { $0.id == activeWorkspaceID }) else {
            throw BrowserStateError.missingWorkspace
        }
    }

    @discardableResult
    public mutating func addProfile(name: String) throws -> UUID {
        try transact { draft in
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            try Self.validateName(name)
            let profile = BrowserProfile(name: name)
            draft.profiles.append(profile)
            return profile.id
        }
    }

    @discardableResult
    public mutating func addWorkspace(name: String, profileID: UUID) throws -> UUID {
        try transact { draft in
            guard draft.profiles.contains(where: { $0.id == profileID }) else { throw BrowserStateError.missingProfile }
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            try Self.validateName(name)
            let workspace = Workspace(profileID: profileID, name: name)
            draft.workspaces.append(workspace)
            return workspace.id
        }
    }

    public mutating func activateWorkspace(_ id: UUID) throws {
        try transact { draft in
            guard draft.workspaces.contains(where: { $0.id == id }) else { throw BrowserStateError.missingWorkspace }
            draft.activeWorkspaceID = id
        }
    }

    /// Switch workspace and page as one validated organization transaction.
    public mutating func activateEntry(_ id: UUID, inWorkspace workspaceID: UUID) throws {
        try transact { draft in
            guard let workspace = draft.workspaces.first(where: { $0.id == workspaceID }) else {
                throw BrowserStateError.missingWorkspace
            }
            guard workspace.profileID == draft.currentWorkspace.profileID else {
                throw BrowserStateError.invalidSelection
            }
            let favorites = draft.profiles.first(where: { $0.id == workspace.profileID })?.favorites ?? []
            guard (favorites + workspace.pins + workspace.tabs).contains(where: { $0.id == id }) else {
                throw BrowserStateError.missingEntry
            }
            draft.activeWorkspaceID = workspaceID
            draft.selectEntryInPlace(id)
        }
    }

    /// Edits organization metadata without changing ownership, order or selection.
    public mutating func updateWorkspace(_ id: UUID, name: String, color: String) throws {
        try transact { draft in
            guard let index = draft.workspaces.firstIndex(where: { $0.id == id }) else {
                throw BrowserStateError.missingWorkspace
            }
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            try Self.validateName(name)
            draft.workspaces[index].name = name
            draft.workspaces[index].color = color.uppercased()
        }
    }

    /// Workspace ordering is global; ownership and active selections stay unchanged.
    public func canMoveWorkspace(_ id: UUID, direction: WorkspaceMoveDirection) -> Bool {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return false }
        switch direction {
        case .up: return index > 0
        case .down: return index + 1 < workspaces.count
        }
    }

    public mutating func moveWorkspace(_ id: UUID, direction: WorkspaceMoveDirection) throws {
        try transact { draft in
            guard let index = draft.workspaces.firstIndex(where: { $0.id == id }) else {
                throw BrowserStateError.missingWorkspace
            }
            guard draft.canMoveWorkspace(id, direction: direction) else {
                throw BrowserStateError.invalidSelection
            }
            let destination: Int
            switch direction {
            case .up: destination = index - 1
            case .down: destination = index + 1
            }
            draft.workspaces.swapAt(index, destination)
        }
    }

    @discardableResult
    public mutating func createFolder(name: String) throws -> UUID {
        try transact { draft in
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            try Self.validateFolderName(name)
            let folder = PageFolder(name: name)
            draft.workspaces[draft.currentWorkspaceIndex].folders.append(folder)
            return folder.id
        }
    }

    public mutating func renameFolder(_ id: UUID, name: String) throws {
        try transact { draft in
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            try Self.validateFolderName(name)
            let index = try draft.currentFolderIndex(id)
            draft.workspaces[draft.currentWorkspaceIndex].folders[index].name = name
        }
    }

    public mutating func setFolderCollapsed(_ id: UUID, collapsed: Bool) throws {
        try transact { draft in
            let index = try draft.currentFolderIndex(id)
            draft.workspaces[draft.currentWorkspaceIndex].folders[index].isCollapsed = collapsed
        }
    }

    public func canMoveFolder(_ id: UUID, direction: FolderMoveDirection) -> Bool {
        guard let index = currentWorkspace.folders.firstIndex(where: { $0.id == id }) else { return false }
        switch direction {
        case .up: return index > 0
        case .down: return index + 1 < currentWorkspace.folders.count
        }
    }

    public mutating func moveFolder(_ id: UUID, direction: FolderMoveDirection) throws {
        try transact { draft in
            let index = try draft.currentFolderIndex(id)
            guard draft.canMoveFolder(id, direction: direction) else { throw BrowserStateError.invalidSelection }
            let next = direction == .up ? index - 1 : index + 1
            draft.workspaces[draft.currentWorkspaceIndex].folders.swapAt(index, next)
        }
    }

    /// Removes only the container. Pins retain their full value, selection and canonical order.
    public mutating func dissolveFolder(_ id: UUID) throws {
        try transact { draft in
            let index = try draft.currentFolderIndex(id)
            draft.workspaces[draft.currentWorkspaceIndex].folders.remove(at: index)
        }
    }

    /// Appends membership to the destination folder, or restores the pin to the unfiled group.
    public mutating func movePin(_ id: UUID, toFolder folderID: UUID?) throws {
        try transact { draft in
            let workspace = draft.currentWorkspaceIndex
            guard draft.workspaces[workspace].pins.contains(where: { $0.id == id }) else {
                throw BrowserStateError.missingEntry
            }
            let destination = try folderID.map { try draft.currentFolderIndex($0) }
            if draft.currentWorkspace.folder(containingPin: id)?.id == folderID { return }
            for index in draft.workspaces[workspace].folders.indices {
                draft.workspaces[workspace].folders[index].pinIDs.removeAll { $0 == id }
            }
            if let destination { draft.workspaces[workspace].folders[destination].pinIDs.append(id) }
        }
    }

    /// A supplied identity lets a future host adopt an existing live page without
    /// replacing its token. This only inserts organization metadata.
    @discardableResult
    public mutating func addTab(id: UUID = UUID(), url: URL, title: String) throws -> UUID {
        try transact { draft in
            try Self.validateURL(url)
            let entry = PageEntry(id: id, title: title, lastURL: url, kind: .temporary)
            let workspace = draft.currentWorkspaceIndex
            draft.workspaces[workspace].tabs.append(entry)
            // Claim the identity before selection can discard an active transient
            // split whose identifier must not be reused by the adopted page.
            try draft.validate()
            draft.selectEntryInPlace(entry.id)
            return entry.id
        }
    }

    public mutating func selectEntry(_ id: UUID) throws {
        try transact { draft in
            guard draft.visibleEntries.contains(where: { $0.id == id }) else { throw BrowserStateError.missingEntry }
            draft.selectEntryInPlace(id)
        }
    }

    /// Order changes stay inside the entry's current sidebar section.
    public func canMoveEntry(_ id: UUID, direction: EntryMoveDirection) -> Bool {
        guard let section = sectionContaining(id), let index = section.firstIndex(where: { $0.id == id }) else {
            return false
        }
        switch direction {
        case .up: return index > 0
        case .down: return index + 1 < section.count
        }
    }

    public mutating func moveEntry(_ id: UUID, direction: EntryMoveDirection) throws {
        try transact { draft in
            guard let entry = draft.visibleEntries.first(where: { $0.id == id }) else {
                throw BrowserStateError.missingEntry
            }
            guard draft.canMoveEntry(id, direction: direction),
                  let section = draft.sectionContaining(id),
                  let index = section.firstIndex(where: { $0.id == id }) else {
                throw BrowserStateError.invalidSelection
            }
            let destination: Int
            switch direction {
            case .up: destination = index - 1
            case .down: destination = index + 1
            }
            let workspace = draft.currentWorkspaceIndex
            switch entry.kind {
            case .favorite:
                let profile = draft.currentProfileIndex
                draft.profiles[profile].favorites.swapAt(index, destination)
            case .pinned:
                if let folder = draft.currentWorkspace.folder(containingPin: id),
                   let folderIndex = draft.workspaces[workspace].folders.firstIndex(where: { $0.id == folder.id }) {
                    draft.workspaces[workspace].folders[folderIndex].pinIDs.swapAt(index, destination)
                } else {
                    let first = draft.workspaces[workspace].pins.firstIndex(where: { $0.id == section[index].id })!
                    let second = draft.workspaces[workspace].pins.firstIndex(where: { $0.id == section[destination].id })!
                    draft.workspaces[workspace].pins.swapAt(first, second)
                }
            case .temporary:
                draft.workspaces[workspace].tabs.swapAt(index, destination)
            }
        }
    }

    /// Only local pins/tabs can move; Favorites already span their Profile's workspaces.
    public func canMoveEntry(_ id: UUID, toWorkspace destinationID: UUID) -> Bool {
        let source = currentWorkspace
        guard destinationID != source.id,
              let destination = workspaces.first(where: { $0.id == destinationID }),
              destination.profileID == source.profileID else { return false }
        return (source.pins + source.tabs).contains(where: { $0.id == id })
    }

    /// Transfers the entire entry without changing the active workspace or destination selection.
    public mutating func moveEntry(_ id: UUID, toWorkspace destinationID: UUID) throws {
        try transact { draft in
            guard let destination = draft.workspaces.firstIndex(where: { $0.id == destinationID }) else {
                throw BrowserStateError.missingWorkspace
            }
            let source = draft.currentWorkspaceIndex
            guard destination != source,
                  draft.workspaces[destination].profileID == draft.workspaces[source].profileID else {
                throw BrowserStateError.invalidSelection
            }
            guard let entry = draft.visibleEntries.first(where: { $0.id == id }) else {
                throw BrowserStateError.missingEntry
            }
            draft.removeSplits(containing: id)
            switch entry.kind {
            case .favorite:
                throw BrowserStateError.invalidEntryOwnership
            case .pinned:
                draft.workspaces[source].pins.removeAll { $0.id == id }
                for folder in draft.workspaces[source].folders.indices {
                    draft.workspaces[source].folders[folder].pinIDs.removeAll { $0 == id }
                }
                draft.workspaces[destination].pins.append(entry)
            case .temporary:
                draft.workspaces[source].tabs.removeAll { $0.id == id }
                draft.workspaces[destination].tabs.append(entry)
            }
            if draft.workspaces[source].activeEntryID == id {
                draft.workspaces[source].activeEntryID = nil
            }
        }
    }

    public mutating func pinEntry(_ id: UUID) throws {
        try transact { draft in
            guard var entry = draft.visibleEntries.first(where: { $0.id == id }) else { throw BrowserStateError.missingEntry }
            if entry.kind == .pinned { return }
            draft.removeEntry(id)
            entry.kind = .pinned
            entry.savedURL = entry.savedURL ?? entry.lastURL
            let workspace = draft.currentWorkspaceIndex
            draft.workspaces[workspace].pins.append(entry)
            draft.workspaces[workspace].activeEntryID = id
        }
    }

    public mutating func favoriteEntry(_ id: UUID) throws {
        try transact { draft in
            guard var entry = draft.visibleEntries.first(where: { $0.id == id }) else { throw BrowserStateError.missingEntry }
            if entry.kind == .favorite { return }
            draft.removeEntry(id)
            entry.kind = .favorite
            entry.savedURL = entry.savedURL ?? entry.lastURL
            let profile = draft.currentProfileIndex
            draft.profiles[profile].favorites.append(entry)
            draft.workspaces[draft.currentWorkspaceIndex].activeEntryID = id
        }
    }

    /// Removes saved status without closing the page or replacing its identity.
    /// Profile-wide Favorites become local to the current workspace.
    public mutating func makeTemporary(_ id: UUID) throws {
        try transact { draft in
            guard var entry = draft.visibleEntries.first(where: { $0.id == id }) else {
                throw BrowserStateError.missingEntry
            }
            guard entry.kind != .temporary else { throw BrowserStateError.invalidEntryOwnership }
            let selected = draft.currentWorkspace.activeEntryID
            draft.removeEntry(id)
            entry.kind = .temporary
            entry.savedURL = nil
            let workspace = draft.currentWorkspaceIndex
            draft.workspaces[workspace].tabs.append(entry)
            draft.workspaces[workspace].activeEntryID = selected
        }
    }

    /// Explicitly adopts the latest committed destination for a visible saved page.
    /// Ordinary navigation continues to leave its saved destination untouched.
    public mutating func updateSavedURL(_ id: UUID) throws {
        try transact { draft in
            guard let entry = draft.visibleEntries.first(where: { $0.id == id }) else {
                throw BrowserStateError.missingEntry
            }
            guard entry.kind != .temporary else { throw BrowserStateError.invalidSavedURL }
            draft.updateEntry(id) { $0.savedURL = entry.lastURL }
        }
    }

    /// Closing saved entries keeps their identity/order and restores their saved destination for reopening.
    public mutating func closeEntry(_ id: UUID) throws {
        try transact { draft in
            guard let entry = draft.visibleEntries.first(where: { $0.id == id }) else { throw BrowserStateError.missingEntry }
            if entry.kind == .temporary {
                draft.removeEntry(id)
            } else {
                if let pair = draft.currentSplit, pair.contains(id) {
                    draft.workspaces[draft.currentWorkspaceIndex].activeSplitID = nil
                    if !pair.isPinned {
                        draft.workspaces[draft.currentWorkspaceIndex].splits.removeAll { $0.id == pair.id }
                    }
                    draft.workspaces[draft.currentWorkspaceIndex].activeEntryID = pair.leftEntryID == id ? pair.rightEntryID : pair.leftEntryID
                }
                draft.updateEntry(id) { $0.lastURL = $0.savedURL! }
                draft.clearSelections(id)
            }
        }
    }

    /// Engine callbacks may update an entry in an inactive workspace without changing selection.
    public mutating func recordNavigation(entryID: UUID, url: URL, title: String) throws {
        try transact { draft in
            try Self.validateURL(url)
            guard draft.allEntries.contains(where: { $0.id == entryID }) else { throw BrowserStateError.missingEntry }
            draft.updateEntry(entryID) { entry in
                entry.lastURL = url
                entry.title = title
            }
        }
    }

    @discardableResult
    public mutating func createSplit(with id: UUID) throws -> UUID {
        try transact { draft in
            guard draft.canCreateSplit(with: id), let focused = draft.currentWorkspace.activeEntryID else {
                throw BrowserStateError.invalidSplit
            }
            let split = PageSplit(leftEntryID: focused, rightEntryID: id)
            let index = draft.currentWorkspaceIndex
            draft.workspaces[index].splits.append(split)
            draft.workspaces[index].activeSplitID = split.id
            return split.id
        }
    }

    public mutating func activateSplit(_ id: UUID, focusedEntryID: UUID? = nil) throws {
        try transact { draft in
            guard let split = draft.currentWorkspace.splits.first(where: { $0.id == id }) else {
                throw BrowserStateError.invalidSplit
            }
            let focused = focusedEntryID ?? split.leftEntryID
            guard split.contains(focused) else { throw BrowserStateError.invalidSplit }
            if let previous = draft.currentSplit, previous.id != id, !previous.isPinned {
                draft.workspaces[draft.currentWorkspaceIndex].splits.removeAll { $0.id == previous.id }
            }
            draft.workspaces[draft.currentWorkspaceIndex].activeSplitID = id
            draft.workspaces[draft.currentWorkspaceIndex].activeEntryID = focused
        }
    }

    public mutating func deactivateSplit() throws {
        try transact { draft in
            let index = draft.currentWorkspaceIndex
            if let pair = draft.currentSplit, !pair.isPinned {
                draft.workspaces[index].splits.removeAll { $0.id == pair.id }
            }
            draft.workspaces[index].activeSplitID = nil
        }
    }

    public mutating func dissolveSplit(_ id: UUID) throws {
        try transact { draft in
            guard draft.currentWorkspace.splits.contains(where: { $0.id == id }) else { throw BrowserStateError.invalidSplit }
            let index = draft.currentWorkspaceIndex
            draft.workspaces[index].splits.removeAll { $0.id == id }
            if draft.workspaces[index].activeSplitID == id { draft.workspaces[index].activeSplitID = nil }
        }
    }

    public mutating func pinSplit(_ id: UUID) throws {
        try transact { draft in
            guard let splitIndex = draft.currentWorkspace.splits.firstIndex(where: { $0.id == id }) else {
                throw BrowserStateError.invalidSplit
            }
            let index = draft.currentWorkspaceIndex
            let pair = draft.workspaces[index].splits[splitIndex]
            for entryID in [pair.leftEntryID, pair.rightEntryID] {
                if let tab = draft.workspaces[index].tabs.firstIndex(where: { $0.id == entryID }) {
                    var entry = draft.workspaces[index].tabs.remove(at: tab)
                    entry.kind = .pinned
                    entry.savedURL = entry.lastURL
                    draft.workspaces[index].pins.append(entry)
                }
            }
            draft.workspaces[index].splits[splitIndex].isPinned = true
        }
    }

    public mutating func updateSplitRatio(_ id: UUID, ratio: Double) throws {
        try transact { draft in
            guard let index = draft.currentWorkspace.splits.firstIndex(where: { $0.id == id }),
                  ratio.isFinite, ratio > 0, ratio < 1 else { throw BrowserStateError.invalidSplit }
            draft.workspaces[draft.currentWorkspaceIndex].splits[index].dividerRatio = ratio
        }
    }

    private mutating func selectEntryInPlace(_ id: UUID) {
        let index = currentWorkspaceIndex
        if currentSplit?.contains(id) != true {
            if let pair = currentSplit, !pair.isPinned {
                workspaces[index].splits.removeAll { $0.id == pair.id }
            }
            workspaces[index].activeSplitID = nil
        }
        workspaces[index].activeEntryID = id
    }

    /// Removing a side leaves the other page selected when this pair was displayed.
    private mutating func removeSplits(containing id: UUID) {
        for index in workspaces.indices {
            if let pair = workspaces[index].splits.first(where: { $0.id == workspaces[index].activeSplitID && $0.contains(id) }) {
                workspaces[index].activeSplitID = nil
                workspaces[index].activeEntryID = pair.leftEntryID == id ? pair.rightEntryID : pair.leftEntryID
            }
            workspaces[index].splits.removeAll { $0.contains(id) }
        }
    }

    private func sectionContaining(_ id: UUID) -> [PageEntry]? {
        let workspace = currentWorkspace
        let favorites = profiles[currentProfileIndex].favorites
        if favorites.contains(where: { $0.id == id }) { return favorites }
        if workspace.pins.contains(where: { $0.id == id }) {
            if let folder = workspace.folder(containingPin: id) {
                return folder.pinIDs.compactMap { pinID in workspace.pins.first { $0.id == pinID } }
            }
            let filedIDs = Set(workspace.folders.flatMap(\.pinIDs))
            return workspace.pins.filter { !filedIDs.contains($0.id) }
        }
        if workspace.tabs.contains(where: { $0.id == id }) { return workspace.tabs }
        return nil
    }

    private var currentWorkspaceIndex: Int { workspaces.firstIndex(where: { $0.id == activeWorkspaceID })! }
    private var currentProfileIndex: Int { profiles.firstIndex(where: { $0.id == currentWorkspace.profileID })! }
    private var allEntries: [PageEntry] { profiles.flatMap(\.favorites) + workspaces.flatMap { $0.pins + $0.tabs } }

    private mutating func transact<T>(_ mutation: (inout BrowserState) throws -> T) throws -> T {
        try validate()
        var draft = self
        let result = try mutation(&draft)
        try draft.validate()
        self = draft
        return result
    }

    private mutating func clearSelections(_ id: UUID) {
        for index in workspaces.indices where workspaces[index].activeEntryID == id {
            workspaces[index].activeEntryID = nil
        }
    }

    private mutating func removeEntry(_ id: UUID) {
        removeSplits(containing: id)
        for index in profiles.indices { profiles[index].favorites.removeAll { $0.id == id } }
        for index in workspaces.indices {
            workspaces[index].pins.removeAll { $0.id == id }
            for folder in workspaces[index].folders.indices {
                workspaces[index].folders[folder].pinIDs.removeAll { $0 == id }
            }
            workspaces[index].tabs.removeAll { $0.id == id }
        }
        clearSelections(id)
    }

    private mutating func updateEntry(_ id: UUID, _ update: (inout PageEntry) -> Void) {
        for profile in profiles.indices {
            for entry in profiles[profile].favorites.indices where profiles[profile].favorites[entry].id == id {
                update(&profiles[profile].favorites[entry])
            }
        }
        for workspace in workspaces.indices {
            for entry in workspaces[workspace].pins.indices where workspaces[workspace].pins[entry].id == id {
                update(&workspaces[workspace].pins[entry])
            }
            for entry in workspaces[workspace].tabs.indices where workspaces[workspace].tabs[entry].id == id {
                update(&workspaces[workspace].tabs[entry])
            }
        }
    }

    private func currentFolderIndex(_ id: UUID) throws -> Int {
        guard let index = currentWorkspace.folders.firstIndex(where: { $0.id == id }) else {
            throw BrowserStateError.missingFolder
        }
        return index
    }

    private static func validateFolderName(_ name: String) throws {
        guard !name.isEmpty, name.count <= 80,
              name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw BrowserStateError.invalidFolder
        }
    }

    private static func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BrowserStateError.emptyName }
    }

    private static func validateURL(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { throw BrowserStateError.invalidURL }
    }
}
