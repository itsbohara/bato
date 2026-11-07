import BatoCore
import CryptoKit
import Foundation

public struct ImportOptions: Equatable, Sendable {
    public var includeTodayTabs: Bool
    public var excludedSpaceIDs: Set<String>
    /// Changes every derived identifier, so a deliberate second import does not collide with the first.
    public var idSalt: String

    public init(includeTodayTabs: Bool = false, excludedSpaceIDs: Set<String> = [], idSalt: String = "") {
        self.includeTodayTabs = includeTodayTabs
        self.excludedSpaceIDs = excludedSpaceIDs
        self.idSalt = idSalt
    }
}

public enum ImportPlanError: Error, Equatable, LocalizedError {
    case nothingToImport
    case alreadyImported

    public var errorDescription: String? {
        switch self {
        case .nothingToImport: "No Arc spaces are selected for import."
        case .alreadyImported: "This Arc file has already been imported."
        }
    }
}

public struct ImportSummary: Equatable, Sendable {
    public struct Space: Equatable, Sendable {
        public var arcID: String
        public var name: String
        public var pins: Int
        public var folders: Int
        public var maxFolderDepth: Int
        public var tabs: Int
        public var splits: Int

        init(arcID: String, workspace: Workspace) {
            self.arcID = arcID
            name = workspace.name
            pins = workspace.pins.count
            folders = workspace.folders.count
            maxFolderDepth = workspace.folders.compactMap { workspace.depth(ofFolder: $0.id) }.max() ?? 0
            tabs = workspace.tabs.count
            splits = workspace.splits.count
        }
    }

    public var profiles: Int
    public var workspaces: Int
    public var favorites: Int
    public var spaces: [Space]
    public var warningCounts: [ImportWarning.Kind: Int]

    public var pins: Int { spaces.reduce(0) { $0 + $1.pins } }
    public var folders: Int { spaces.reduce(0) { $0 + $1.folders } }
    public var tabs: Int { spaces.reduce(0) { $0 + $1.tabs } }
    public var splits: Int { spaces.reduce(0) { $0 + $1.splits } }
}

public extension ImportPlan {
    /// Arc space ids whose workspace from this file (and salt) is already in `existing`.
    static func alreadyImportedSpaceIDs(_ staging: ArcStaging, in existing: BrowserState,
                                        idSalt: String = "") -> Set<String> {
        let ids = IdentityFactory(digest: staging.sourceDigest, salt: idSalt)
        let known = Set(existing.workspaces.map(\.id))
        return Set(staging.spaces.filter { known.contains(ids.id("workspace", $0.id)) }.map(\.id))
    }
}

/// A validated draft of the organization after import. Nothing is persisted or applied here.
public struct ImportPlan: Equatable, Sendable {
    public var state: BrowserState
    public var summary: ImportSummary
    public var warnings: [ImportWarning]

    public static func make(_ staging: ArcStaging, options: ImportOptions = ImportOptions(),
                            into existing: BrowserState) throws -> ImportPlan {
        try existing.validate()
        let spaces = staging.spaces.filter { !options.excludedSpaceIDs.contains($0.id) }
        guard !spaces.isEmpty else { throw ImportPlanError.nothingToImport }
        let ids = IdentityFactory(digest: staging.sourceDigest, salt: options.idSalt)

        let usedKeys = Set(spaces.map(\.profileKey))
        let usedProfiles = staging.profiles.filter { usedKeys.contains($0.key) }
        let profileIDs = Dictionary(uniqueKeysWithValues: usedProfiles.map { ($0.key, ids.id("profile", $0.key)) })
        // A profile imported earlier from this file is reused, so importing another space of the same file works.
        let knownProfileIDs = Set(existing.profiles.map(\.id))
        let profiles = usedProfiles.filter { !knownProfileIDs.contains(profileIDs[$0.key]!) }.map { profile in
            BrowserProfile(id: profileIDs[profile.key]!, name: profile.name,
                           favorites: profile.favorites.map { ids.entry($0, kind: .favorite) })
        }

        var workspaces: [Workspace] = []
        for space in spaces {
            var builder = EntryBuilder(ids: ids)
            builder.addPinned(space.pinned, in: nil)
            if options.includeTodayTabs { builder.addToday(space.today) }
            workspaces.append(Workspace(
                id: ids.id("workspace", space.id), profileID: profileIDs[space.profileKey]!,
                name: space.title, color: space.colorHex ?? Workspace.defaultColor,
                pins: builder.pins, folders: builder.folders, tabs: builder.tabs, splits: builder.splits))
        }

        let existingIDs = Set(existing.workspaces.map(\.id))
        guard existingIDs.isDisjoint(with: workspaces.map(\.id)) else {
            throw ImportPlanError.alreadyImported
        }
        var draft = existing
        draft.version = max(existing.version, 2)
        draft.profiles += profiles
        draft.workspaces += workspaces
        try draft.validate()

        let included = Set(spaces.map(\.id))
        let warnings = staging.warnings.filter { $0.spaceID.map(included.contains) ?? true }
        let summary = ImportSummary(
            profiles: profiles.count, workspaces: workspaces.count,
            favorites: profiles.reduce(0) { $0 + $1.favorites.count },
            spaces: zip(spaces, workspaces).map { ImportSummary.Space(arcID: $0.id, workspace: $1) },
            warningCounts: warnings.reduce(into: [:]) { $0[$1.kind, default: 0] += 1 })
        return ImportPlan(state: draft, summary: summary, warnings: warnings)
    }
}

private extension Workspace {
    static let defaultColor = "#B47879"
}

/// Name-based identifiers: the same file, item and salt always map to the same UUID.
private struct IdentityFactory {
    let digest: String
    let salt: String

    func id(_ kind: String, _ arcID: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("\(digest)\0\(salt)\0\(kind)\0\(arcID)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    func entry(_ page: ArcPage, kind: EntryKind) -> PageEntry {
        PageEntry(id: id("entry", page.id), title: page.title,
                  savedURL: kind == .temporary ? nil : page.url, lastURL: page.url, kind: kind)
    }
}

private struct EntryBuilder {
    let ids: IdentityFactory
    var pins: [PageEntry] = []
    var folders: [PageFolder] = []
    var tabs: [PageEntry] = []
    var splits: [PageSplit] = []

    init(ids: IdentityFactory) {
        self.ids = ids
    }

    mutating func addPinned(_ nodes: [ArcNode], in folderIndex: Int?) {
        for node in nodes {
            switch node {
            case .page(let page):
                addPin(page, in: folderIndex)
            case .split(let split):
                addPin(split.first, in: folderIndex)
                addPin(split.second, in: folderIndex)
                splits.append(PageSplit(id: ids.id("split", split.id), leftEntryID: ids.id("entry", split.first.id),
                                        rightEntryID: ids.id("entry", split.second.id), isPinned: true))
            case .folder(let folder):
                folders.append(PageFolder(id: ids.id("folder", folder.id), name: folder.name, isCollapsed: true,
                                          parentID: folderIndex.map { folders[$0].id }))
                addPinned(folder.children, in: folders.count - 1)
            }
        }
    }

    mutating func addToday(_ nodes: [ArcNode]) {
        for node in nodes {
            switch node {
            case .page(let page):
                tabs.append(ids.entry(page, kind: .temporary))
            case .split(let split):
                tabs.append(ids.entry(split.first, kind: .temporary))
                tabs.append(ids.entry(split.second, kind: .temporary))
                splits.append(PageSplit(id: ids.id("split", split.id), leftEntryID: ids.id("entry", split.first.id),
                                        rightEntryID: ids.id("entry", split.second.id)))
            case .folder:
                break
            }
        }
    }

    private mutating func addPin(_ page: ArcPage, in folderIndex: Int?) {
        let pin = ids.entry(page, kind: .pinned)
        pins.append(pin)
        if let folderIndex { folders[folderIndex].pinIDs.append(pin.id) }
    }
}
