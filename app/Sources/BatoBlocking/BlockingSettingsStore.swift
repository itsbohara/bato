import Foundation

/// Reads and atomically writes `blocking-settings.json` in a Profile's blocking directory.
/// The host process polls this file, so every save is a whole-file atomic replace.
public final class BlockingSettingsStore: @unchecked Sendable {
    public static let fileName = "blocking-settings.json"

    public enum StoreError: Error, Equatable {
        case saveFailed
    }

    private let directory: URL
    private let lock = NSLock()
    private var cached: BlockingSettings?
    private var recovered = false

    public init(directory: URL) {
        self.directory = directory
    }

    public var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// True when an unreadable settings file was set aside as `blocking-settings.json.corrupt`
    /// and defaults were used instead.
    public var recoveredFromCorruption: Bool { lock.withLock { recovered } }

    public func current() -> BlockingSettings {
        lock.withLock { cachedOrLoad() }
    }

    /// Drops the in-memory copy so the next read sees a file replaced on disk, e.g. by a backup restore.
    public func reload() {
        lock.withLock {
            cached = nil
            recovered = false
        }
    }

    @discardableResult
    public func update(_ change: (inout BlockingSettings) throws -> Void) throws -> BlockingSettings {
        try lock.withLock {
            var next = cachedOrLoad()
            try change(&next)
            guard next != cached else { return next }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try encoder.encode(next).write(to: fileURL, options: .atomic)
            } catch {
                throw StoreError.saveFailed
            }
            cached = next
            return next
        }
    }

    private func cachedOrLoad() -> BlockingSettings {
        if let cached { return cached }
        let loaded = readFromDisk()
        cached = loaded
        return loaded
    }

    private func readFromDisk() -> BlockingSettings {
        guard let bytes = try? Data(contentsOf: fileURL) else { return BlockingSettings() }
        if let settings = try? JSONDecoder().decode(BlockingSettings.self, from: bytes) { return settings }
        let quarantine = fileURL.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: quarantine)
        try? FileManager.default.moveItem(at: fileURL, to: quarantine)
        recovered = true
        return BlockingSettings()
    }
}
