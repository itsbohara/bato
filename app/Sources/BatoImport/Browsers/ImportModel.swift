import Foundation

/// Browsers the onboarding "Bring everything over" step can read from.
public enum ImportSource: String, CaseIterable, Codable, Sendable {
    case dia, arc, chrome, brave, edge, safari, firefox, zen, orion

    public var displayName: String {
        switch self {
        case .dia: "Dia"
        case .arc: "Arc"
        case .chrome: "Chrome"
        case .brave: "Brave"
        case .edge: "Edge"
        case .safari: "Safari"
        case .firefox: "Firefox"
        case .zen: "Zen"
        case .orion: "Orion"
        }
    }

    var isChromium: Bool { [.dia, .arc, .chrome, .brave, .edge].contains(self) }
    var isGecko: Bool { self == .firefox || self == .zen }
}

public enum ImportItem: String, CaseIterable, Codable, Sendable {
    /// Arc Favorites, Zen Essentials, or the bookmarks bar of every other browser.
    case favorites
    /// Every other bookmark, with its folders.
    case bookmarks
    case history
    /// Arc Spaces with pinned items and folders, Zen workspaces with pinned tabs.
    case spaces
}

public enum ItemAvailability: Equatable, Sendable {
    case available(Int)
    /// macOS blocks reading this data until the app has Full Disk Access.
    case needsFullDiskAccess
    case unsupported(String)
    case missing
}

public struct ImportedPage: Codable, Equatable, Sendable {
    public var title: String
    public var url: URL
}

public indirect enum BookmarkNode: Codable, Equatable, Sendable {
    case page(ImportedPage)
    case folder(name: String, children: [BookmarkNode])

    public var pageCount: Int {
        switch self {
        case .page: 1
        case .folder(_, let children): children.reduce(0) { $0 + $1.pageCount }
        }
    }
}

public struct ImportedHistoryEntry: Codable, Equatable, Sendable {
    public var url: URL
    public var title: String
    public var visitCount: Int
    public var lastVisit: Date
}

/// The versioned intermediate model every reader produces and every apply path consumes.
/// It holds no passwords, cookies or form data.
public struct BrowserSnapshot: Sendable {
    public static let schemaVersion = 1

    public var source: ImportSource
    public var profileID: String
    public var favorites: [ImportedPage] = []
    public var bookmarks: [BookmarkNode] = []
    public var history: [ImportedHistoryEntry] = []
    /// Spaces, pinned items, folders and per-profile Favorites (Arc, Zen).
    public var spaces: ArcStaging?
    /// Content-free, human-readable limits of what was read.
    public var notes: [String] = []

    public var bookmarkCount: Int { bookmarks.reduce(0) { $0 + $1.pageCount } }
}

public enum ImportReadError: Error, Equatable, LocalizedError {
    case permissionDenied
    case unreadable
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: "macOS blocked reading this browser's data."
        case .unreadable: "The browser's data could not be read."
        case .unsupported(let note): note
        }
    }
}

extension URL {
    var isWebURL: Bool {
        guard let scheme = scheme?.lowercased(), ["http", "https"].contains(scheme) else { return false }
        return host?.isEmpty == false && user == nil && password == nil
    }

    /// Key for duplicate detection: scheme and host case-insensitive, no fragment, no trailing slash.
    var duplicateKey: String {
        guard var parts = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return absoluteString }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        parts.fragment = nil
        var text = parts.string ?? absoluteString
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }
}
