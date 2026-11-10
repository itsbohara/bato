import Foundation

public enum CommandBarDestination: Equatable, Sendable {
    case empty
    case navigate(URL)
    case search(URL)
    case invalid(String)
}

/// The chosen provider is persisted app-wide by `AppPreferencesStore`; DuckDuckGo is the default.
public enum CommandBarSearchProvider: String, CaseIterable, Codable, Sendable {
    case duckDuckGo, google, brave, bing
    public static let `default`: CommandBarSearchProvider = .duckDuckGo
    public var title: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo"
        case .google: "Google"
        case .brave: "Brave Search"
        case .bing: "Bing"
        }
    }
    public var endpoint: URL {
        switch self {
        case .duckDuckGo: URL(string: "https://duckduckgo.com/")!
        case .google: URL(string: "https://www.google.com/search")!
        case .brave: URL(string: "https://search.brave.com/search")!
        case .bing: URL(string: "https://www.bing.com/search")!
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
        return .search(searchURL(for: text, provider: provider))
    }

    public static func searchURL(for text: String, provider: CommandBarSearchProvider) -> URL {
        formURL(provider.endpoint, [URLQueryItem(name: "q", value: text)])
    }

    /// Search endpoints decode form queries, where a literal + means space.
    /// URLComponents uses RFC 3986 and leaves + unescaped by default.
    static func formURL(_ endpoint: URL, _ items: [URLQueryItem]) -> URL {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = items
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }
}

/// Typed-query completions from the selected search provider. The typed text leaves the device only
/// when the user has search suggestions on, and never for addresses.
public enum SearchSuggestions {
    public static let maxQueryLength = 100

    /// Nil unless the input is a plain search: addresses and invalid input are never sent to a provider.
    public static func endpoint(for query: String, provider: CommandBarSearchProvider) -> URL? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= maxQueryLength, case .search = CommandBarInput.resolve(text, provider: provider) else { return nil }
        switch provider {
        case .duckDuckGo:
            return CommandBarInput.formURL(URL(string: "https://duckduckgo.com/ac/")!, [URLQueryItem(name: "q", value: text)])
        case .google:
            return CommandBarInput.formURL(URL(string: "https://suggestqueries.google.com/complete/search")!,
                                           [URLQueryItem(name: "client", value: "firefox"), URLQueryItem(name: "q", value: text)])
        case .brave:
            return CommandBarInput.formURL(URL(string: "https://search.brave.com/api/suggest")!, [URLQueryItem(name: "q", value: text)])
        case .bing:
            return CommandBarInput.formURL(URL(string: "https://api.bing.com/osjson.aspx")!, [URLQueryItem(name: "query", value: text)])
        }
    }

    /// Reads the OpenSearch shape (`["q", ["a", "b"]]`, Google, Brave, Bing) and DuckDuckGo's
    /// `[{"phrase": "a"}]`. Anything else yields no suggestions.
    public static func parse(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        let raw: [String]
        if json.first is String, json.count > 1, let list = json[1] as? [Any] {
            raw = list.compactMap { $0 as? String }
        } else {
            raw = json.compactMap { ($0 as? [String: Any])?["phrase"] as? String }
        }
        var seen = Set<String>()
        return raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}

/// Fetches suggestions after the user pauses typing. A new request cancels the previous one, so a slow
/// response for an old query is never delivered.
@MainActor
public final class SearchSuggestionFetcher {
    public typealias Fetch = @Sendable (URL) async throws -> Data
    public static let debounce: Duration = .milliseconds(120)

    private let delay: Duration
    private let fetch: Fetch
    private var task: Task<Void, Never>?

    public init(delay: Duration = SearchSuggestionFetcher.debounce, fetch: @escaping Fetch = SearchSuggestionFetcher.live) {
        self.delay = delay
        self.fetch = fetch
    }

    public func request(query: String, provider: CommandBarSearchProvider,
                        deliver: @escaping @MainActor (_ query: String, _ suggestions: [String]) -> Void) {
        task?.cancel()
        guard let url = SearchSuggestions.endpoint(for: query, provider: provider) else { task = nil; return }
        task = Task { [delay, fetch] in
            do {
                try await Task.sleep(for: delay)
                let data = try await fetch(url)
                try Task.checkCancellation()
                deliver(query, SearchSuggestions.parse(data))
            } catch {}
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    private static let session = URLSession(configuration: .ephemeral)

    public static let live: Fetch = { url in
        let (data, response) = try await session.data(for: URLRequest(url: url, timeoutInterval: 3))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}

public enum CommandBarCommand: String, CaseIterable, Sendable {
    case findPage, toggleSidebar, closePage, archiveTab, openArchive, openHistory, openDownloads, openSettings
    public var title: String {
        switch self {
        case .findPage: "Find Page"
        case .toggleSidebar: "Toggle Sidebar"
        case .closePage: "Close Current Page"
        case .archiveTab: "Archive Current Tab"
        case .openArchive: "Archive"
        case .openHistory: "History"
        case .openDownloads: "Downloads"
        case .openSettings: "Settings"
        }
    }
}

public enum CommandBarAction: Equatable, Sendable {
    case open(URL)
    /// Loads the destination in the page the bar was opened for, instead of a new tab.
    case navigateCurrent(URL)
    case peek(URL)
    case activate(PageSearchResult)
    case command(CommandBarCommand)
}

public struct CommandBarResult: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let action: CommandBarAction

    public static let webSearchSubtitle = "Web search"
    public static let suggestionSubtitle = "Suggestion"
    public var isSearch: Bool { subtitle == Self.webSearchSubtitle || subtitle == Self.suggestionSubtitle }
}

public enum CommandBarSelection {
    /// An arrow-key choice survives a refresh only while the query is unchanged; typing re-ranks, so the top row wins.
    public static func rowAfterRefresh(previousID: String?, previousQuery: String, query: String,
                                       results: [CommandBarResult]) -> Int? {
        if query == previousQuery, let index = results.firstIndex(where: { $0.id == previousID }) { return index }
        return results.isEmpty ? nil : 0
    }
}

public enum CommandBarResults {
    /// Stable IDs let the UI preserve selection while organization events arrive.
    /// Results never mutate state; activation must revalidate through PageRuntime.
    /// A typed query shows at most this many rows, so the palette stays about as tall as Arc's.
    public static let queryRowLimit = 7
    /// Open-tab matches that rank above search suggestions; further matches follow the suggestions.
    static let leadingPageMatches = 3

    public static func make(query: String, state: BrowserState, provider: CommandBarSearchProvider = .duckDuckGo,
                            navigatingCurrentPage: Bool = false, suggestions: [String] = []) -> [CommandBarResult] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var results: [CommandBarResult] = []
        switch CommandBarInput.resolve(text, provider: provider) {
        case .navigate(let url):
            if navigatingCurrentPage {
                results.append(CommandBarResult(id: "destination", title: "Go to \(url.host ?? text)",
                    subtitle: url.absoluteString, action: .navigateCurrent(url)))
            } else {
                results.append(CommandBarResult(id: "destination", title: "Open \(url.host ?? text)",
                    subtitle: url.absoluteString, action: .open(url)))
                results.append(CommandBarResult(id: "peek", title: "Open \(url.host ?? text) in Peek",
                    subtitle: url.absoluteString, action: .peek(url)))
            }
        case .search(let url):
            results.append(CommandBarResult(id: "destination", title: "Search \(provider.title) for “\(text)”",
                subtitle: CommandBarResult.webSearchSubtitle, action: navigatingCurrentPage ? .navigateCurrent(url) : .open(url)))
        case .empty, .invalid: break
        }
        let commands = CommandBarCommand.allCases.filter {
            text.isEmpty || $0.title.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }.map {
            CommandBarResult(id: "command:\($0.rawValue)", title: $0.title,
                subtitle: "Browser command", action: .command($0))
        }
        // An exact command name is a deliberate choice, so it outranks the web-search fallback.
        let isExactCommand = { (result: CommandBarResult) in
            result.title.compare(text, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        var remainingCommands = commands
        if case .search = CommandBarInput.resolve(text, provider: provider) {
            results.insert(contentsOf: commands.filter(isExactCommand), at: 0)
            remainingCommands.removeAll(where: isExactCommand)
        }
        let pages = Self.oneRowPerPage(state.searchPages(matching: text), preferring: state.activeWorkspaceID).map {
            CommandBarResult(id: "page:\($0.entryID.uuidString)", title: $0.entry.title,
                subtitle: "\($0.workspaceName) · \($0.entry.lastURL.absoluteString)", action: .activate($0))
        }
        let suggestionRows = suggestions.filter { $0.caseInsensitiveCompare(text) != .orderedSame }.map { suggestion in
            let url = CommandBarInput.searchURL(for: suggestion, provider: provider)
            return CommandBarResult(id: "suggestion:\(suggestion)", title: suggestion,
                subtitle: CommandBarResult.suggestionSubtitle, action: navigatingCurrentPage ? .navigateCurrent(url) : .open(url))
        }
        guard !text.isEmpty else { return results + pages + remainingCommands }
        results += pages.prefix(leadingPageMatches) + suggestionRows + pages.dropFirst(leadingPageMatches) + remainingCommands
        return Array(results.prefix(queryRowLimit))
    }
}

extension CommandBarResults {
    /// The same address open in several Spaces is offered once, in the current Space when it is open there.
    static func oneRowPerPage(_ pages: [PageSearchResult], preferring workspaceID: UUID) -> [PageSearchResult] {
        let ordered = pages.enumerated().sorted {
            let (lhs, rhs) = ($0.element.workspaceID == workspaceID, $1.element.workspaceID == workspaceID)
            return lhs == rhs ? $0.offset < $1.offset : lhs
        }.map(\.element)
        var seen = Set<String>()
        return ordered.filter { seen.insert($0.entry.lastURL.absoluteString).inserted }
    }
}

public enum FaviconFallback {
    public struct Spec: Equatable, Sendable {
        public let letter: String
        public let hue: Double
    }

    public static func spec(title: String, url: URL) -> Spec {
        let host = (url.host ?? "").lowercased()
        let hostless = host.isEmpty || host == "localhost" || host.allSatisfy { $0.isNumber || $0 == "." || $0 == ":" }
        let source = hostless ? title : host.replacingOccurrences(of: "www.", with: "")
        let letter = source.first(where: \.isLetter) ?? source.first(where: \.isNumber) ?? "?"
        let seed = (url.absoluteString + title).unicodeScalars.reduce(UInt32(7)) { $0 &* 31 &+ $1.value }
        return Spec(letter: String(letter).uppercased(), hue: Double(seed % 360) / 360)
    }
}
