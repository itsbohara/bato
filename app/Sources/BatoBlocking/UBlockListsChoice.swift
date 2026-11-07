import Foundation

/// Where the user stands on the optional uBlock Origin filter lists.
public enum UBlockListsChoice: String, Codable, Equatable, Sendable {
    /// Never asked. The first-run offer is due.
    case undecided
    case enabled
    /// Asked and declined, or added and later removed. The offer is not shown again; Settings re-offers.
    case declined
}

/// Persists the choice as `list-choices.json` in the blocking root. It is per machine, not per Profile,
/// because the lists are shared by every Profile.
public final class UBlockListsChoiceStore: @unchecked Sendable {
    public static let fileName = "list-choices.json"

    private struct Document: Codable {
        var version = 1
        var uBlockLists: UBlockListsChoice
    }

    private let fileURL: URL
    private let lock = NSLock()
    private var cached: UBlockListsChoice?

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent(Self.fileName)
    }

    public var choice: UBlockListsChoice {
        lock.withLock {
            if let cached { return cached }
            let loaded = (try? Data(contentsOf: fileURL))
                .flatMap { try? JSONDecoder().decode(Document.self, from: $0) }
                .flatMap { $0.version == 1 ? $0.uBlockLists : nil } ?? .undecided
            cached = loaded
            return loaded
        }
    }

    public func set(_ choice: UBlockListsChoice) throws {
        try lock.withLock {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(Document(uBlockLists: choice)).write(to: fileURL, options: .atomic)
            cached = choice
        }
    }
}
