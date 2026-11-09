import Darwin
import Foundation

/// Bookmarks and history staged for a Bato Profile's Chromium profile directory.
///
/// Bato's pages run in Chromium profiles and Bato keeps no history of its own, so imported history
/// and bookmarks must end up in the profile's `History` database and `Bookmarks` file. Chromium holds
/// those open (exclusive lock) and rewrites `Bookmarks` from memory on exit, so they can only be written
/// while the engine is not using the profile. The plan therefore stages them here, and
/// `ChromiumProfileWriter` applies them at the next launch before the engine starts.
public struct PendingBrowserData: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion = PendingBrowserData.schemaVersion
    /// Same source and Profile always yield the same batch, so re-staging replaces rather than duplicates.
    public var batchID: String
    public var source: ImportSource
    public var bookmarks: [BookmarkNode]
    public var history: [ImportedHistoryEntry]

    public var isEmpty: Bool { bookmarks.isEmpty && history.isEmpty }
}

/// One JSON file per Profile and batch under `<state>/import-pending`.
public struct PendingImportStore: Sendable {
    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private func file(_ profileKey: String, _ batchID: String) -> URL {
        directory.appendingPathComponent("\(profileKey).\(batchID).json")
    }

    public func stage(_ data: PendingBrowserData, profileKey: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(data).write(to: file(profileKey, data.batchID), options: .atomic)
    }

    public func pending(profileKey: String) -> [PendingBrowserData] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix("\(profileKey).") && $0.hasSuffix(".json") }.sorted().compactMap {
            try? JSONDecoder().decode(PendingBrowserData.self, from: Data(contentsOf: directory.appendingPathComponent($0)))
        }
    }

    public func discard(_ data: PendingBrowserData, profileKey: String) {
        try? FileManager.default.removeItem(at: file(profileKey, data.batchID))
    }
}

public enum ChromiumWriteError: Error, Equatable, LocalizedError {
    case engineRunning
    case unreadableBookmarks
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .engineRunning: "The browser engine is using this Profile. History and bookmarks are imported at the next launch."
        case .unreadableBookmarks: "The Profile's bookmarks file could not be read, so it was left alone."
        case .writeFailed: "The Profile's history or bookmarks could not be written."
        }
    }
}

public struct ChromiumWriteResult: Equatable, Sendable {
    public var bookmarksAdded = 0
    public var historyAdded = 0
    public var historySkippedExisting = 0
    /// The History database does not exist yet (the Profile has never run) or has an unexpected layout.
    /// Nothing was written for history; keep the data staged and retry after the Profile has run once.
    public var historyDeferred = false
}

public enum ChromiumProfileWriter {
    /// Chromium's PageTransition LINK | CHAIN_START | CHAIN_END.
    private static let linkTransition: Int64 = 0x3000_0000
    private static let epochOffsetSeconds = 11_644_473_600.0
    static let batchKey = "bato_import_batch"

    /// Chromium locks its user data directory with a `SingletonLock` symlink to "host-pid".
    /// A lock whose process is gone is stale and does not count.
    public static func isInUse(userDataDirectory: URL) -> Bool {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(
            atPath: userDataDirectory.appendingPathComponent("SingletonLock").path),
              let pid = target.split(separator: "-").last.flatMap({ pid_t($0) }) else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    /// Writes into a profile no browser has open. History already present is never modified: a URL
    /// that exists keeps its own counts and the import only adds the ones missing.
    /// - Parameter lockIsOurs: the caller is the engine process itself and knows this Profile's context is not
    ///   open yet, so the user data directory's own lock does not count as another browser using it.
    public static func apply(_ data: PendingBrowserData, profileDirectory: URL, userDataDirectory: URL,
                             lockIsOurs: Bool = false) throws -> ChromiumWriteResult {
        guard lockIsOurs || !isInUse(userDataDirectory: userDataDirectory) else { throw ChromiumWriteError.engineRunning }
        var result = ChromiumWriteResult()
        result.bookmarksAdded = try writeBookmarks(data, profileDirectory: profileDirectory)
        if !data.history.isEmpty { try writeHistory(data.history, profileDirectory: profileDirectory, into: &result) }
        return result
    }

    private static func chromiumTime(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 + epochOffsetSeconds) * 1_000_000)
    }

    // MARK: History

    private static func writeHistory(_ entries: [ImportedHistoryEntry], profileDirectory: URL,
                                     into result: inout ChromiumWriteResult) throws {
        let file = profileDirectory.appendingPathComponent("History")
        guard FileManager.default.fileExists(atPath: file.path) else { result.historyDeferred = true; return }
        let database: SQLiteDatabase
        do { database = try SQLiteDatabase.open(file) } catch { throw ChromiumWriteError.writeFailed }
        let urlColumns: Set<String>, visitColumns: Set<String>
        do {
            urlColumns = try database.columns(of: "urls")
            visitColumns = try database.columns(of: "visits")
        } catch { throw ChromiumWriteError.writeFailed }
        guard urlColumns.isSuperset(of: ["id", "url", "title", "visit_count", "typed_count", "last_visit_time", "hidden"]),
              visitColumns.isSuperset(of: ["url", "visit_time", "transition"]) else {
            result.historyDeferred = true
            return
        }
        do {
            try database.execute("BEGIN IMMEDIATE")
            for entry in entries {
                let url = entry.url.absoluteString
                if try !database.rows("SELECT 1 FROM urls WHERE url = ?", [.text(url)]).isEmpty {
                    result.historySkippedExisting += 1
                    continue
                }
                let time = chromiumTime(entry.lastVisit)
                try database.execute("""
                    INSERT INTO urls(url, title, visit_count, typed_count, last_visit_time, hidden) VALUES (?, ?, ?, 0, ?, 0)
                    """, [.text(url), .text(entry.title), .int(Int64(max(entry.visitCount, 1))), .int(time)])
                try database.execute("""
                    INSERT INTO visits(url, visit_time, transition) VALUES ((SELECT id FROM urls WHERE url = ?), ?, ?)
                    """, [.text(url), .int(time), .int(linkTransition)])
                result.historyAdded += 1
            }
            try database.execute("COMMIT")
        } catch {
            try? database.execute("ROLLBACK")
            result.historyAdded = 0
            result.historySkippedExisting = 0
            throw ChromiumWriteError.writeFailed
        }
    }

    // MARK: Bookmarks

    private static func writeBookmarks(_ data: PendingBrowserData, profileDirectory: URL) throws -> Int {
        guard !data.bookmarks.isEmpty else { return 0 }
        let file = profileDirectory.appendingPathComponent("Bookmarks")
        var document: [String: Any]
        if FileManager.default.fileExists(atPath: file.path) {
            guard let bytes = try? Data(contentsOf: file),
                  let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  object["roots"] is [String: Any] else { throw ChromiumWriteError.unreadableBookmarks }
            document = object
        } else {
            document = skeleton()
        }
        var roots = document["roots"] as! [String: Any]
        var other = (roots["other"] as? [String: Any]) ?? skeletonRoot(id: "2", name: "Other bookmarks", type: "other")
        var children = other["children"] as? [[String: Any]] ?? []
        if children.contains(where: { ($0["meta_info"] as? [String: String])?[batchKey] == data.batchID }) { return 0 }

        var nextID = maxID(in: roots) + 1
        let now = String(chromiumTime(Date()))
        func convert(_ node: BookmarkNode) -> [String: Any] {
            let id = String(nextID)
            nextID += 1
            switch node {
            case .page(let page):
                return ["type": "url", "id": id, "guid": UUID().uuidString.lowercased(), "name": page.title.isEmpty ? page.url.host ?? "" : page.title,
                        "url": page.url.absoluteString, "date_added": now, "date_last_used": "0"]
            case .folder(let name, let inner):
                var folder: [String: Any] = ["type": "folder", "id": id, "guid": UUID().uuidString.lowercased(), "name": name,
                                             "date_added": now, "date_last_used": "0", "date_modified": now]
                folder["children"] = inner.map(convert)
                return folder
            }
        }
        var wrapper = convert(.folder(name: "Imported from \(data.source.displayName)", children: data.bookmarks))
        wrapper["meta_info"] = [batchKey: data.batchID]
        children.append(wrapper)
        other["children"] = children
        roots["other"] = other
        document["roots"] = roots
        document.removeValue(forKey: "checksum")

        do {
            if FileManager.default.fileExists(atPath: file.path) {
                let backup = profileDirectory.appendingPathComponent("Bookmarks.bato-pre-import")
                try? FileManager.default.removeItem(at: backup)
                try FileManager.default.copyItem(at: file, to: backup)
            }
            try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: file, options: .atomic)
        } catch { throw ChromiumWriteError.writeFailed }
        return data.bookmarks.reduce(0) { $0 + $1.pageCount }
    }

    private static func skeletonRoot(id: String, name: String, type: String) -> [String: Any] {
        ["type": "folder", "id": id, "guid": UUID().uuidString.lowercased(), "name": name, "children": [] as [Any],
         "date_added": String(chromiumTime(Date())), "date_modified": "0"]
    }

    private static func skeleton() -> [String: Any] {
        ["version": 1, "roots": ["bookmark_bar": skeletonRoot(id: "1", name: "Bookmarks bar", type: "bookmark_bar"),
                                 "other": skeletonRoot(id: "2", name: "Other bookmarks", type: "other"),
                                 "synced": skeletonRoot(id: "3", name: "Mobile bookmarks", type: "synced")]]
    }

    private static func maxID(in value: Any) -> Int {
        if let dictionary = value as? [String: Any] {
            let own = (dictionary["id"] as? String).flatMap(Int.init) ?? 0
            return dictionary.values.map { maxID(in: $0) }.max().map { max($0, own) } ?? own
        }
        if let array = value as? [Any] { return array.map { maxID(in: $0) }.max() ?? 0 }
        return 0
    }
}

public extension PendingImportStore {
    struct Outcome: Equatable, Sendable {
        public var batchID: String
        public var result: ChromiumWriteResult?
        public var error: ChromiumWriteError?
    }

    /// Call at launch for a Profile, before its engine context starts. A batch is discarded once its
    /// bookmarks and history are fully written; an engine-in-use or deferred batch stays staged.
    func applyPending(profileKey: String, profileDirectory: URL, userDataDirectory: URL, lockIsOurs: Bool = false) -> [Outcome] {
        pending(profileKey: profileKey).map { data in
            do {
                let result = try ChromiumProfileWriter.apply(data, profileDirectory: profileDirectory,
                                                             userDataDirectory: userDataDirectory, lockIsOurs: lockIsOurs)
                if !result.historyDeferred { discard(data, profileKey: profileKey) }
                return Outcome(batchID: data.batchID, result: result, error: nil)
            } catch let error as ChromiumWriteError {
                return Outcome(batchID: data.batchID, result: nil, error: error)
            } catch {
                return Outcome(batchID: data.batchID, result: nil, error: .writeFailed)
            }
        }
    }
}

public extension PendingImportStore {
    /// The engine's directory layout: the launch Profile lives in `<root>/Default`, every other Profile in
    /// `<root>/<key>`. The launch Profile is applied before the engine initializes, others right before their
    /// context is created, so Chromium has not opened either one yet. Failures keep the batch staged.
    func applyBeforeEngineOpens(profileKey: String, isLaunchProfile: Bool, userDataDirectory: URL) -> [Outcome] {
        let profileDirectory = userDataDirectory.appendingPathComponent(isLaunchProfile ? "Default" : profileKey, isDirectory: true)
        return applyPending(profileKey: profileKey, profileDirectory: profileDirectory,
                            userDataDirectory: userDataDirectory, lockIsOurs: !isLaunchProfile)
    }
}
