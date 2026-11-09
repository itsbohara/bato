import Foundation
import XCTest
@testable import BatoImport

/// Synthetic browser data in a fake home directory. Nothing here comes from a real browser.
final class FakeHome {
    let root: URL
    var support: URL { root.appendingPathComponent("Library/Application Support") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("bato-fakehome-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        chmodRecursively()
        try? FileManager.default.removeItem(at: root)
    }

    private func chmodRecursively() {
        for case let url as URL in FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) ?? NSEnumerator() {
            chmod(url.path, 0o700)
        }
    }

    @discardableResult
    func write(_ path: String, _ text: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func database(_ path: String, _ statements: [String]) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let database = try SQLiteDatabase.open(url, create: true)
        for statement in statements { try database.execute(statement) }
        return url
    }

    // MARK: Chromium

    static let chromiumBookmarks = """
    {"roots":{
      "bookmark_bar":{"type":"folder","name":"Bookmarks bar","children":[
        {"type":"url","name":"Swift","url":"https://swift.org/"},
        {"type":"url","name":"Bookmarklet","url":"javascript:alert(1)"},
        {"type":"url","name":"Apple","url":"https://apple.com/"},
        {"type":"folder","name":"Dev","children":[
          {"type":"url","name":"GitHub","url":"https://github.com/"},
          {"type":"folder","name":"Empty","children":[]}]}]},
      "other":{"type":"folder","name":"Other","children":[{"type":"url","name":"Caf\\u00e9","url":"https://example.com/caf\\u00e9"}]},
      "synced":{"type":"folder","name":"Mobile","children":[]}}}
    """

    /// Chromium time: microseconds since 1601-01-01.
    static func chromiumTime(_ unix: Double) -> Int64 { Int64((unix + 11_644_473_600) * 1_000_000) }

    static let chromiumHistorySQL = [
        "CREATE TABLE urls(id INTEGER PRIMARY KEY AUTOINCREMENT, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0 NOT NULL, typed_count INTEGER DEFAULT 0 NOT NULL, last_visit_time INTEGER NOT NULL, hidden INTEGER DEFAULT 0 NOT NULL)",
        "CREATE TABLE visits(id INTEGER PRIMARY KEY, url INTEGER NOT NULL, visit_time INTEGER NOT NULL, from_visit INTEGER, transition INTEGER DEFAULT 0 NOT NULL, segment_id INTEGER, visit_duration INTEGER DEFAULT 0 NOT NULL, incremented_omnibox_typed_score BOOLEAN DEFAULT FALSE NOT NULL)",
        "CREATE TABLE meta(key LONGVARCHAR NOT NULL UNIQUE PRIMARY KEY, value LONGVARCHAR)",
        "INSERT INTO urls(url,title,visit_count,last_visit_time,hidden) VALUES ('https://swift.org/','Swift',3,\(chromiumTime(1_700_000_000)),0)",
        "INSERT INTO urls(url,title,visit_count,last_visit_time,hidden) VALUES ('https://example.com/a','A',1,\(chromiumTime(1_700_000_100)),0)",
        "INSERT INTO urls(url,title,visit_count,last_visit_time,hidden) VALUES ('chrome://settings/','Settings',5,\(chromiumTime(1_700_000_200)),0)",
        "INSERT INTO urls(url,title,visit_count,last_visit_time,hidden) VALUES ('https://frame.example/','Frame',2,\(chromiumTime(1_700_000_300)),1)",
    ]

    func addChrome(profiles: [(String, String)] = [("Default", "Person 1")]) throws {
        let cache = profiles.map { "\"\($0.0)\":{\"name\":\"\($0.1)\"}" }.joined(separator: ",")
        try write("Library/Application Support/Google/Chrome/Local State", "{\"profile\":{\"info_cache\":{\(cache)}}}")
        for (directory, _) in profiles {
            try write("Library/Application Support/Google/Chrome/\(directory)/Bookmarks", Self.chromiumBookmarks)
            _ = try database("Library/Application Support/Google/Chrome/\(directory)/History", Self.chromiumHistorySQL)
        }
    }

    // MARK: Safari

    static let safariBookmarks = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict><key>WebBookmarkType</key><string>WebBookmarkTypeList</string><key>Children</key><array>
    <dict><key>Title</key><string>History</string><key>WebBookmarkType</key><string>WebBookmarkTypeProxy</string></dict>
    <dict><key>Title</key><string>BookmarksBar</string><key>WebBookmarkType</key><string>WebBookmarkTypeList</string><key>Children</key><array>
      <dict><key>WebBookmarkType</key><string>WebBookmarkTypeLeaf</string><key>URLString</key><string>https://apple.com/</string><key>URIDictionary</key><dict><key>title</key><string>Apple</string></dict></dict>
      <dict><key>Title</key><string>Reads</string><key>WebBookmarkType</key><string>WebBookmarkTypeList</string><key>Children</key><array>
        <dict><key>WebBookmarkType</key><string>WebBookmarkTypeLeaf</string><key>URLString</key><string>https://news.example/</string><key>URIDictionary</key><dict><key>title</key><string>News</string></dict></dict>
      </array></dict></array></dict>
    <dict><key>Title</key><string>com.apple.ReadingList</string><key>WebBookmarkType</key><string>WebBookmarkTypeList</string><key>Children</key><array>
      <dict><key>WebBookmarkType</key><string>WebBookmarkTypeLeaf</string><key>URLString</key><string>https://later.example/</string><key>URIDictionary</key><dict><key>title</key><string>Later</string></dict></dict>
    </array></dict></array></dict></plist>
    """

    static func appleTime(_ unix: Double) -> Double { unix - 978_307_200 }

    func addSafari() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Applications/Safari.app"), withIntermediateDirectories: true)
        try write("Library/Safari/Bookmarks.plist", Self.safariBookmarks)
        _ = try database("Library/Safari/History.db", [
            "CREATE TABLE history_items(id INTEGER PRIMARY KEY, url TEXT NOT NULL, visit_count INTEGER NOT NULL)",
            "CREATE TABLE history_visits(id INTEGER PRIMARY KEY, history_item INTEGER NOT NULL, visit_time REAL NOT NULL, title TEXT)",
            "INSERT INTO history_items VALUES (1,'https://apple.com/',2)",
            "INSERT INTO history_items VALUES (2,'https://news.example/',1)",
            "INSERT INTO history_items VALUES (3,'file:///tmp/x',1)",
            "INSERT INTO history_visits VALUES (1,1,\(Self.appleTime(1_700_000_000)),'Old Apple')",
            "INSERT INTO history_visits VALUES (2,1,\(Self.appleTime(1_700_000_500)),'Apple')",
            "INSERT INTO history_visits VALUES (3,2,\(Self.appleTime(1_700_000_100)),'News')",
        ])
    }

    // MARK: Gecko

    static let placesSQL = [
        "CREATE TABLE moz_places(id INTEGER PRIMARY KEY, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0, hidden INTEGER DEFAULT 0 NOT NULL, last_visit_date INTEGER)",
        "CREATE TABLE moz_bookmarks(id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER DEFAULT NULL, parent INTEGER, position INTEGER, title LONGVARCHAR, guid TEXT)",
        "INSERT INTO moz_places VALUES (1,'https://mozilla.org/','Mozilla',4,0,1700000000000000)",
        "INSERT INTO moz_places VALUES (2,'https://example.com/b','B',1,0,1700000100000000)",
        "INSERT INTO moz_places VALUES (3,'place:type=6','Recent',9,0,1700000200000000)",
        "INSERT INTO moz_bookmarks VALUES (1,2,NULL,0,0,'','root________')",
        "INSERT INTO moz_bookmarks VALUES (2,2,NULL,1,0,'toolbar','toolbar_____')",
        "INSERT INTO moz_bookmarks VALUES (3,2,NULL,1,1,'menu','menu________')",
        "INSERT INTO moz_bookmarks VALUES (4,2,NULL,1,2,'unfiled','unfiled_____')",
        "INSERT INTO moz_bookmarks VALUES (5,1,1,2,0,'Mozilla','aaaaaaaaaaaa')",
        "INSERT INTO moz_bookmarks VALUES (6,2,NULL,3,0,'Folder','bbbbbbbbbbbb')",
        "INSERT INTO moz_bookmarks VALUES (7,1,2,6,0,'B','cccccccccccc')",
    ]

    func addFirefox() throws {
        try write("Library/Application Support/Firefox/profiles.ini", """
        [Profile1]
        Name=old
        IsRelative=1
        Path=Profiles/old.default

        [Profile0]
        Name=default-release
        IsRelative=1
        Path=Profiles/abc.default-release
        Default=1
        """)
        try FileManager.default.createDirectory(at: support.appendingPathComponent("Firefox/Profiles/old.default"), withIntermediateDirectories: true)
        _ = try database("Library/Application Support/Firefox/Profiles/abc.default-release/places.sqlite", Self.placesSQL)
    }

    func addZen() throws {
        try write("Library/Application Support/zen/profiles.ini", "[Profile0]\nName=Default\nIsRelative=1\nPath=Profiles/z.Default\nDefault=1\n")
        _ = try database("Library/Application Support/zen/Profiles/z.Default/places.sqlite", Self.placesSQL + [
            "CREATE TABLE zen_workspaces(id INTEGER PRIMARY KEY, uuid TEXT UNIQUE, name TEXT, container_id INTEGER, position INTEGER)",
            "CREATE TABLE zen_pins(id INTEGER PRIMARY KEY, uuid TEXT UNIQUE, title TEXT, url TEXT, container_id INTEGER, workspace_uuid TEXT, position INTEGER, is_essential INTEGER, is_group INTEGER, folder_parent_uuid TEXT)",
            "INSERT INTO zen_workspaces VALUES (1,'ws-a','Work',0,0)",
            "INSERT INTO zen_workspaces VALUES (2,'ws-b','Play',2,1)",
            "INSERT INTO zen_pins VALUES (1,'p1','Docs','https://docs.example/',0,'ws-a',0,0,0,NULL)",
            "INSERT INTO zen_pins VALUES (2,'g1','Group',NULL,0,'ws-a',1,0,1,NULL)",
            "INSERT INTO zen_pins VALUES (3,'p2','Inside','https://inside.example/',0,'ws-a',0,0,0,'g1')",
            "INSERT INTO zen_pins VALUES (4,'p3','Game','https://game.example/',2,'ws-b',0,0,0,NULL)",
            "INSERT INTO zen_pins VALUES (5,'e1','Mail','https://mail.example/',0,'ws-a',0,1,0,NULL)",
            "INSERT INTO zen_pins VALUES (6,'p4','Internal','about:preferences',0,'ws-a',3,0,0,NULL)",
        ])
    }

    // MARK: Arc

    func addArc(sidebar: URL) throws {
        let target = support.appendingPathComponent("Arc/StorableSidebar.json")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sidebar, to: target)
        try write("Library/Application Support/Arc/User Data/Local State", "{\"profile\":{\"info_cache\":{\"Default\":{\"name\":\"Arc\"}}}}")
        _ = try database("Library/Application Support/Arc/User Data/Default/History", Self.chromiumHistorySQL)
    }
}
