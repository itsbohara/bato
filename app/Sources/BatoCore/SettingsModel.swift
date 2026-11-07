import Foundation

public enum SettingsPane: String, CaseIterable, Sendable {
    case profiles, privacy, importData, shortcuts, advanced

    public var title: String {
        switch self {
        case .profiles: "Profiles"
        case .privacy: "Privacy"
        case .importData: "Import"
        case .shortcuts: "Shortcuts"
        case .advanced: "Advanced"
        }
    }

    public var symbolName: String {
        switch self {
        case .profiles: "person.crop.circle"
        case .privacy: "hand.raised"
        case .importData: "square.and.arrow.down"
        case .shortcuts: "keyboard"
        case .advanced: "gearshape.2"
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
