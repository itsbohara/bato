import Foundation

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

public struct Workspace: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var profileID: UUID
    public var name: String
    public var color: String
    public var pins: [PageEntry]
    public var tabs: [PageEntry]
    public var activeEntryID: UUID?

    public init(id: UUID = UUID(), profileID: UUID, name: String, color: String = "#B47879", pins: [PageEntry] = [], tabs: [PageEntry] = [], activeEntryID: UUID? = nil) {
        self.id = id
        self.profileID = profileID
        self.name = name
        self.color = color
        self.pins = pins
        self.tabs = tabs
        self.activeEntryID = activeEntryID
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

    public var visibleEntries: [PageEntry] {
        let workspace = currentWorkspace
        let favorites = profiles.first(where: { $0.id == workspace.profileID })?.favorites ?? []
        return favorites + workspace.pins + workspace.tabs
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

    @discardableResult
    public mutating func addTab(url: URL, title: String) throws -> UUID {
        try transact { draft in
            try Self.validateURL(url)
            let entry = PageEntry(title: title, lastURL: url, kind: .temporary)
            let workspace = draft.currentWorkspaceIndex
            draft.workspaces[workspace].tabs.append(entry)
            draft.workspaces[workspace].activeEntryID = entry.id
            return entry.id
        }
    }

    public mutating func selectEntry(_ id: UUID) throws {
        try transact { draft in
            guard draft.visibleEntries.contains(where: { $0.id == id }) else { throw BrowserStateError.missingEntry }
            draft.workspaces[draft.currentWorkspaceIndex].activeEntryID = id
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

    /// Closing saved entries keeps their identity/order and restores their saved destination for reopening.
    public mutating func closeEntry(_ id: UUID) throws {
        try transact { draft in
            guard let entry = draft.visibleEntries.first(where: { $0.id == id }) else { throw BrowserStateError.missingEntry }
            if entry.kind == .temporary {
                draft.removeEntry(id)
            } else {
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
        for index in profiles.indices { profiles[index].favorites.removeAll { $0.id == id } }
        for index in workspaces.indices {
            workspaces[index].pins.removeAll { $0.id == id }
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

    private static func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BrowserStateError.emptyName }
    }

    private static func validateURL(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { throw BrowserStateError.invalidURL }
    }
}
