import Foundation

public enum SettingsPane: String, CaseIterable, Sendable {
    case general, profiles, privacy, archive, importData, shortcuts, advanced, about

    public var title: String {
        switch self {
        case .general: "General"
        case .profiles: "Profiles"
        case .privacy: "Privacy"
        case .archive: "Archive"
        case .importData: "Import"
        case .shortcuts: "Shortcuts"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    public var symbolName: String {
        switch self {
        case .general: "magnifyingglass"
        case .profiles: "person.crop.circle"
        case .privacy: "hand.raised"
        case .archive: "archivebox"
        case .importData: "square.and.arrow.down"
        case .shortcuts: "keyboard"
        case .advanced: "gearshape.2"
        case .about: "info.circle"
        }
    }
}

public struct SettingsProfileRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let colorHex: String
    public let workspaceCount: Int
    public let isCurrent: Bool

    public var detail: String {
        let spaces = workspaceCount == 1 ? "1 workspace" : "\(workspaceCount) workspaces"
        return isCurrent ? "Current · \(spaces)" : spaces
    }

    public static func rows(from state: BrowserState) -> [SettingsProfileRow] {
        let current = state.currentWorkspace.profileID
        return state.profiles.map { profile in
            SettingsProfileRow(id: profile.id, name: profile.name, colorHex: state.displayColor(of: profile),
                               workspaceCount: state.workspaces.filter { $0.profileID == profile.id }.count,
                               isCurrent: profile.id == current)
        }
    }
}

public struct ShortcutRow: Equatable, Sendable {
    public let title: String
    public let keys: String
}

public enum ShortcutCatalog {
    public static let rows: [ShortcutRow] = [
        ShortcutRow(title: "New tab or command bar", keys: "⌘T"),
        ShortcutRow(title: "Go to address in this page", keys: "⌘L"),
        ShortcutRow(title: "Close page", keys: "⌘W"),
        ShortcutRow(title: "Toggle sidebar", keys: "⌘S"),
        ShortcutRow(title: "Copy page URL", keys: "⇧⌘C"),
        ShortcutRow(title: "Open Peek as tab", keys: "⌥⌘↩"),
        ShortcutRow(title: "Switch Profile", keys: "⌃1–9"),
        ShortcutRow(title: "History", keys: "⌘Y"),
        ShortcutRow(title: "Downloads", keys: "⇧⌘J"),
        ShortcutRow(title: "Settings", keys: "⌘,"),
    ]
}

public struct AboutInfo: Equatable, Sendable {
    public static let developmentVersion = "development"
    public static let noticesURL = URL(string: "https://github.com/itsbohara/bato/blob/main/NOTICES.md")!

    public let version: String
    public let build: String?

    /// The packaged app carries the repo's `VERSION` file as its bundle version; a bare VERSION file is the
    /// fallback for unpackaged runs. Blank values count as missing.
    public init(bundleVersion: String?, bundleBuild: String?, versionFileText: String?) {
        func clean(_ text: String?) -> String? {
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        version = clean(bundleVersion) ?? clean(versionFileText) ?? Self.developmentVersion
        build = clean(bundleBuild)
    }

    public var displayVersion: String { build.map { "\(version) (\($0))" } ?? version }
}
