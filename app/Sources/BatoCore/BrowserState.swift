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
    /// When a temporary tab was last known to be in use; set only while its workspace archives idle tabs.
    public var lastActiveAt: Date?

    public init(id: UUID = UUID(), title: String, savedURL: URL? = nil, lastURL: URL, kind: EntryKind,
                lastActiveAt: Date? = nil) {
        self.id = id
        self.title = title
        self.savedURL = savedURL
        self.lastURL = lastURL
        self.kind = kind
        self.lastActiveAt = lastActiveAt
    }
}

/// A transient organization search result; engine-loaded state stays in the runtime.
/// A temporary tab that was closed, with where it sat so reopening can put it back.
public struct ClosedTab: Equatable, Sendable, Codable {
    public var profileID: UUID
    public var workspaceID: UUID
    public var title: String
    public var url: URL
    public var index: Int

    public init(profileID: UUID, workspaceID: UUID, title: String, url: URL, index: Int) {
        self.profileID = profileID
        self.workspaceID = workspaceID
        self.title = title
        self.url = url
        self.index = index
    }
}

/// The last closed tab comes out first. Past the capacity the oldest is dropped.
public struct ClosedTabStack: Equatable, Sendable, Codable {
    public static let capacity = 25
    public private(set) var tabs: [ClosedTab] = []

    public init() {}

    /// Oldest first, as stored; keeps only the newest `capacity` tabs.
    public init(tabs: [ClosedTab]) {
        self.tabs = Array(tabs.suffix(Self.capacity))
    }

    public var last: ClosedTab? { tabs.last }

    /// The `offset`-th most recently closed tab, 0 being the newest.
    public func closed(at offset: Int) -> ClosedTab? {
        offset >= 0 && offset < tabs.count ? tabs[tabs.count - 1 - offset] : nil
    }

    @discardableResult
    public mutating func remove(at offset: Int) -> ClosedTab? {
        guard offset >= 0, offset < tabs.count else { return nil }
        return tabs.remove(at: tabs.count - 1 - offset)
    }
    public var isEmpty: Bool { tabs.isEmpty }

    public mutating func removeTabs(inWorkspace id: UUID) { tabs.removeAll { $0.workspaceID == id } }

    public mutating func push(_ tab: ClosedTab) {
        tabs.append(tab)
        if tabs.count > Self.capacity { tabs.removeFirst(tabs.count - Self.capacity) }
    }

    @discardableResult
    public mutating func pop() -> ClosedTab? { tabs.popLast() }
}

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
    /// Badge color in the switcher. Absent in documents saved before Profiles could be colored.
    public var color: String?

    public init(id: UUID = UUID(), name: String, favorites: [PageEntry] = [], color: String? = nil) {
        self.id = id
        self.name = name
        self.favorites = favorites
        self.color = color
    }
}

/// One switcher section: a Profile and its workspaces in global workspace order.
public struct ProfileGroup: Equatable, Sendable {
    public var profile: BrowserProfile
    public var isLaunch: Bool
    public var workspaces: [Workspace]
}

/// Ordered organization metadata. The complete saved entries remain in Workspace.pins.
/// Workspace.folders is flat: a folder's subfolders are the entries naming it as `parentID`,
/// ordered by their position in that array. A folder lists its pins before its subfolders.
public struct PageFolder: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var isCollapsed: Bool
    public var pinIDs: [UUID]
    public var parentID: UUID?

    public init(id: UUID = UUID(), name: String, isCollapsed: Bool = false, pinIDs: [UUID] = [], parentID: UUID? = nil) {
        self.id = id
        self.name = name
        self.isCollapsed = isCollapsed
        self.pinIDs = pinIDs
        self.parentID = parentID
    }
}

/// How a pair's two panes are arranged. The first member is the left or top pane.
public enum SplitOrientation: String, Codable, Equatable, Sendable {
    case horizontal, vertical
}

/// Where a new pane opens relative to the page it splits from.
public enum SplitSide: String, CaseIterable, Sendable {
    case right, left, top, bottom

    public var orientation: SplitOrientation { self == .left || self == .right ? .horizontal : .vertical }
    /// True when the new page becomes the left or top member.
    public var newPageIsFirst: Bool { self == .left || self == .top }
    public var title: String {
        switch self {
        case .right: "Add Right Split"
        case .left: "Add Left Split"
        case .top: "Add Top Split"
        case .bottom: "Add Bottom Split"
        }
    }
    public var symbolName: String {
        switch self {
        case .right: "rectangle.righthalf.inset.filled"
        case .left: "rectangle.lefthalf.inset.filled"
        case .top: "rectangle.tophalf.inset.filled"
        case .bottom: "rectangle.bottomhalf.inset.filled"
        }
    }
}

/// Stable organization references; Chromium split identifiers are never persisted.
/// `leftEntryID` and `rightEntryID` are the first (left or top) and second (right or bottom) pane.
public struct PageSplit: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var leftEntryID: UUID
    public var rightEntryID: UUID
    public var dividerRatio: Double
    public var isPinned: Bool
    public var orientation: SplitOrientation

    public init(id: UUID = UUID(), leftEntryID: UUID, rightEntryID: UUID,
                dividerRatio: Double = 0.5, isPinned: Bool = false,
                orientation: SplitOrientation = .horizontal) {
        self.id = id
        self.leftEntryID = leftEntryID
        self.rightEntryID = rightEntryID
        self.dividerRatio = dividerRatio
        self.isPinned = isPinned
        self.orientation = orientation
    }

    private enum CodingKeys: String, CodingKey {
        case id, leftEntryID, rightEntryID, dividerRatio, isPinned, orientation
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        leftEntryID = try values.decode(UUID.self, forKey: .leftEntryID)
        rightEntryID = try values.decode(UUID.self, forKey: .rightEntryID)
        dividerRatio = try values.decode(Double.self, forKey: .dividerRatio)
        isPinned = try values.decode(Bool.self, forKey: .isPinned)
        orientation = try values.decodeIfPresent(SplitOrientation.self, forKey: .orientation) ?? .horizontal
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(leftEntryID, forKey: .leftEntryID)
        try values.encode(rightEntryID, forKey: .rightEntryID)
        try values.encode(dividerRatio, forKey: .dividerRatio)
        try values.encode(isPinned, forKey: .isPinned)
        if orientation != .horizontal { try values.encode(orientation, forKey: .orientation) }
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
    /// Overrides the global archive period for this workspace.
    public var archivePeriod: ArchivePeriod?

    public init(id: UUID = UUID(), profileID: UUID, name: String, color: String = "#B47879", pins: [PageEntry] = [], folders: [PageFolder] = [], tabs: [PageEntry] = [], activeEntryID: UUID? = nil, splits: [PageSplit] = [], activeSplitID: UUID? = nil, archivePeriod: ArchivePeriod? = nil) {
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
        self.archivePeriod = archivePeriod
    }

    public func folder(containingPin id: UUID) -> PageFolder? {
        folders.first { $0.pinIDs.contains(id) }
    }

    public func folder(_ id: UUID) -> PageFolder? {
        folders.first { $0.id == id }
    }

    /// Direct subfolders in display order; `nil` lists the workspace's top-level folders.
    public func subfolders(of parentID: UUID?) -> [PageFolder] {
        folders.filter { $0.parentID == parentID }
    }

    /// One for a top-level folder. Nil for an unknown folder or a broken parent chain.
    public func depth(ofFolder id: UUID) -> Int? {
        var depth = 0
        var current: UUID? = id
        while let folderID = current {
            guard depth < folders.count, let folder = folder(folderID) else { return nil }
            depth += 1
            current = folder.parentID
        }
        return depth
    }

    public func descendantFolderIDs(of id: UUID) -> Set<UUID> {
        var found = Set<UUID>()
        var pending = [id]
        while let next = pending.popLast() {
            for child in subfolders(of: next) where found.insert(child.id).inserted { pending.append(child.id) }
        }
        return found
    }

    /// Every folder in sidebar order, each after its parent, with its depth (one for top level).
    public func folderOutline(under parentID: UUID? = nil, depth: Int = 1) -> [(folder: PageFolder, depth: Int)] {
        subfolders(of: parentID).flatMap { [($0, depth)] + folderOutline(under: $0.id, depth: depth + 1) }
    }

    /// Levels in the folder's own subtree, counting the folder itself.
    public func subtreeHeight(ofFolder id: UUID) -> Int {
        1 + (subfolders(of: id).map { subtreeHeight(ofFolder: $0.id) }.max() ?? 0)
    }

    /// Pins in the folder and all of its descendants.
    public func pinCount(inFolder id: UUID) -> Int {
        (folder(id)?.pinIDs.count ?? 0) + subfolders(of: id).reduce(0) { $0 + pinCount(inFolder: $1.id) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, profileID, name, color, pins, folders, tabs, activeEntryID, splits, activeSplitID, archivePeriod
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
        archivePeriod = try values.decodeIfPresent(ArchivePeriod.self, forKey: .archivePeriod)
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
        try values.encodeIfPresent(archivePeriod, forKey: .archivePeriod)
    }
}

public enum BrowserStateError: Error, Equatable, LocalizedError {
    case unsupportedVersion(Int)
    case emptyName
    case invalidURL
    case invalidColor
    case duplicateIdentity
    case missingProfile
    case duplicateProfileName
    case launchProfileProtected
    case lastWorkspaceInProfile
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
        case .duplicateProfileName: "Another Profile already has that name."
        case .launchProfileProtected: "The Profile Bato started with cannot be deleted."
        case .lastWorkspaceInProfile: "A Profile keeps at least one workspace."
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
    public var archive = ArchiveState()

    /// Version 3 added the archive. Documents that never use it keep their version and bytes.
    public static let archiveVersion = 3

    private enum CodingKeys: String, CodingKey {
        case version, profiles, workspaces, activeWorkspaceID, archive
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        profiles = try values.decode([BrowserProfile].self, forKey: .profiles)
        workspaces = try values.decode([Workspace].self, forKey: .workspaces)
        activeWorkspaceID = try values.decode(UUID.self, forKey: .activeWorkspaceID)
        archive = try values.decodeIfPresent(ArchiveState.self, forKey: .archive) ?? ArchiveState()
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encode(profiles, forKey: .profiles)
        try values.encode(workspaces, forKey: .workspaces)
        try values.encode(activeWorkspaceID, forKey: .activeWorkspaceID)
        if !archive.isDefault { try values.encode(archive, forKey: .archive) }
    }

    /// Folders are at most this many levels deep, so indentation fits the 220-point minimum sidebar.
    public static let maxFolderDepth = 4

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

    /// The Profile whose data lives in the engine's original context. Profiles are only ever appended,
    /// so the first one stays the same whichever workspace was selected when the app started.
    public var launchProfileID: UUID? { profiles.first?.id }

    /// Use only after validation, including immediately after decoding persisted state.
    public var currentWorkspace: Workspace {
        guard let workspace = workspaces.first(where: { $0.id == activeWorkspaceID }) else {
            preconditionFailure("Validate BrowserState before accessing its current workspace")
        }
        return workspace
    }

    /// No tab is selected, so the page area shows the empty card rather than any page.
    public var showsEmptySpace: Bool { currentWorkspace.activeEntryID == nil }

    public var currentSplit: PageSplit? {
        currentWorkspace.splits.first { $0.id == currentWorkspace.activeSplitID }
    }

    public func split(containingEntry id: UUID) -> PageSplit? {
        currentWorkspace.splits.first { $0.contains(id) }
    }

    /// The selected page is a pin or tab; a page already in a pair re-pairs with the new tab.
    public var canSplitSelection: Bool {
        guard let focused = currentWorkspace.activeEntryID else { return false }
        return (currentWorkspace.pins + currentWorkspace.tabs).contains { $0.id == focused }
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
        guard (1...Self.archiveVersion).contains(version) else { throw BrowserStateError.unsupportedVersion(version) }
        if version < Self.archiveVersion {
            let usesArchive = !archive.isDefault || workspaces.contains {
                $0.archivePeriod != nil || $0.tabs.contains { $0.lastActiveAt != nil }
            }
            guard !usesArchive else { throw BrowserStateError.unsupportedVersion(version) }
        }
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
            if let color = profile.color { try Self.validateColor(color) }
            for entry in profile.favorites { try validateEntry(entry, kind: .favorite) }
        }
        let profileIDs = Set(profiles.map(\.id))
        for workspace in workspaces {
            try claim(workspace.id)
            try Self.validateName(workspace.name)
            guard profileIDs.contains(workspace.profileID) else { throw BrowserStateError.missingProfile }
            try Self.validateColor(workspace.color)
            for entry in workspace.pins { try validateEntry(entry, kind: .pinned) }
            for entry in workspace.tabs { try validateEntry(entry, kind: .temporary) }
            let pinIDs = Set(workspace.pins.map(\.id))
            var filedPins = Set<UUID>()
            let folderIDs = Set(workspace.folders.map(\.id))
            for folder in workspace.folders {
                try claim(folder.id)
                try Self.validateFolderName(folder.name)
                if let parentID = folder.parentID {
                    guard version >= 2 else { throw BrowserStateError.unsupportedVersion(version) }
                    guard parentID != folder.id, folderIDs.contains(parentID) else { throw BrowserStateError.invalidFolder }
                }
                for id in folder.pinIDs {
                    guard pinIDs.contains(id), filedPins.insert(id).inserted else {
                        throw BrowserStateError.invalidFolder
                    }
                }
            }
            for folder in workspace.folders {
                guard let depth = workspace.depth(ofFolder: folder.id), depth <= Self.maxFolderDepth else {
                    throw BrowserStateError.invalidFolder
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
        for record in archive.records {
            try claim(record.id)
            guard profileIDs.contains(record.profileID) else { throw BrowserStateError.missingProfile }
            try Self.validateURL(record.url)
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

    /// Adds a Profile and its first workspace together; an invalid name or color leaves both absent.
    /// Selection is unchanged so callers choose whether to enter the new Profile.
    @discardableResult
    public mutating func createProfile(name: String, color: String, workspaceName: String) throws
        -> (profileID: UUID, workspaceID: UUID) {
        try transact { draft in
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let workspaceName = workspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
            try Self.validateName(name)
            try Self.validateName(workspaceName)
            try Self.validateColor(color)
            guard draft.isProfileNameAvailable(name) else { throw BrowserStateError.duplicateProfileName }
            let profile = BrowserProfile(name: name, color: color.uppercased())
            let workspace = Workspace(profileID: profile.id, name: workspaceName, color: color.uppercased())
            draft.profiles.append(profile)
            draft.workspaces.append(workspace)
            return (profile.id, workspace.id)
        }
    }

    /// Renaming never changes the Profile's identity, so its engine storage stays attached.
    public mutating func updateProfile(_ id: UUID, name: String, color: String) throws {
        try transact { draft in
            guard let index = draft.profiles.firstIndex(where: { $0.id == id }) else {
                throw BrowserStateError.missingProfile
            }
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            try Self.validateName(name)
            try Self.validateColor(color)
            guard draft.isProfileNameAvailable(name, excluding: id) else { throw BrowserStateError.duplicateProfileName }
            draft.profiles[index].name = name
            draft.profiles[index].color = color.uppercased()
        }
    }

    /// What deleting a Profile removes from the organization; engine data (history, logins) is separate.
    public struct ProfileLoss: Equatable, Sendable {
        public let workspaces: Int
        public let pages: Int
        public let favorites: Int
        public let archived: Int
    }

    public func lossOfDeleting(profile id: UUID) -> ProfileLoss? {
        guard let profile = profiles.first(where: { $0.id == id }) else { return nil }
        let owned = workspaces.filter { $0.profileID == id }
        return ProfileLoss(workspaces: owned.count, pages: owned.reduce(0) { $0 + $1.pins.count + $1.tabs.count },
                           favorites: profile.favorites.count, archived: archive.records(inProfile: id).count)
    }

    /// The launch Profile owns the engine's default storage and can never be deleted. Selection moves to the
    /// launch Profile's first workspace when the current one goes away.
    public mutating func deleteProfile(_ id: UUID) throws {
        try transact { draft in
            guard id != draft.launchProfileID else { throw BrowserStateError.launchProfileProtected }
            guard draft.profiles.contains(where: { $0.id == id }) else { throw BrowserStateError.missingProfile }
            let doomed = Set(draft.workspaces.filter { $0.profileID == id }.map(\.id))
            draft.profiles.removeAll { $0.id == id }
            draft.workspaces.removeAll { $0.profileID == id }
            draft.archive.records.removeAll { $0.profileID == id }
            if doomed.contains(draft.activeWorkspaceID) {
                guard let next = draft.workspaces.first(where: { $0.profileID == draft.launchProfileID }) ?? draft.workspaces.first else {
                    throw BrowserStateError.missingWorkspace
                }
                draft.activeWorkspaceID = next.id
            }
        }
    }

    public struct WorkspaceLoss: Equatable, Sendable {
        public let pages: Int
        public let archived: Int
    }

    public func lossOfDeleting(workspace id: UUID) -> WorkspaceLoss? {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return nil }
        return WorkspaceLoss(pages: workspace.pins.count + workspace.tabs.count,
                             archived: archive.records.filter { $0.workspaceID == id }.count)
    }

    /// A Profile always keeps one workspace, so the last one in each Profile is never offered for deletion.
    public func canDeleteWorkspace(_ id: UUID) -> Bool {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return false }
        return workspaces.filter { $0.profileID == workspace.profileID }.count > 1
    }

    /// Selection moves to the nearest remaining workspace of the same Profile when the current one goes away.
    public mutating func deleteWorkspace(_ id: UUID) throws {
        try transact { draft in
            guard let index = draft.workspaces.firstIndex(where: { $0.id == id }) else {
                throw BrowserStateError.missingWorkspace
            }
            let profileID = draft.workspaces[index].profileID
            guard draft.canDeleteWorkspace(id) else { throw BrowserStateError.lastWorkspaceInProfile }
            let siblings = draft.workspaces.enumerated().filter { $0.element.profileID == profileID && $0.element.id != id }
            draft.workspaces.remove(at: index)
            draft.archive.records.removeAll { $0.workspaceID == id }
            if draft.activeWorkspaceID == id {
                let nearest = siblings.first { $0.offset > index } ?? siblings.last
                draft.activeWorkspaceID = nearest!.element.id
            }
        }
    }

    /// Names are compared after trimming, ignoring case, so two Profiles cannot look identical in the switcher.
    public func isProfileNameAvailable(_ name: String, excluding id: UUID? = nil) -> Bool {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !profiles.contains { $0.id != id && $0.name.caseInsensitiveCompare(wanted) == .orderedSame }
    }

    public var hasMultipleProfiles: Bool { profiles.count > 1 }

    /// Workspaces grouped under their Profile, Profiles in creation order.
    public var profileGroups: [ProfileGroup] {
        profiles.map { profile in
            ProfileGroup(profile: profile, isLaunch: profile.id == launchProfileID,
                         workspaces: workspaces.filter { $0.profileID == profile.id })
        }
    }

    /// Switcher order, which numbered shortcuts follow: grouped by Profile, so it can differ from `workspaces`.
    public var switcherWorkspaceIDs: [UUID] { profileGroups.flatMap { $0.workspaces.map(\.id) } }

    /// `number` is 1-based, like the shortcut digit.
    public func switcherWorkspaceID(forShortcut number: Int) -> UUID? {
        let ids = switcherWorkspaceIDs
        return ids.indices.contains(number - 1) ? ids[number - 1] : nil
    }

    /// The Profile's own color, else its first workspace's, so imported Profiles still get a badge.
    public func displayColor(of profile: BrowserProfile) -> String {
        profile.color ?? workspaces.first { $0.profileID == profile.id }?.color ?? "#B47879"
    }

    /// The first palette colour no workspace of the Profile uses, so a new Space does not repeat a neighbour.
    public func nextWorkspaceColor(in palette: [String], profileID: UUID) -> String {
        let used = Set(workspaces.filter { $0.profileID == profileID }.map { $0.color.uppercased() })
        return palette.first { !used.contains($0.uppercased()) } ?? palette.first ?? "#B47879"
    }

    @discardableResult
    public mutating func addWorkspace(name: String, profileID: UUID, color: String? = nil) throws -> UUID {
        try transact { draft in
            guard draft.profiles.contains(where: { $0.id == profileID }) else { throw BrowserStateError.missingProfile }
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            try Self.validateName(name)
            var workspace = Workspace(profileID: profileID, name: name)
            if let color {
                try Self.validateColor(color)
                workspace.color = color.uppercased()
            }
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

    /// Nesting upgrades the document to version 2; flat documents keep version 1 and their bytes.
    @discardableResult
    public mutating func createFolder(name: String, parentID: UUID? = nil) throws -> UUID {
        try transact { draft in
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            try Self.validateFolderName(name)
            let workspace = draft.currentWorkspaceIndex
            let folder = PageFolder(name: name, parentID: parentID)
            if let parentID {
                let parent = try draft.currentFolderIndex(parentID)
                draft.workspaces[workspace].folders[parent].isCollapsed = false
                draft.version = max(draft.version, 2)
            }
            draft.workspaces[workspace].folders.append(folder)
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

    /// Folders reorder among their siblings only.
    public func canMoveFolder(_ id: UUID, direction: FolderMoveDirection) -> Bool {
        let workspace = currentWorkspace
        guard let folder = workspace.folder(id) else { return false }
        let siblings = workspace.subfolders(of: folder.parentID)
        guard let position = siblings.firstIndex(where: { $0.id == id }) else { return false }
        switch direction {
        case .up: return position > 0
        case .down: return position + 1 < siblings.count
        }
    }

    public mutating func moveFolder(_ id: UUID, direction: FolderMoveDirection) throws {
        try transact { draft in
            let index = try draft.currentFolderIndex(id)
            guard draft.canMoveFolder(id, direction: direction) else { throw BrowserStateError.invalidSelection }
            let folders = draft.currentWorkspace.folders
            let siblings = folders.indices.filter { folders[$0].parentID == folders[index].parentID }
            let position = siblings.firstIndex(of: index)!
            let neighbor = siblings[direction == .up ? position - 1 : position + 1]
            draft.workspaces[draft.currentWorkspaceIndex].folders.swapAt(index, neighbor)
        }
    }

    /// A folder cannot move into itself or a descendant, and its whole subtree must fit the depth limit.
    public func canMoveFolder(_ id: UUID, toParent parentID: UUID?) -> Bool {
        let workspace = currentWorkspace
        guard let folder = workspace.folder(id), folder.parentID != parentID, parentID != id else { return false }
        var parentDepth = 0
        if let parentID {
            guard !workspace.descendantFolderIDs(of: id).contains(parentID),
                  let depth = workspace.depth(ofFolder: parentID) else { return false }
            parentDepth = depth
        }
        return parentDepth + workspace.subtreeHeight(ofFolder: id) <= Self.maxFolderDepth
    }

    /// The folder becomes the last child of the destination, or the last top-level folder for `nil`.
    public mutating func moveFolder(_ id: UUID, toParent parentID: UUID?) throws {
        try transact { draft in
            let index = try draft.currentFolderIndex(id)
            let workspace = draft.currentWorkspaceIndex
            if let parentID { _ = try draft.currentFolderIndex(parentID) }
            guard draft.canMoveFolder(id, toParent: parentID) else { throw BrowserStateError.invalidFolder }
            var folder = draft.workspaces[workspace].folders.remove(at: index)
            folder.parentID = parentID
            draft.workspaces[workspace].folders.append(folder)
            if let parentID, let parent = draft.workspaces[workspace].folders.firstIndex(where: { $0.id == parentID }) {
                draft.workspaces[workspace].folders[parent].isCollapsed = false
                draft.version = max(draft.version, 2)
            }
        }
    }

    /// Removes only the container. Pins and subfolders move up one level in their existing order;
    /// at the top level pins return to the unfiled group in their canonical order.
    public mutating func dissolveFolder(_ id: UUID) throws {
        try transact { draft in
            let index = try draft.currentFolderIndex(id)
            let workspace = draft.currentWorkspaceIndex
            let folders = draft.workspaces[workspace].folders
            let dissolved = folders[index]
            var rebuilt: [PageFolder] = []
            for folder in folders {
                if folder.id == id {
                    rebuilt += folders.filter { $0.parentID == id }.map { child in
                        var child = child
                        child.parentID = dissolved.parentID
                        return child
                    }
                } else if folder.parentID != id {
                    rebuilt.append(folder)
                }
            }
            if let parentID = dissolved.parentID,
               let parent = rebuilt.firstIndex(where: { $0.id == parentID }) {
                rebuilt[parent].pinIDs += dissolved.pinIDs
            }
            draft.workspaces[workspace].folders = rebuilt
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

    /// The closed-tab record for a temporary tab of any workspace; nil for saved entries, which stay in the sidebar.
    public func closedTab(for id: UUID) -> ClosedTab? {
        for workspace in workspaces {
            if let index = workspace.tabs.firstIndex(where: { $0.id == id }) {
                let entry = workspace.tabs[index]
                return ClosedTab(profileID: workspace.profileID, workspaceID: workspace.id,
                                 title: entry.title, url: entry.lastURL, index: index)
            }
        }
        return nil
    }

    /// Puts a closed tab back at its old position in its workspace, or in the first workspace of its
    /// Profile when that workspace is gone, and selects it.
    @discardableResult
    public mutating func reopenTab(_ closed: ClosedTab) throws -> UUID {
        try transact { draft in
            try Self.validateURL(closed.url)
            guard let workspace = draft.workspaces.firstIndex(where: { $0.id == closed.workspaceID && $0.profileID == closed.profileID })
                    ?? draft.workspaces.firstIndex(where: { $0.profileID == closed.profileID }) else {
                throw BrowserStateError.missingWorkspace
            }
            let entry = PageEntry(title: closed.title, lastURL: closed.url, kind: .temporary)
            let position = min(max(closed.index, 0), draft.workspaces[workspace].tabs.count)
            draft.workspaces[workspace].tabs.insert(entry, at: position)
            draft.activeWorkspaceID = draft.workspaces[workspace].id
            draft.selectEntryInPlace(entry.id)
            return entry.id
        }
    }

    /// The page one step from the selection in sidebar order, wrapping at the ends.
    /// With nothing selected, forward starts at the first page and backward at the last.
    public func adjacentEntryID(step: Int) -> UUID? {
        let entries = visibleEntries
        guard !entries.isEmpty, step != 0 else { return nil }
        guard let active = currentWorkspace.activeEntryID,
              let index = entries.firstIndex(where: { $0.id == active }) else {
            return step > 0 ? entries.first?.id : entries.last?.id
        }
        let count = entries.count
        return entries[((index + step) % count + count) % count].id
    }

    /// The page to select once `id` closes: the next one in sidebar order, else the previous one.
    public func entryID(afterClosing id: UUID, skipping unavailable: (UUID) -> Bool = { _ in false }) -> UUID? {
        let entries = visibleEntries
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        let candidates = entries[(index + 1)...] + entries[..<index].reversed()
        return candidates.first { !unavailable($0.id) }?.id
    }

    /// Cmd-1 to Cmd-8 pick that page in sidebar order; Cmd-9 always picks the last one.
    public func entryID(forShortcut number: Int) -> UUID? {
        let entries = visibleEntries
        guard (1...9).contains(number), !entries.isEmpty else { return nil }
        if number == 9 { return entries.last?.id }
        return number <= entries.count ? entries[number - 1].id : nil
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

    /// Where a dragged entry lands. Indices count the destination list as displayed, before the entry leaves it.
    public enum SidebarSection: Equatable, Sendable {
        case favorites
        case pinned(folder: UUID?)
        case tabs
    }

    /// The section currently listing the entry, in the active workspace and its Profile.
    public func sidebarSection(of id: UUID) -> SidebarSection? {
        let workspace = currentWorkspace
        if profiles[currentProfileIndex].favorites.contains(where: { $0.id == id }) { return .favorites }
        if workspace.pins.contains(where: { $0.id == id }) { return .pinned(folder: workspace.folder(containingPin: id)?.id) }
        if workspace.tabs.contains(where: { $0.id == id }) { return .tabs }
        return nil
    }

    public func canPlaceEntry(_ id: UUID, in section: SidebarSection) -> Bool {
        guard sidebarSection(of: id) != nil else { return false }
        if case .pinned(let folder?) = section { return currentWorkspace.folder(folder) != nil }
        return true
    }

    /// Reorders within a section, or moves between Favorites, pins, folders and tabs, converting the entry's
    /// kind as needed. Selection stays with the entry; a pair is dissolved when its member changes kind.
    public mutating func placeEntry(_ id: UUID, in section: SidebarSection, at index: Int) throws {
        try transact { draft in
            guard let source = draft.sidebarSection(of: id),
                  var entry = draft.visibleEntries.first(where: { $0.id == id }) else {
                throw BrowserStateError.missingEntry
            }
            guard draft.canPlaceEntry(id, in: section) else { throw BrowserStateError.invalidFolder }
            let workspace = draft.currentWorkspaceIndex
            let profile = draft.currentProfileIndex
            var position = max(0, index)
            if source == section, let current = draft.sectionContaining(id)?.firstIndex(where: { $0.id == id }),
               current < position {
                position -= 1
            }
            let kind: EntryKind
            switch section {
            case .favorites: kind = .favorite
            case .pinned: kind = .pinned
            case .tabs: kind = .temporary
            }
            if entry.kind != kind { draft.removeSplits(containing: id) }
            draft.profiles[profile].favorites.removeAll { $0.id == id }
            draft.workspaces[workspace].pins.removeAll { $0.id == id }
            for folder in draft.workspaces[workspace].folders.indices {
                draft.workspaces[workspace].folders[folder].pinIDs.removeAll { $0 == id }
            }
            draft.workspaces[workspace].tabs.removeAll { $0.id == id }
            entry.kind = kind
            entry.savedURL = kind == .temporary ? nil : (entry.savedURL ?? entry.lastURL)
            switch section {
            case .favorites:
                draft.profiles[profile].favorites.insert(entry, at: min(position, draft.profiles[profile].favorites.count))
                for other in draft.workspaces.indices where other != workspace && draft.workspaces[other].activeEntryID == id {
                    draft.workspaces[other].activeEntryID = nil
                }
            case .tabs:
                draft.workspaces[workspace].tabs.insert(entry, at: min(position, draft.workspaces[workspace].tabs.count))
            case .pinned(let folder):
                if let folder {
                    let target = try draft.currentFolderIndex(folder)
                    let pinIDs = draft.workspaces[workspace].folders[target].pinIDs
                    draft.workspaces[workspace].folders[target].pinIDs.insert(id, at: min(position, pinIDs.count))
                    draft.workspaces[workspace].pins.append(entry)
                } else {
                    let filed = Set(draft.workspaces[workspace].folders.flatMap(\.pinIDs))
                    let unfiled = draft.workspaces[workspace].pins.filter { !filed.contains($0.id) }
                    if position < unfiled.count,
                       let anchor = draft.workspaces[workspace].pins.firstIndex(where: { $0.id == unfiled[position].id }) {
                        draft.workspaces[workspace].pins.insert(entry, at: anchor)
                    } else {
                        draft.workspaces[workspace].pins.append(entry)
                    }
                }
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
    /// Only temporary tabs follow the page title; a Favorite or pin keeps the title it was saved with.
    public mutating func recordNavigation(entryID: UUID, url: URL, title: String) throws {
        try transact { draft in
            try Self.validateURL(url)
            guard draft.allEntries.contains(where: { $0.id == entryID }) else { throw BrowserStateError.missingEntry }
            draft.updateEntry(entryID) { entry in
                entry.lastURL = url
                if entry.kind == .temporary { entry.title = title }
            }
        }
    }

    @discardableResult
    public mutating func createSplit(with id: UUID, side: SplitSide = .right) throws -> UUID {
        try transact { draft in
            guard draft.canCreateSplit(with: id), let focused = draft.currentWorkspace.activeEntryID else {
                throw BrowserStateError.invalidSplit
            }
            let split = PageSplit(leftEntryID: side.newPageIsFirst ? id : focused,
                                  rightEntryID: side.newPageIsFirst ? focused : id,
                                  orientation: side.orientation)
            let index = draft.currentWorkspaceIndex
            draft.workspaces[index].splits.append(split)
            draft.workspaces[index].activeSplitID = split.id
            return split.id
        }
    }

    /// Opens a new temporary tab beside the selected page and focuses it. A page already in a pair
    /// leaves it, so a pane's split menu replaces the other pane.
    @discardableResult
    public mutating func addSplitTab(url: URL, title: String, side: SplitSide) throws -> UUID {
        try transact { draft in
            guard draft.canSplitSelection, let source = draft.currentWorkspace.activeEntryID else {
                throw BrowserStateError.invalidSplit
            }
            try Self.validateURL(url)
            let entry = PageEntry(title: title, lastURL: url, kind: .temporary)
            let index = draft.currentWorkspaceIndex
            // The selected page leaves any pair it was in; its old partner stays as an ordinary page.
            draft.workspaces[index].splits.removeAll { $0.contains(source) }
            draft.workspaces[index].tabs.append(entry)
            let split = PageSplit(leftEntryID: side.newPageIsFirst ? entry.id : source,
                                  rightEntryID: side.newPageIsFirst ? source : entry.id,
                                  orientation: side.orientation)
            draft.workspaces[index].splits.append(split)
            draft.workspaces[index].activeSplitID = split.id
            draft.workspaces[index].activeEntryID = entry.id
            return entry.id
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

    mutating func removeTemporaryTab(_ id: UUID) { removeEntry(id) }

    mutating func selectTabInPlace(_ id: UUID) { selectEntryInPlace(id) }

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

    private static func validateColor(_ color: String) throws {
        guard color.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else {
            throw BrowserStateError.invalidColor
        }
    }

    public static func isValidPageURL(_ url: URL) -> Bool { (try? validateURL(url)) != nil }

    private static func validateURL(_ url: URL) throws {
        if BrowserEssential.accepts(url) { return }
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { throw BrowserStateError.invalidURL }
    }
}
