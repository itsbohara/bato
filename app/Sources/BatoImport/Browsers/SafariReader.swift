import Foundation

/// Safari's `Bookmarks.plist` and `History.db`. Both live in a folder macOS protects, so reads fail
/// with a permission error until the app has Full Disk Access.
enum SafariReader {
    private static let webFilter = "url LIKE 'http://%' OR url LIKE 'https://%'"

    static func historyCount(folder: URL) throws -> Int {
        try SQLiteDatabase.copyOf(folder.appendingPathComponent("History.db"))
            .scalarInt("SELECT COUNT(*) FROM history_items WHERE \(webFilter)")
    }

    static func history(folder: URL) throws -> [ImportedHistoryEntry] {
        let database = try SQLiteDatabase.copyOf(folder.appendingPathComponent("History.db"))
        let rows = try database.rows("""
            SELECT i.url, v.title, i.visit_count, v.visit_time FROM history_items i
            JOIN history_visits v ON v.history_item = i.id
            WHERE (i.url LIKE 'http://%' OR i.url LIKE 'https://%')
              AND v.visit_time = (SELECT MAX(visit_time) FROM history_visits WHERE history_item = i.id)
            GROUP BY i.id ORDER BY v.visit_time DESC
            """)
        return rows.compactMap { row in
            guard let text = row[0].text, let url = URL(string: text), url.isWebURL else { return nil }
            return ImportedHistoryEntry(url: url, title: row[1].text ?? "", visitCount: Int(row[2].int ?? 1),
                                        lastVisit: Date(timeIntervalSinceReferenceDate: row[3].double ?? 0))
        }
    }

    /// Bookmarks-bar leaves become Favorites. The Reading List is skipped.
    static func bookmarks(folder: URL) throws -> (favorites: [ImportedPage], tree: [BookmarkNode]) {
        let data: Data
        do { data = try Data(contentsOf: folder.appendingPathComponent("Bookmarks.plist")) } catch {
            throw classify(error)
        }
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ImportReadError.unreadable
        }
        var favorites: [ImportedPage] = []
        var tree: [BookmarkNode] = []
        for child in root["Children"] as? [[String: Any]] ?? [] {
            switch child["Title"] as? String {
            case "BookmarksBar":
                var rest: [BookmarkNode] = []
                for node in nodes(child["Children"]) {
                    if case .page(let page) = node { favorites.append(page) } else { rest.append(node) }
                }
                if !rest.isEmpty { tree.append(.folder(name: "Favorites", children: rest)) }
            case "BookmarksMenu":
                let children = nodes(child["Children"])
                if !children.isEmpty { tree.append(.folder(name: "Bookmarks Menu", children: children)) }
            default: break
            }
        }
        return (favorites, tree)
    }

    /// Whether the importer may read Safari's folder, without reading any content.
    static func hasFullDiskAccess(folder: URL) -> Bool {
        let descriptor = open(folder.appendingPathComponent("Bookmarks.plist").path, O_RDONLY)
        if descriptor >= 0 { close(descriptor); return true }
        return errno != EPERM && errno != EACCES
    }

    static func classify(_ error: Error) -> ImportReadError {
        let nsError = error as NSError
        let posix = nsError.domain == NSPOSIXErrorDomain ? nsError.code
            : (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.code
        return nsError.code == NSFileReadNoPermissionError || posix == Int(EPERM) || posix == Int(EACCES)
            ? .permissionDenied : .unreadable
    }

    private static func nodes(_ raw: Any?) -> [BookmarkNode] {
        (raw as? [[String: Any]] ?? []).compactMap { node in
            switch node["WebBookmarkType"] as? String {
            case "WebBookmarkTypeList":
                let children = nodes(node["Children"])
                return children.isEmpty ? nil : .folder(name: (node["Title"] as? String) ?? "", children: children)
            case "WebBookmarkTypeLeaf":
                guard let text = node["URLString"] as? String, let url = URL(string: text), url.isWebURL else { return nil }
                let title = ((node["URIDictionary"] as? [String: Any])?["title"] as? String) ?? ""
                return .page(ImportedPage(title: title, url: url))
            default: return nil
            }
        }
    }
}
