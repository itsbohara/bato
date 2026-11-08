import BatoCore
import Foundation

/// Per-Profile closed-tab history in `closed-tabs.json`, so Reopen Closed Tab survives a relaunch.
/// Each Profile keeps at most `ClosedTabStack.capacity` tabs; saves replace the whole file.
public struct ClosedTabsStore {
    public static let fileName = "closed-tabs.json"

    private struct Document: Codable {
        var version = 1
        var stacks: [String: [ClosedTab]] = [:]
    }

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// A missing or unreadable file yields no history; an unreadable one is set aside as `closed-tabs.json.corrupt`.
    public func load() -> [UUID: ClosedTabStack] {
        guard let bytes = try? Data(contentsOf: fileURL) else { return [:] }
        guard let document = try? JSONDecoder().decode(Document.self, from: bytes), document.version == 1 else {
            let quarantine = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: quarantine)
            try? FileManager.default.moveItem(at: fileURL, to: quarantine)
            return [:]
        }
        var stacks: [UUID: ClosedTabStack] = [:]
        for (key, tabs) in document.stacks {
            guard let profileID = UUID(uuidString: key) else { continue }
            let stack = ClosedTabStack(tabs: tabs.filter { $0.profileID == profileID })
            if !stack.isEmpty { stacks[profileID] = stack }
        }
        return stacks
    }

    public func save(_ stacks: [UUID: ClosedTabStack]) throws {
        var document = Document()
        for (profileID, stack) in stacks where !stack.isEmpty {
            document.stacks[profileID.uuidString] = stack.tabs
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(document).write(to: fileURL, options: .atomic)
    }
}
