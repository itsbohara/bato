import Foundation

public enum CommandBarDestination: Equatable, Sendable {
    case empty
    case navigate(URL)
    case search(URL)
    case invalid(String)
}

/// Provider selection is owned by the UI; DuckDuckGo is the alpha default.
public enum CommandBarSearchProvider: String, CaseIterable, Sendable {
    case duckDuckGo, google
    public var title: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo"
        case .google: "Google"
        }
    }
    public var endpoint: URL {
        switch self {
        case .duckDuckGo: URL(string: "https://duckduckgo.com/")!
        case .google: URL(string: "https://www.google.com/search")!
        }
    }
}

/// Local input classification only. No query or page data is sent until Open.
public enum CommandBarInput {
    public static func resolve(_ input: String, provider: CommandBarSearchProvider = .duckDuckGo) -> CommandBarDestination {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }
        guard !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return .invalid("Enter an address or search without control characters.")
        }
        let authority = String(text.prefix { !"/?#".contains($0) })
        let isBareAddress = !authority.contains(where: { $0.isWhitespace }) &&
            (authority.contains(".") || authority == "localhost" || authority.hasPrefix("localhost:") || authority.hasPrefix("["))
        // A domain/localhost port is not an explicit URI scheme.
        let colonPrefix = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let schemeLike = text.contains(":") && colonPrefix.range(of: "^[A-Za-z][A-Za-z0-9+.-]*$", options: .regularExpression) != nil
        let portSuffix = authority.split(separator: ":", omittingEmptySubsequences: false).last ?? ""
        let barePort = isBareAddress && !portSuffix.isEmpty && portSuffix.allSatisfy(\.isNumber)
        let explicit = schemeLike && !barePort
        if explicit || isBareAddress {
            if explicit && !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
                return .invalid("Only HTTP and HTTPS addresses can be opened.")
            }
            let value = explicit ? text : "https://" + text
            guard !text.contains(where: { $0.isWhitespace }), !text.contains("\\"),
                  let components = URLComponents(string: value),
                  ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
                  components.user == nil, components.password == nil,
                  let host = components.host, !host.isEmpty,
                  !host.contains("%"), !host.contains(".."),
                  components.port.map({ (1...65535).contains($0) }) ?? true,
                  let url = components.url else {
                return .invalid("Enter a valid HTTP or HTTPS address without sign-in details.")
            }
            return .navigate(url)
        }
        var search = URLComponents(url: provider.endpoint, resolvingAgainstBaseURL: false)!
        search.queryItems = [URLQueryItem(name: "q", value: text)]
        // Search endpoints decode form queries, where a literal + means space.
        // URLComponents uses RFC 3986 and leaves + unescaped by default.
        search.percentEncodedQuery = search.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return .search(search.url!)
    }
}

public enum CommandBarCommand: String, CaseIterable, Sendable {
    case findPage, toggleSidebar, closePage
    public var title: String {
        switch self {
        case .findPage: "Find Page"
        case .toggleSidebar: "Toggle Sidebar"
        case .closePage: "Close Current Page"
        }
    }
}

public enum CommandBarAction: Equatable, Sendable {
    case open(URL)
    case activate(PageSearchResult)
    case command(CommandBarCommand)
}

public struct CommandBarResult: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let action: CommandBarAction
}

public enum CommandBarResults {
    /// Stable IDs let the UI preserve selection while organization events arrive.
    /// Results never mutate state; activation must revalidate through PageRuntime.
    public static func make(query: String, state: BrowserState, provider: CommandBarSearchProvider = .duckDuckGo) -> [CommandBarResult] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var results: [CommandBarResult] = []
        switch CommandBarInput.resolve(text, provider: provider) {
        case .navigate(let url):
            results.append(CommandBarResult(id: "destination", title: "Open \(url.host ?? text)",
                subtitle: url.absoluteString, action: .open(url)))
        case .search(let url):
            results.append(CommandBarResult(id: "destination", title: "Search \(provider.title) for “\(text)”",
                subtitle: "Web search", action: .open(url)))
        case .empty, .invalid: break
        }
        results += state.searchPages(matching: text).map {
            CommandBarResult(id: "page:\($0.entryID.uuidString)", title: $0.entry.title,
                subtitle: "\($0.workspaceName) · \($0.entry.lastURL.absoluteString)", action: .activate($0))
        }
        results += CommandBarCommand.allCases.filter {
            text.isEmpty || $0.title.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }.map {
            CommandBarResult(id: "command:\($0.rawValue)", title: $0.title,
                subtitle: "Browser command", action: .command($0))
        }
        return results
    }
}
