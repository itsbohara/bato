import BatoCore
import CryptoKit
import Foundation

typealias JSONObject = [String: Any]

public enum ArcSidebarParser {
    public static let maxInputBytes = 64 * 1024 * 1024
    static let maxNesting = 256

    public static func parse(_ data: Data) throws -> ArcStaging {
        guard data.count <= maxInputBytes else { throw ArcImportError.tooLarge }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? JSONObject else {
            throw ArcImportError.invalidJSON
        }
        let sidebar = root["sidebar"] as? JSONObject ?? root
        guard let container = (sidebar["containers"] as? [Any])?
            .compactMap({ $0 as? JSONObject })
            .first(where: { $0["spaces"] != nil && $0["items"] != nil }) else {
            throw ArcImportError.missingSidebar
        }
        var reader = SidebarReader(items: Dictionary(keyedEntries(container["items"]), uniquingKeysWith: { first, _ in first }))
        let spaces = reader.spaces(keyedEntries(container["spaces"]))
        let favorites = reader.favorites(container["topAppsContainerIDs"] ?? sidebar["topAppsContainerIDs"], profiles: spaces.profiles)
        return ArcStaging(
            sourceDigest: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            profiles: favorites,
            spaces: spaces.spaces,
            warnings: reader.warnings
        )
    }
}

/// Arc writes maps as alternating `[key, value, key, value]` arrays; plain object lists and dictionaries are also accepted.
func keyedEntries(_ raw: Any?) -> [(String, JSONObject)] {
    if let map = raw as? JSONObject {
        return map.keys.sorted().compactMap { key in (map[key] as? JSONObject).map { (key, $0) } }
    }
    guard let array = raw as? [Any] else { return [] }
    var entries: [(String, JSONObject)] = []
    var index = 0
    while index < array.count {
        if let key = array[index] as? String, index + 1 < array.count, let value = array[index + 1] as? JSONObject {
            entries.append((key, value))
            index += 2
        } else {
            if let object = array[index] as? JSONObject, let key = object["id"] as? String {
                entries.append((key, object))
            }
            index += 1
        }
    }
    return entries
}

private struct SidebarReader {
    let items: [String: JSONObject]
    var warnings: [ImportWarning] = []
    private var visited = Set<String>()
    private var path = Set<String>()
    private var spaceID: String?
    private var interleaved = false

    init(items: [String: JSONObject]) {
        self.items = items
    }

    mutating func spaces(_ entries: [(String, JSONObject)]) -> (spaces: [ArcSpace], profiles: [ArcProfile]) {
        var spaces: [ArcSpace] = []
        var profiles: [ArcProfile] = []
        for (index, (key, object)) in entries.enumerated() {
            let id = key
            spaceID = id
            interleaved = false
            let profile = Self.profile(object["profile"])
            if !profiles.contains(where: { $0.key == profile.key }) {
                profiles.append(ArcProfile(key: profile.key, name: profile.name, favorites: []))
            }
            let roles = Self.containerRoles(object["newContainerIDs"], fallback: object["containerIDs"])
            let pinned = roles.pinned.map { flatten(nodes(ofContainer: $0), keepSplits: true, keepFolders: true) } ?? []
            let today = roles.unpinned.map { flatten(nodes(ofContainer: $0), keepSplits: true, keepFolders: false) } ?? []
            if interleaved { warn(.interleavingLost) }
            let custom = object["customInfo"] as? JSONObject
            if custom?["iconType"] != nil { warn(.droppedIcon) }
            var colorHex: String?
            if let theme = custom?["windowTheme"] as? JSONObject {
                warn(.droppedTheme)
                colorHex = Self.midToneHex(theme)
            }
            spaces.append(ArcSpace(id: id, title: title(object["title"], fallback: "Space \(index + 1)"),
                                   profileKey: profile.key, colorHex: colorHex, pinned: pinned, today: today))
        }
        spaceID = nil
        return (spaces, profiles)
    }

    mutating func favorites(_ raw: Any?, profiles: [ArcProfile]) -> [ArcProfile] {
        var profiles = profiles
        var key = "default"
        for element in raw as? [Any] ?? [] {
            if let descriptor = element as? JSONObject {
                key = Self.profile(descriptor).key
            } else if let string = element as? String, string == "default" {
                key = string
            } else if let containerID = element as? String {
                guard let index = profiles.firstIndex(where: { $0.key == key }) else {
                    warn(.missingReference, detail: "favorites-profile")
                    continue
                }
                var seen = Set(profiles[index].favorites.map(\.url))
                for node in flatten(nodes(ofContainer: containerID), keepSplits: false, keepFolders: false) {
                    guard case .page(let page) = node else { continue }
                    if seen.insert(page.url).inserted {
                        profiles[index].favorites.append(page)
                    } else {
                        warn(.duplicateFavorite)
                    }
                }
            }
        }
        return profiles
    }

    private mutating func nodes(ofContainer id: String) -> [ArcNode] {
        guard let container = items[id] else {
            warn(.missingReference, detail: "container")
            return []
        }
        visited.insert(id)
        return nodes(Self.childIDs(container), folderDepth: 0, nesting: 0)
    }

    private mutating func nodes(_ ids: [String], folderDepth: Int, nesting: Int) -> [ArcNode] {
        var result: [ArcNode] = []
        for id in ids {
            guard let item = items[id] else {
                warn(.missingReference, detail: "child")
                continue
            }
            guard !path.contains(id) else {
                warn(.cycle)
                continue
            }
            guard visited.insert(id).inserted else {
                warn(.duplicateItem)
                continue
            }
            guard nesting < ArcSidebarParser.maxNesting else {
                warn(.excessiveNesting)
                continue
            }
            path.insert(id)
            result += node(id: id, item: item, folderDepth: folderDepth, nesting: nesting)
            path.remove(id)
        }
        noteInterleaving(result)
        return result
    }

    private mutating func node(id: String, item: JSONObject, folderDepth: Int, nesting: Int) -> [ArcNode] {
        let data = item["data"] as? JSONObject
        if let tab = data?["tab"] as? JSONObject {
            return page(id: id, item: item, tab: tab).map { [.page($0)] } ?? []
        }
        if let list = data?["list"] as? JSONObject {
            if list["automaticLiveFolderData"] != nil || data?["automaticLiveFolderData"] != nil {
                warn(.liveFolder)
            }
            let depth = folderDepth + 1
            let children = Self.childIDs(item)
            guard depth <= BrowserState.maxFolderDepth else {
                warn(.depthHoisted, detail: "\(depth)")
                return nodes(children, folderDepth: folderDepth, nesting: nesting + 1)
            }
            let name = folderName(item["title"])
            return [.folder(ArcFolder(id: id, name: name, children: nodes(children, folderDepth: depth, nesting: nesting + 1)))]
        }
        if data?["splitView"] != nil {
            let ids = Self.childIDs(item)
            let pages = nodes(ids, folderDepth: folderDepth, nesting: nesting + 1).compactMap { node -> ArcPage? in
                if case .page(let page) = node { page } else { nil }
            }
            if pages.count == 2, ids.count == 2 {
                return [.split(ArcSplit(id: id, first: pages[0], second: pages[1]))]
            }
            warn(.splitFlattened, detail: "\(ids.count)")
            return pages.map { .page($0) }
        }
        warn(.unknownItem, detail: data?.keys.sorted().first ?? "none")
        return []
    }

    private mutating func page(id: String, item: JSONObject, tab: JSONObject) -> ArcPage? {
        guard let raw = tab["savedURL"] as? String, let url = Self.httpURL(raw) else {
            let scheme = (tab["savedURL"] as? String).flatMap { URL(string: $0)?.scheme?.lowercased() }
            warn(.unsupportedURL, detail: scheme ?? "invalid")
            return nil
        }
        let title = [item["title"], tab["savedTitle"]]
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? url.host ?? ""
        return ArcPage(id: id, title: title, url: url)
    }

    private mutating func folderName(_ raw: Any?) -> String {
        let cleaned = String(String.UnicodeScalarView((raw as? String ?? "").unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            warn(.nameDefaulted, detail: "folder")
            return "Folder"
        }
        guard cleaned.count > 80 else { return cleaned }
        warn(.truncatedName)
        return String(cleaned.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private mutating func title(_ raw: Any?, fallback: String) -> String {
        let trimmed = (raw as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }
        warn(.nameDefaulted, detail: "space")
        return fallback
    }

    /// Splits stay only where their pinned/temporary kind is preserved; folders only inside pinned content.
    private mutating func flatten(_ nodes: [ArcNode], keepSplits: Bool, keepFolders: Bool) -> [ArcNode] {
        var result: [ArcNode] = []
        for node in nodes {
            switch node {
            case .page: result.append(node)
            case .split(let split):
                result += keepSplits ? [node] : [.page(split.first), .page(split.second)]
            case .folder(let folder):
                if keepFolders {
                    result.append(node)
                } else {
                    warn(.unknownItem, detail: "folder-in-flat-list")
                    result += flatten(folder.children, keepSplits: keepSplits, keepFolders: false)
                }
            }
        }
        return result
    }

    private mutating func noteInterleaving(_ nodes: [ArcNode]) {
        var sawFolder = false
        for node in nodes {
            if case .folder = node {
                sawFolder = true
            } else if sawFolder {
                interleaved = true
            }
        }
    }

    private mutating func warn(_ kind: ImportWarning.Kind, detail: String? = nil) {
        warnings.append(ImportWarning(kind, spaceID: spaceID, detail: detail))
    }

    private static func childIDs(_ item: JSONObject) -> [String] {
        (item["childrenIds"] as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private static func httpURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    private static func profile(_ raw: Any?) -> (key: String, name: String) {
        guard let custom = (raw as? JSONObject)?["custom"] as? JSONObject else { return ("default", "Arc") }
        let basename = ((custom["_0"] as? JSONObject)?["directoryBasename"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return basename.isEmpty ? ("custom:", "Arc - Profile") : ("custom:\(basename)", "Arc - \(basename)")
    }

    /// Pairs a role marker (`"pinned"` or `{"pinned": ...}`) with the container id that follows it.
    private static func containerRoles(_ raw: Any?, fallback: Any?) -> (pinned: String?, unpinned: String?) {
        func read(_ raw: Any?) -> (pinned: String?, unpinned: String?) {
            var assigned: [String: String] = [:]
            var unmarked: [String] = []
            var role: String?
            for element in raw as? [Any] ?? [] {
                if let string = element as? String, string == "pinned" || string == "unpinned" {
                    role = string
                } else if let object = element as? JSONObject {
                    role = ["pinned", "unpinned"].first { object[$0] != nil }
                } else if let id = element as? String {
                    if let current = role { assigned[current] = id } else { unmarked.append(id) }
                    role = nil
                }
            }
            return (assigned["pinned"] ?? unmarked.first, assigned["unpinned"] ?? unmarked.dropFirst().first)
        }
        let primary = read(raw)
        let secondary = read(fallback)
        return (primary.pinned ?? secondary.pinned, primary.unpinned ?? secondary.unpinned)
    }

    private static func midToneHex(_ theme: JSONObject) -> String? {
        guard let tone = (theme["primaryColorPalette"] as? JSONObject)?["midTone"] as? JSONObject else { return nil }
        let channels = ["red", "green", "blue"].compactMap { (tone[$0] as? NSNumber)?.doubleValue }
        guard channels.count == 3 else { return nil }
        return "#" + channels.map { String(format: "%02X", Int((min(max($0, 0), 1) * 255).rounded())) }.joined()
    }
}
