import Foundation

public enum DownloadState: String, Codable, Equatable, Sendable {
    case inProgress, paused, completed, failed, cancelled

    public var isActive: Bool { self == .inProgress || self == .paused }
}

/// One engine download as last reported. `id` is stable for the item's life within its Profile.
public struct DownloadItem: Identifiable, Equatable, Sendable {
    public var id: String
    /// Names the engine Profile the download belongs to; never shown.
    public var profileKey: String
    public var filename: String
    /// Final location once known; empty while the engine has not chosen one.
    public var path: String
    public var receivedBytes: Int64
    /// -1 when the server sent no length.
    public var totalBytes: Int64
    public var bytesPerSecond: Int64
    public var state: DownloadState
    public var canResume: Bool
    public var fileExists: Bool

    public init(id: String, profileKey: String, filename: String, path: String = "", receivedBytes: Int64 = 0,
                totalBytes: Int64 = -1, bytesPerSecond: Int64 = 0, state: DownloadState = .inProgress,
                canResume: Bool = false, fileExists: Bool = true) {
        self.id = id
        self.profileKey = profileKey
        self.filename = filename
        self.path = path
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
        self.bytesPerSecond = bytesPerSecond
        self.state = state
        self.canResume = canResume
        self.fileExists = fileExists
    }

    /// nil when the total is unknown, so the UI shows an indeterminate state.
    public var fraction: Double? {
        guard totalBytes > 0 else { return nil }
        return min(1, max(0, Double(receivedBytes) / Double(totalBytes)))
    }

    public var fileURL: URL? { path.isEmpty ? nil : URL(fileURLWithPath: path) }
    public var canOpen: Bool { state == .completed && fileExists && fileURL != nil }
}

public enum DownloadEvent: Equatable, Sendable {
    /// A snapshot: both a new download and any later change arrive as an upsert, so the
    /// engine never has to distinguish created from updated for correctness.
    case upsert(DownloadItem)
    case removed(profileKey: String, id: String)
}

public enum DownloadAction: Equatable, Sendable {
    case pause, resume, cancel, open, showInFinder, remove
}

/// What the sidebar needs from the engine. Events arrive on the main actor; actions return whether
/// the engine accepted them (an unknown or finished id is refused, never an error).
@MainActor
public protocol DownloadsEngine: AnyObject {
    var onEvent: ((DownloadEvent) -> Void)? { get set }
    /// Replays every known download of every Profile as `upsert`, for a host that attaches late.
    func requestSnapshot()
    @discardableResult
    func perform(_ action: DownloadAction, id: String, profileKey: String) -> Bool
}

/// Per-Profile download lists, newest first. Pure state; the controller owns engine wiring.
public struct DownloadsModel: Equatable, Sendable {
    private var itemsByProfile: [String: [DownloadItem]] = [:]
    /// Profiles with a download that finished since the list was last viewed.
    private var unseen: Set<String> = []

    public init() {}

    public func items(for profileKey: String) -> [DownloadItem] { itemsByProfile[profileKey] ?? [] }
    public func activeItems(for profileKey: String) -> [DownloadItem] { items(for: profileKey).filter { $0.state.isActive } }
    public func hasUnseenFinish(for profileKey: String) -> Bool { unseen.contains(profileKey) }

    public mutating func apply(_ event: DownloadEvent) {
        switch event {
        case .upsert(let item): upsert(item)
        case .removed(let profileKey, let id): remove(profileKey: profileKey, id: id)
        }
    }

    public mutating func markSeen(_ profileKey: String) { unseen.remove(profileKey) }

    /// Drops finished items (completed, failed, cancelled) from the list only; files stay on disk.
    public mutating func clearFinished(for profileKey: String) {
        itemsByProfile[profileKey]?.removeAll { !$0.state.isActive }
        if itemsByProfile[profileKey]?.isEmpty == true { itemsByProfile[profileKey] = nil }
        unseen.remove(profileKey)
    }

    /// Combined progress of active downloads with a known size, nil when none can report one.
    public func aggregateFraction(for profileKey: String) -> Double? {
        let sized = activeItems(for: profileKey).filter { $0.totalBytes > 0 }
        let total = sized.reduce(Int64(0)) { $0 + $1.totalBytes }
        guard total > 0 else { return nil }
        let received = sized.reduce(Int64(0)) { $0 + min($1.receivedBytes, $1.totalBytes) }
        return Double(received) / Double(total)
    }

    private mutating func upsert(_ item: DownloadItem) {
        var list = itemsByProfile[item.profileKey] ?? []
        if let index = list.firstIndex(where: { $0.id == item.id }) {
            if list[index].state.isActive, !item.state.isActive { unseen.insert(item.profileKey) }
            list[index] = item
        } else {
            list.insert(item, at: 0)
            if !item.state.isActive { unseen.insert(item.profileKey) }
        }
        itemsByProfile[item.profileKey] = list
    }

    private mutating func remove(profileKey: String, id: String) {
        itemsByProfile[profileKey]?.removeAll { $0.id == id }
        if itemsByProfile[profileKey]?.isEmpty == true {
            itemsByProfile[profileKey] = nil
            unseen.remove(profileKey)
        }
    }
}

public enum DownloadFormat {
    /// "4.2 MB of 48 MB · 1.1 MB/s", "Done · 48 MB", "Paused", "Failed", "Cancelled".
    public static func status(_ item: DownloadItem) -> String {
        switch item.state {
        case .completed:
            if !item.fileExists { return "File moved or deleted" }
            return item.totalBytes > 0 ? "Done · \(bytes(item.totalBytes))" : "Done"
        case .failed: return item.canResume ? "Failed · can resume" : "Failed"
        case .cancelled: return "Cancelled"
        case .paused: return item.totalBytes > 0 ? "Paused · \(bytes(item.receivedBytes)) of \(bytes(item.totalBytes))" : "Paused"
        case .inProgress:
            var text = item.totalBytes > 0 ? "\(bytes(item.receivedBytes)) of \(bytes(item.totalBytes))" : bytes(item.receivedBytes)
            if item.bytesPerSecond > 0 { text += " · \(bytes(item.bytesPerSecond))/s" }
            return text
        }
    }

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
