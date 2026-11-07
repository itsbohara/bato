import Foundation

/// Browser pages that Chromium already provides. Bato opens them as ordinary organized tabs
/// in the current Profile, so history and downloads stay per Profile and a repeat shortcut
/// returns to the tab it opened.
public enum BrowserEssential: String, CaseIterable, Sendable {
    case history, downloads, chromiumSettings

    public var url: URL {
        switch self {
        case .history: URL(string: "chrome://history/")!
        case .downloads: URL(string: "chrome://downloads/")!
        case .chromiumSettings: URL(string: "chrome://settings/")!
        }
    }

    public var title: String {
        switch self {
        case .history: "History"
        case .downloads: "Downloads"
        case .chromiumSettings: "Browser Settings"
        }
    }

    /// The only non-web destinations Bato will save in organization or hand to the engine.
    public static func accepts(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "chrome", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, let host = url.host?.lowercased() else { return false }
        return allCases.contains { $0.url.host == host } && (url.path.isEmpty || url.path == "/")
    }

    public static func matching(_ url: URL) -> BrowserEssential? {
        accepts(url) ? allCases.first { $0.url.host == url.host?.lowercased() } : nil
    }
}

extension BrowserState {
    /// The current Workspace's tab for an essential, if one is already open.
    public func openEssentialEntry(_ essential: BrowserEssential) -> PageEntry? {
        visibleEntries.first { BrowserEssential.matching($0.lastURL) == essential }
    }
}
