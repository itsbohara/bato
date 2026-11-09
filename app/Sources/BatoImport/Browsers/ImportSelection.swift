import Foundation

extension ImportSource {
    /// The browser a macOS bundle identifier belongs to, for spotting the current default browser.
    public init?(bundleIdentifier: String) {
        let known: [String: ImportSource] = [
            "com.google.Chrome": .chrome, "com.brave.Browser": .brave, "com.microsoft.edgemac": .edge,
            "company.thebrowser.Browser": .arc, "company.thebrowser.dia": .dia, "com.apple.Safari": .safari,
            "org.mozilla.firefox": .firefox, "app.zen-browser.zen": .zen, "com.kagi.kagimacOS": .orion,
        ]
        guard let source = known[bundleIdentifier] else { return nil }
        self = source
    }
}

/// One card of the "Bring everything over" grid.
public struct BrowserChoice: Equatable, Sendable {
    public let source: ImportSource
    public let subtitle: String
    public let isCurrentDefault: Bool

    public var name: String { source.displayName }

    public static func choices(from detected: [DetectedBrowser], defaultSource: ImportSource?) -> [BrowserChoice] {
        detected.map { BrowserChoice(source: $0.source, subtitle: $0.subtitle, isCurrentDefault: $0.source == defaultSource) }
    }
}

/// The toggle list shown after a browser is chosen: one row per supported item, switched on when it has something to bring.
public struct ImportSelection: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let item: ImportItem
        public let title: String
        public let detail: String
        public let count: Int?
        public var isOn: Bool
        public var isEnabled: Bool { count.map { $0 > 0 } ?? false }
    }

    public enum Access: Equatable, Sendable {
        case ready
        case needsFullDiskAccess
        case nothingToImport
    }

    public let source: ImportSource
    public private(set) var rows: [Row]
    public let access: Access

    public init(source: ImportSource, counts: [ImportItem: ItemAvailability], locale: Locale = .current) {
        self.source = source
        let order: [ImportItem] = [.favorites, .bookmarks, .history, .spaces]
        let present = order.filter { counts[$0] != nil }
        rows = present.map { item in
            let count: Int?
            if case .available(let value) = counts[item] { count = value } else { count = nil }
            return Row(item: item, title: Self.title(item), detail: Self.detail(item, counts[item]!, locale: locale),
                       count: count, isOn: (count ?? 0) > 0)
        }
        if counts.values.contains(.needsFullDiskAccess) {
            access = .needsFullDiskAccess
        } else {
            access = rows.contains { $0.isEnabled } ? .ready : .nothingToImport
        }
    }

    public mutating func toggle(_ item: ImportItem) {
        guard let index = rows.firstIndex(where: { $0.item == item }), rows[index].isEnabled else { return }
        rows[index].isOn.toggle()
    }

    public var selectedItems: Set<ImportItem> { Set(rows.filter { $0.isOn && $0.isEnabled }.map(\.item)) }
    public var canContinue: Bool { access == .ready && !selectedItems.isEmpty }

    private static func title(_ item: ImportItem) -> String {
        switch item {
        case .favorites: "Favorites"
        case .bookmarks: "Bookmarks"
        case .history: "History"
        case .spaces: "Spaces"
        }
    }

    private static func detail(_ item: ImportItem, _ availability: ItemAvailability, locale: Locale) -> String {
        switch availability {
        case .available(let count):
            let number = count.formatted(.number.locale(locale))
            switch item {
            case .favorites, .bookmarks: return count == 1 ? "1 site" : "\(number) sites"
            case .history: return count == 1 ? "1 page" : "\(number) pages"
            case .spaces: return count == 1 ? "1 space" : "\(number) spaces"
            }
        case .needsFullDiskAccess: return "Needs Full Disk Access"
        case .unsupported(let note): return note
        case .missing: return "Nothing found"
        }
    }
}
