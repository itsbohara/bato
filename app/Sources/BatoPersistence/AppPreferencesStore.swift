import BatoCore
import Foundation

public struct AppPreferences: Equatable, Sendable {
    public var searchProvider: CommandBarSearchProvider = .default
    public init() {}
}

extension AppPreferences: Codable {
    private enum CodingKeys: String, CodingKey { case searchProvider }

    /// An unknown provider name, e.g. from a newer build, falls back to the default instead of dropping the file.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let name = try values.decodeIfPresent(String.self, forKey: .searchProvider)
        searchProvider = name.flatMap(CommandBarSearchProvider.init(rawValue:)) ?? .default
    }
}

/// App-wide preferences in `preferences.json`, shared by every Profile and window. Saves replace the whole file.
public final class AppPreferencesStore {
    public static let fileName = "preferences.json"

    public enum StoreError: Error, Equatable { case saveFailed }

    private let directory: URL
    private var cached: AppPreferences?

    public init(directory: URL) {
        self.directory = directory
    }

    public var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    public func current() -> AppPreferences {
        if let cached { return cached }
        let loaded = readFromDisk()
        cached = loaded
        return loaded
    }

    @discardableResult
    public func update(_ change: (inout AppPreferences) -> Void) throws -> AppPreferences {
        var next = current()
        change(&next)
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

    /// An unreadable file is set aside as `preferences.json.corrupt` and defaults are used.
    private func readFromDisk() -> AppPreferences {
        guard let bytes = try? Data(contentsOf: fileURL) else { return AppPreferences() }
        if let preferences = try? JSONDecoder().decode(AppPreferences.self, from: bytes) { return preferences }
        let quarantine = fileURL.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: quarantine)
        try? FileManager.default.moveItem(at: fileURL, to: quarantine)
        return AppPreferences()
    }
}
