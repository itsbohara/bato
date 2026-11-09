import Foundation

/// Chrome, Brave, Edge, Dia and Arc's Chromium profile: `Bookmarks` JSON and `History` SQLite.
enum ChromiumReader {
    private static let epochOffsetSeconds = 11_644_473_600.0
    private static let historyFilter = "hidden = 0 AND visit_count > 0 AND (url LIKE 'http://%' OR url LIKE 'https://%')"

    static func historyCount(profile: URL) throws -> Int {
        try SQLiteDatabase.copyOf(profile.appendingPathComponent("History")).scalarInt("SELECT COUNT(*) FROM urls WHERE \(historyFilter)")
    }

    static func history(profile: URL) throws -> [ImportedHistoryEntry] {
        let database = try SQLiteDatabase.copyOf(profile.appendingPathComponent("History"))
        let rows = try database.rows("SELECT url, title, visit_count, last_visit_time FROM urls WHERE \(historyFilter) ORDER BY last_visit_time DESC")
        return rows.compactMap { row in
            guard let text = row[0].text, let url = URL(string: text), url.isWebURL else { return nil }
            let micros = row[3].double ?? 0
            return ImportedHistoryEntry(url: url, title: row[1].text ?? "", visitCount: Int(row[2].int ?? 1),
                                        lastVisit: Date(timeIntervalSince1970: micros / 1_000_000 - epochOffsetSeconds))
        }
    }

    /// Bookmarks-bar pages become Favorites; the rest of the tree stays as bookmarks.
    static func bookmarks(profile: URL) throws -> (favorites: [ImportedPage], tree: [BookmarkNode]) {
        let url = profile.appendingPathComponent("Bookmarks")
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw ImportReadError.unreadable }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = object["roots"] as? [String: Any] else { throw ImportReadError.unreadable }
        var favorites: [ImportedPage] = []
        var tree: [BookmarkNode] = []
        if let bar = roots["bookmark_bar"] as? [String: Any] {
            var barRest: [BookmarkNode] = []
            for child in nodes(bar["children"]) {
                if case .page(let page) = child { favorites.append(page) } else { barRest.append(child) }
            }
            if !barRest.isEmpty { tree.append(.folder(name: "Bookmarks Bar", children: barRest)) }
        }
        for (key, name) in [("other", "Other Bookmarks"), ("synced", "Mobile Bookmarks")] {
            guard let root = roots[key] as? [String: Any] else { continue }
            let children = nodes(root["children"])
            if !children.isEmpty { tree.append(.folder(name: name, children: children)) }
        }
        return (favorites, tree)
    }

    private static func nodes(_ raw: Any?) -> [BookmarkNode] {
        (raw as? [[String: Any]] ?? []).compactMap { node in
            let name = (node["name"] as? String) ?? ""
            if node["type"] as? String == "folder" {
                let children = nodes(node["children"])
                return children.isEmpty ? nil : .folder(name: name, children: children)
            }
            guard let text = node["url"] as? String, let url = URL(string: text), url.isWebURL else { return nil }
            return .page(ImportedPage(title: name, url: url))
        }
    }
}
