import BatoCore
import Foundation

/// Firefox and Zen: bookmarks and history from `places.sqlite`. Zen also keeps workspaces
/// (`zen_workspaces`) and pinned tabs/Essentials (`zen_pins`) in that database; those table and
/// column names are from Zen's public source and are read defensively, so an unfamiliar layout yields
/// no Spaces rather than an error.
enum GeckoReader {
    private static let historyFilter = "visit_count > 0 AND hidden = 0 AND (url LIKE 'http://%' OR url LIKE 'https://%')"

    static func places(_ profile: URL) -> URL { profile.appendingPathComponent("places.sqlite") }

    static func historyCount(profile: URL) throws -> Int {
        try SQLiteDatabase.copyOf(places(profile)).scalarInt("SELECT COUNT(*) FROM moz_places WHERE \(historyFilter)")
    }

    static func history(profile: URL) throws -> [ImportedHistoryEntry] {
        let database = try SQLiteDatabase.copyOf(places(profile))
        let rows = try database.rows("SELECT url, title, visit_count, last_visit_date FROM moz_places WHERE \(historyFilter) ORDER BY last_visit_date DESC")
        return rows.compactMap { row in
            guard let text = row[0].text, let url = URL(string: text), url.isWebURL else { return nil }
            return ImportedHistoryEntry(url: url, title: row[1].text ?? "", visitCount: Int(row[2].int ?? 1),
                                        lastVisit: Date(timeIntervalSince1970: (row[3].double ?? 0) / 1_000_000))
        }
    }

    /// Toolbar pages become Favorites (Zen: Essentials are added by `zen`).
    static func bookmarks(profile: URL) throws -> (favorites: [ImportedPage], tree: [BookmarkNode]) {
        let database = try SQLiteDatabase.copyOf(places(profile))
        let rows = try database.rows("""
            SELECT b.id, b.parent, b.type, b.title, p.url, b.guid FROM moz_bookmarks b
            LEFT JOIN moz_places p ON p.id = b.fk ORDER BY b.parent, b.position
            """)
        var children: [Int64: [[SQLValue]]] = [:]
        var rootsByGUID: [String: Int64] = [:]
        for row in rows {
            children[row[1].int ?? -1, default: []].append(row)
            if let guid = row[5].text, guid.hasSuffix("_") { rootsByGUID[guid] = row[0].int ?? -1 }
        }
        func nodes(_ parent: Int64, depth: Int = 0) -> [BookmarkNode] {
            guard depth < 32 else { return [] }
            return (children[parent] ?? []).compactMap { row in
                switch row[2].int {
                case 2:
                    let inner = nodes(row[0].int ?? -1, depth: depth + 1)
                    return inner.isEmpty ? nil : .folder(name: row[3].text ?? "", children: inner)
                case 1:
                    guard let text = row[4].text, let url = URL(string: text), url.isWebURL else { return nil }
                    return .page(ImportedPage(title: row[3].text ?? "", url: url))
                default: return nil
                }
            }
        }
        var favorites: [ImportedPage] = []
        var tree: [BookmarkNode] = []
        if let toolbar = rootsByGUID["toolbar_____"] {
            var rest: [BookmarkNode] = []
            for node in nodes(toolbar) {
                if case .page(let page) = node { favorites.append(page) } else { rest.append(node) }
            }
            if !rest.isEmpty { tree.append(.folder(name: "Bookmarks Toolbar", children: rest)) }
        }
        for (guid, name) in [("menu________", "Bookmarks Menu"), ("unfiled_____", "Other Bookmarks"),
                             ("mobile______", "Mobile Bookmarks")] {
            guard let root = rootsByGUID[guid] else { continue }
            let inner = nodes(root)
            if !inner.isEmpty { tree.append(.folder(name: name, children: inner)) }
        }
        return (favorites, tree)
    }

    /// Zen workspaces as Spaces with their pinned tabs and folders; Essentials become Favorites.
    /// Nil when the database has no workspaces table.
    static func zenSpaces(profile: URL, profileID: String) throws -> ArcStaging? {
        let database = try SQLiteDatabase.copyOf(places(profile))
        guard try database.hasTable("zen_workspaces") else { return nil }
        let workspaceColumns = try database.columns(of: "zen_workspaces")
        guard workspaceColumns.isSuperset(of: ["uuid", "name"]) else { return nil }
        let container = workspaceColumns.contains("container_id") ? "container_id" : "0"
        let order = workspaceColumns.contains("position") ? "position" : "id"
        let workspaces = try database.rows("SELECT uuid, name, \(container) FROM zen_workspaces ORDER BY \(order)")

        var pins: [ZenPin] = []
        if try database.hasTable("zen_pins") {
            let pinColumns = try database.columns(of: "zen_pins")
            if pinColumns.isSuperset(of: ["uuid", "title", "url", "workspace_uuid"]) {
                let select = ["uuid", "title", "url", "workspace_uuid",
                              pinColumns.contains("container_id") ? "container_id" : "0",
                              pinColumns.contains("is_essential") ? "is_essential" : "0",
                              pinColumns.contains("is_group") ? "is_group" : "0",
                              pinColumns.contains("folder_parent_uuid") ? "folder_parent_uuid" : "NULL"]
                let sort = pinColumns.contains("position") ? "position" : "id"
                pins = try database.rows("SELECT \(select.joined(separator: ", ")) FROM zen_pins ORDER BY \(sort)").compactMap(ZenPin.init)
            }
        }

        func profileKey(_ container: Int64) -> String { "zen-container-\(container)" }
        var profiles: [String: ArcProfile] = [:]
        func ensureProfile(_ container: Int64) {
            let key = profileKey(container)
            if profiles[key] == nil {
                profiles[key] = ArcProfile(key: key, name: container == 0 ? "Zen" : "Zen (container \(container))", favorites: [])
            }
        }
        var spaces: [ArcSpace] = []
        for row in workspaces {
            guard let uuid = row[0].text else { continue }
            let container = row[2].int ?? 0
            ensureProfile(container)
            spaces.append(ArcSpace(id: uuid, title: cleanName(row[1].text, fallback: "Zen workspace"), profileKey: profileKey(container),
                                   colorHex: nil, pinned: zenNodes(pins, workspace: uuid, parent: nil, depth: 1), today: []))
        }
        var seenFavorites = Set<String>()
        for pin in pins where pin.isEssential && !pin.isGroup {
            guard let url = pin.url else { continue }
            ensureProfile(pin.container)
            guard seenFavorites.insert("\(pin.container)|\(url.duplicateKey)").inserted else { continue }
            profiles[profileKey(pin.container)]?.favorites.append(ArcPage(id: pin.uuid, title: pin.title, url: url))
        }
        guard !spaces.isEmpty else { return nil }
        return ArcStaging(sourceDigest: "zen:\(profileID)", profiles: profiles.keys.sorted().compactMap { profiles[$0] },
                          spaces: spaces, warnings: [])
    }

    private struct ZenPin {
        var uuid: String, title: String, url: URL?, workspace: String, container: Int64
        var isEssential: Bool, isGroup: Bool, parent: String?

        init?(_ row: [SQLValue]) {
            guard let uuid = row[0].text else { return nil }
            self.uuid = uuid
            url = row[2].text.flatMap(URL.init(string:)).flatMap { $0.isWebURL ? $0 : nil }
            title = cleanName(row[1].text, fallback: url?.host ?? "Pinned tab")
            workspace = row[3].text ?? ""
            container = row[4].int ?? 0
            isEssential = (row[5].int ?? 0) != 0
            isGroup = (row[6].int ?? 0) != 0
            parent = row[7].text.flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    /// Folders deeper than Bato allows are hoisted into their nearest allowed ancestor.
    private static func zenNodes(_ pins: [ZenPin], workspace: String, parent: String?, depth: Int,
                                 visited: Set<String> = []) -> [ArcNode] {
        pins.filter { $0.workspace == workspace && !$0.isEssential && $0.parent == parent && !visited.contains($0.uuid) }
            .flatMap { pin -> [ArcNode] in
                let nextVisited = visited.union([pin.uuid])
                if pin.isGroup {
                    let inner = zenNodes(pins, workspace: workspace, parent: pin.uuid,
                                         depth: min(depth + 1, BrowserState.maxFolderDepth + 1), visited: nextVisited)
                    return depth > BrowserState.maxFolderDepth ? inner
                        : [.folder(ArcFolder(id: pin.uuid, name: cleanName(pin.title, fallback: "Folder"), children: inner))]
                }
                return pin.url.map { [.page(ArcPage(id: pin.uuid, title: pin.title, url: $0))] } ?? []
            }
    }
}

func cleanName(_ raw: String?, fallback: String) -> String {
    let scalars = (raw ?? "").unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
    let text = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? fallback : String(text.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
}
