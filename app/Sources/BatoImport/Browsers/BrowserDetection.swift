import Foundation

public struct DetectedProfile: Equatable, Sendable {
    /// Stable within one browser: the profile directory name.
    public var id: String
    public var name: String
    public var directory: URL
}

public struct DetectedBrowser: Equatable, Sendable {
    public var source: ImportSource
    public var profiles: [DetectedProfile]
    /// What a reader exists for. Counts and permission state come from `BrowserImporter.counts`.
    public var supportedItems: [ImportItem]
    /// Content-free limits worth showing under the browser's name.
    public var notes: [String]

    /// "Favorites, bookmarks, history" for the browser row.
    public var subtitle: String {
        let names: [ImportItem: String] = [.favorites: "Favorites", .bookmarks: "bookmarks", .history: "history",
                                           .spaces: "Spaces"]
        let list = supportedItems.compactMap { names[$0] }
        return list.isEmpty ? "Nothing to import yet" : list.joined(separator: ", ")
    }
}

/// Finds installed browsers and their profile lists. Only the profile list files (Chromium
/// `Local State`, Gecko `profiles.ini`) are read, never browsing content. Safari is reported when its
/// app exists, since its data folder is protected and cannot be listed without Full Disk Access.
public struct BrowserDetector: Sendable {
    public var home: URL
    public var applicationDirectories: [URL]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                applicationDirectories: [URL] = [URL(fileURLWithPath: "/Applications"),
                                                 URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications"),
                                                 FileManager.default.homeDirectoryForCurrentUser
                                                     .appendingPathComponent("Applications")]) {
        self.home = home
        self.applicationDirectories = applicationDirectories
    }

    public func detect() -> [DetectedBrowser] {
        ImportSource.allCases.compactMap(detect)
    }

    public func detect(_ source: ImportSource) -> DetectedBrowser? {
        let fileManager = FileManager.default
        let root = BrowserLocations.dataRoot(source, home: home)
        let installed = BrowserLocations.appNames(source).contains { name in
            applicationDirectories.contains { fileManager.fileExists(atPath: $0.appendingPathComponent(name).path) }
        }
        let hasData = source != .safari && fileManager.fileExists(atPath: root.path)
        guard installed || hasData else { return nil }
        let profiles: [DetectedProfile]
        switch source {
        case _ where source.isChromium: profiles = chromiumProfiles(root)
        case _ where source.isGecko: profiles = geckoProfiles(root)
        case .safari: profiles = [DetectedProfile(id: "Default", name: "Safari", directory: root)]
        default: profiles = hasData ? [DetectedProfile(id: "Default", name: "Orion", directory: root)] : []
        }
        return DetectedBrowser(source: source, profiles: profiles, supportedItems: BrowserLocations.supportedItems(source),
                               notes: BrowserLocations.notes(source))
    }

    private func chromiumProfiles(_ root: URL) -> [DetectedProfile] {
        let fileManager = FileManager.default
        var named: [(String, String)] = []
        if let data = try? Data(contentsOf: root.appendingPathComponent("Local State")),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let cache = (object["profile"] as? [String: Any])?["info_cache"] as? [String: Any] {
            named = cache.keys.sorted { Self.profileOrder($0, $1) }.map { key in
                (key, ((cache[key] as? [String: Any])?["name"] as? String) ?? key)
            }
        }
        if named.isEmpty, fileManager.fileExists(atPath: root.appendingPathComponent("Default").path) {
            named = [("Default", "Default")]
        }
        return named.filter { fileManager.fileExists(atPath: root.appendingPathComponent($0.0).path) }
            .map { DetectedProfile(id: $0.0, name: $0.1, directory: root.appendingPathComponent($0.0)) }
    }

    /// Default first, then Profile 1, Profile 2, ... numerically.
    private static func profileOrder(_ left: String, _ right: String) -> Bool {
        if left == "Default" || right == "Default" { return left == "Default" && right != "Default" }
        return left.localizedStandardCompare(right) == .orderedAscending
    }

    private func geckoProfiles(_ root: URL) -> [DetectedProfile] {
        guard let text = try? String(contentsOf: root.appendingPathComponent("profiles.ini"), encoding: .utf8) else { return [] }
        var sections: [[String: String]] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { sections.append(["section": trimmed]) }
            else if let equals = trimmed.firstIndex(of: "="), !sections.isEmpty {
                sections[sections.count - 1][String(trimmed[..<equals])] = String(trimmed[trimmed.index(after: equals)...])
            }
        }
        let profiles = sections.compactMap { section -> (DetectedProfile, Bool)? in
            guard section["section"]?.hasPrefix("[Profile") == true, let path = section["Path"] else { return nil }
            let directory = section["IsRelative"] == "0" ? URL(fileURLWithPath: path)
                : root.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
            return (DetectedProfile(id: directory.lastPathComponent, name: section["Name"] ?? path, directory: directory),
                    section["Default"] == "1")
        }
        return profiles.filter(\.1).map(\.0) + profiles.filter { !$0.1 }.map(\.0)
    }
}

enum BrowserLocations {
    static func dataRoot(_ source: ImportSource, home: URL) -> URL {
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        switch source {
        case .chrome: return support.appendingPathComponent("Google/Chrome")
        case .brave: return support.appendingPathComponent("BraveSoftware/Brave-Browser")
        case .edge: return support.appendingPathComponent("Microsoft Edge")
        case .dia: return support.appendingPathComponent("Dia/User Data")
        case .arc: return support.appendingPathComponent("Arc/User Data")
        case .safari: return home.appendingPathComponent("Library/Safari")
        case .firefox: return support.appendingPathComponent("Firefox")
        case .zen: return support.appendingPathComponent("zen")
        case .orion: return support.appendingPathComponent("Orion")
        }
    }

    static func arcSidebarFile(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Arc/StorableSidebar.json")
    }

    static func appNames(_ source: ImportSource) -> [String] {
        switch source {
        case .edge: ["Microsoft Edge.app"]
        case .brave: ["Brave Browser.app"]
        case .chrome: ["Google Chrome.app"]
        default: ["\(source.displayName).app"]
        }
    }

    static func supportedItems(_ source: ImportSource) -> [ImportItem] {
        switch source {
        case .arc: [.favorites, .spaces, .history]
        case .zen: [.favorites, .spaces, .bookmarks, .history]
        case .orion: []
        default: [.favorites, .bookmarks, .history]
        }
    }

    static func notes(_ source: ImportSource) -> [String] {
        switch source {
        case .arc: ["Arc keeps bookmarks in Spaces, so Spaces carry the pinned items."]
        case .dia: ["Dia's own sidebar and pinned tabs have no documented file format; bookmarks and history are read."]
        case .safari: ["Needs Full Disk Access."]
        case .zen: ["Workspaces and pinned tabs are read from Zen's places database."]
        case .orion: ["Orion's data format is not documented; export bookmarks from Orion to an HTML file instead."]
        default: []
        }
    }
}
