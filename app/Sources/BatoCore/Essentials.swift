import Foundation

/// Browser pages that Chromium already provides. Bato opens them as ordinary organized tabs
/// in the current Profile, so history and downloads stay per Profile and a repeat shortcut
/// returns to the tab it opened.
public enum BrowserEssential: String, CaseIterable, Sendable {
    case history, downloads, chromiumSettings, sitePermissions

    public var url: URL {
        switch self {
        case .history: URL(string: "chrome://history/")!
        case .downloads: URL(string: "chrome://downloads/")!
        case .chromiumSettings: URL(string: "chrome://settings/")!
        case .sitePermissions: URL(string: "chrome://settings/content")!
        }
    }

    public var title: String {
        switch self {
        case .history: "History"
        case .downloads: "Downloads"
        case .chromiumSettings: "Browser Settings"
        case .sitePermissions: "Site Settings"
        }
    }

    /// The only non-web destinations Bato will save in organization or hand to the engine. Settings is
    /// the one page that can be browsed further: its site-permission subtree, so a page's site settings
    /// and the all-sites list are rows too, with at most a `site` origin in the query.
    public static func accepts(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "chrome", url.user == nil, url.password == nil,
              url.fragment == nil, let host = url.host?.lowercased(),
              allCases.contains(where: { $0.url.host == host }) else { return false }
        if host == "settings", isSiteSettingsPath(url.path) {
            return url.query == nil || (url.path == "/content/siteDetails" && siteOrigin(inQuery: url) != nil)
        }
        return url.query == nil && (url.path.isEmpty || url.path == "/")
    }

    public static func matching(_ url: URL) -> BrowserEssential? {
        guard accepts(url) else { return nil }
        if url.host?.lowercased() == "settings", isSiteSettingsPath(url.path) { return .sitePermissions }
        return allCases.first { $0.url.host == url.host?.lowercased() && $0 != .sitePermissions }
    }

    /// Chromium's per-site page for the page's origin, or the all-sites list when the page has no web origin.
    public static func siteSettingsURL(for page: URL?) -> URL {
        guard let page, let scheme = page.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = page.host, !host.isEmpty else { return sitePermissions.url }
        let origin = "\(scheme)://\(host)" + (page.port.map { ":\($0)" } ?? "")
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = origin.addingPercentEncoding(withAllowedCharacters: unreserved) ?? origin
        return URL(string: "chrome://settings/content/siteDetails?site=\(encoded)") ?? sitePermissions.url
    }

    private static func isSiteSettingsPath(_ path: String) -> Bool {
        path == "/content" || path.hasPrefix("/content/") && path.dropFirst("/content/".count)
            .allSatisfy { $0.isLetter || $0.isNumber || $0 == "/" }
    }

    private static func siteOrigin(inQuery url: URL) -> URL? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems, items.count == 1,
              items[0].name == "site", let value = items[0].value, let origin = URL(string: value),
              ["http", "https"].contains(origin.scheme?.lowercased() ?? ""), origin.host?.isEmpty == false,
              origin.user == nil, origin.password == nil, origin.query == nil, origin.fragment == nil,
              origin.path.isEmpty else { return nil }
        return origin
    }
}

extension BrowserState {
    /// The current Workspace's tab for an essential, if one is already open.
    public func openEssentialEntry(_ essential: BrowserEssential) -> PageEntry? {
        visibleEntries.first { BrowserEssential.matching($0.lastURL) == essential }
    }
}
