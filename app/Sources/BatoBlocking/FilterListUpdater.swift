import Foundation

/// A filter list fetched at runtime. Lists are never bundled or committed: EasyList and
/// EasyPrivacy are dual licensed (GPL-3+/CC-BY-SA-3.0) and are only downloaded by the user's app.
public struct FilterListSource: Equatable, Sendable {
    public let id: String
    public let url: URL
    public let minimumRuleCount: Int
    public let maximumBytes: Int
    /// Adblock Plus lists open with a `[` header line. uBlock Origin's own lists open with `!` comments.
    public let requiresHeader: Bool

    public init(id: String, url: URL, minimumRuleCount: Int, maximumBytes: Int, requiresHeader: Bool = true) {
        self.id = id
        self.url = url
        self.minimumRuleCount = minimumRuleCount
        self.maximumBytes = maximumBytes
        self.requiresHeader = requiresHeader
    }

    public static let easyList = FilterListSource(
        id: "easylist", url: URL(string: "https://easylist.to/easylist/easylist.txt")!,
        minimumRuleCount: 20_000, maximumBytes: 20_000_000)
    public static let easyPrivacy = FilterListSource(
        id: "easyprivacy", url: URL(string: "https://easylist.to/easylist/easyprivacy.txt")!,
        minimumRuleCount: 5_000, maximumBytes: 20_000_000)
    public static let defaults = [easyList, easyPrivacy]

    /// The uBlock Origin project's own filter lists (GPL-3.0, from uAssets). Downloaded only after
    /// the user accepts the offer; never bundled.
    public static let uBlockFilters = uBlock("ublock-filters", file: "filters", minimumRuleCount: 10_000, maximumBytes: 10_000_000)
    public static let uBlockPrivacy = uBlock("ublock-privacy", file: "privacy", minimumRuleCount: 800, maximumBytes: 5_000_000)
    public static let uBlockBadware = uBlock("ublock-badware", file: "badware", minimumRuleCount: 2_000, maximumBytes: 5_000_000)
    public static let uBlockUnbreak = uBlock("ublock-unbreak", file: "unbreak", minimumRuleCount: 1_000, maximumBytes: 5_000_000)
    public static let uBlockOrigin = [uBlockFilters, uBlockPrivacy, uBlockBadware, uBlockUnbreak]

    private static func uBlock(_ id: String, file: String, minimumRuleCount: Int, maximumBytes: Int) -> FilterListSource {
        FilterListSource(id: id, url: URL(string: "https://ublockorigin.github.io/uAssets/filters/\(file).min.txt")!,
                         minimumRuleCount: minimumRuleCount, maximumBytes: maximumBytes, requiresHeader: false)
    }
}

public enum FetchResult: Equatable, Sendable {
    case notModified
    case content(Data, etag: String?)
}

public protocol FilterListFetching: Sendable {
    func fetch(_ url: URL, etag: String?, maximumBytes: Int) async throws -> FetchResult
}

public enum ListRejection: String, Error, Codable, Equatable, Sendable {
    case notText
    case tooLarge
    case missingHeader
    case tooFewRules
}

public enum ListUpdateOutcome: Equatable, Sendable {
    case updated(ruleCount: Int)
    case unchanged
    case rejected(ListRejection)
    case failed(String)
}

/// Diagnostic record per list, persisted as `lists-status.json`.
public struct ListStatus: Codable, Equatable, Sendable {
    public var etag: String?
    public var lastCheck: Date?
    public var lastSuccess: Date?
    public var lastError: String?
    public var ruleCount: Int?
}

public enum FilterListValidator {
    /// Returns the rule count, or why the download must not replace the last good list.
    public static func validate(_ data: Data, for source: FilterListSource) -> Result<Int, ListRejection> {
        guard data.count <= source.maximumBytes else { return .failure(.tooLarge) }
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else { return .failure(.notText) }
        guard !source.requiresHeader || text.drop(while: { $0 == "\u{FEFF}" || $0.isWhitespace }).hasPrefix("[") else {
            return .failure(.missingHeader)
        }
        let rules = text.split(whereSeparator: \.isNewline).count(where: { line in
            !line.hasPrefix("!") && !line.hasPrefix("[") && !line.allSatisfy(\.isWhitespace)
        })
        return rules >= source.minimumRuleCount ? .success(rules) : .failure(.tooFewRules)
    }
}

/// Downloads lists into `<directory>/lists/<id>.txt`. The active file is only ever replaced,
/// atomically, by a validated download, so a failed or rejected update leaves the last good
/// list in place. The browser host watches the directory and rebuilds its engine off-thread.
public actor FilterListUpdater {
    public static let statusFileName = "lists-status.json"

    private let listsDirectory: URL
    private let statusURL: URL
    private var sources: [FilterListSource]
    private let fetcher: FilterListFetching
    private let now: @Sendable () -> Date
    private var statuses: [String: ListStatus]

    public init(directory: URL, sources: [FilterListSource] = FilterListSource.defaults,
                fetcher: FilterListFetching, now: @escaping @Sendable () -> Date = { Date() }) {
        listsDirectory = directory.appendingPathComponent("lists")
        statusURL = directory.appendingPathComponent(Self.statusFileName)
        self.sources = sources
        self.fetcher = fetcher
        self.now = now
        statuses = (try? Data(contentsOf: statusURL))
            .flatMap { try? Self.decoder.decode([String: ListStatus].self, from: $0) } ?? [:]
    }

    public func status() -> [String: ListStatus] { statuses }

    /// Replaces the lists to keep fresh. Files of lists no longer wanted are left for `discard`.
    public func setSources(_ sources: [FilterListSource]) {
        self.sources = sources
    }

    /// Deletes the lists' files and status so the host stops filtering with them.
    public func discard(_ removed: [FilterListSource]) {
        for source in removed {
            try? FileManager.default.removeItem(at: fileURL(source))
            statuses.removeValue(forKey: source.id)
        }
        saveStatuses()
    }

    /// Checks every list whose last check is older than `maxAge` or whose file is missing.
    @discardableResult
    public func update(maxAge: TimeInterval = 0) async -> [String: ListUpdateOutcome] {
        var outcomes: [String: ListUpdateOutcome] = [:]
        for source in sources {
            let status = statuses[source.id]
            let due = status?.lastCheck.map { now().timeIntervalSince($0) >= maxAge } ?? true
            guard due || !FileManager.default.fileExists(atPath: fileURL(source).path) else {
                outcomes[source.id] = .unchanged
                continue
            }
            outcomes[source.id] = await update(source)
        }
        return outcomes
    }

    private func update(_ source: FilterListSource) async -> ListUpdateOutcome {
        var status = statuses[source.id] ?? ListStatus()
        status.lastCheck = now()
        let hasFile = FileManager.default.fileExists(atPath: fileURL(source).path)
        let outcome: ListUpdateOutcome
        do {
            switch try await fetcher.fetch(source.url, etag: hasFile ? status.etag : nil,
                                           maximumBytes: source.maximumBytes) {
            case .notModified:
                outcome = .unchanged
                status.lastSuccess = now()
                status.lastError = nil
            case let .content(data, etag):
                switch FilterListValidator.validate(data, for: source) {
                case let .success(rules):
                    try install(data, for: source)
                    outcome = .updated(ruleCount: rules)
                    status.etag = etag
                    status.ruleCount = rules
                    status.lastSuccess = now()
                    status.lastError = nil
                case let .failure(reason):
                    outcome = .rejected(reason)
                    status.lastError = "rejected: \(reason.rawValue)"
                }
            }
        } catch {
            outcome = .failed(error.localizedDescription)
            status.lastError = error.localizedDescription
        }
        statuses[source.id] = status
        saveStatuses()
        return outcome
    }

    private func fileURL(_ source: FilterListSource) -> URL {
        listsDirectory.appendingPathComponent("\(source.id).txt")
    }

    private func install(_ data: Data, for source: FilterListSource) throws {
        try FileManager.default.createDirectory(at: listsDirectory, withIntermediateDirectories: true)
        try data.write(to: fileURL(source), options: .atomic)
    }

    private func saveStatuses() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: statusURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let bytes = try? encoder.encode(statuses) { try? bytes.write(to: statusURL, options: .atomic) }
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
