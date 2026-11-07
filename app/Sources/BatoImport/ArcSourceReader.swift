import CryptoKit
import Darwin
import Foundation

public struct ArcSourceFile: Equatable, Sendable {
    public let data: Data
    public let sha256: String
}

public enum ArcSourceError: Error, Equatable, LocalizedError {
    case unreadable
    case notRegularFile
    case tooLarge
    case changedWhileReading

    public var errorDescription: String? {
        switch self {
        case .unreadable: "The file could not be read."
        case .notRegularFile: "Choose the Arc sidebar file itself, not a folder."
        case .tooLarge: "The Arc file is larger than the importer accepts."
        case .changedWhileReading: "The file kept changing while it was read. Quit Arc or choose a copy, then try again."
        }
    }
}

/// Reads a user-chosen file strictly read-only into memory. Nothing is written next to the source
/// and no copy of the user's data is left on disk.
public enum ArcSourceReader {
    /// Only where the open panel may start. Reading it is the user's choice in the panel.
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Arc", isDirectory: true)
    }

    /// Hashes the bytes twice. A mismatch means the writer (Arc) was mid-write, so it retries once.
    public static func read(_ url: URL) throws -> ArcSourceFile {
        for attempt in 0..<2 {
            let first = try readBytes(url)
            let second = try readBytes(url)
            let digest = sha256(first)
            if digest == sha256(second) { return ArcSourceFile(data: first, sha256: digest) }
            if attempt == 1 { break }
        }
        throw ArcSourceError.changedWhileReading
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func readBytes(_ url: URL) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw ArcSourceError.unreadable }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw ArcSourceError.unreadable }
        guard info.st_mode & S_IFMT == S_IFREG else { throw ArcSourceError.notRegularFile }
        guard info.st_size <= ArcSidebarParser.maxInputBytes else { throw ArcSourceError.tooLarge }
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 { return bytes }
            if count < 0 {
                if errno == EINTR { continue }
                throw ArcSourceError.unreadable
            }
            bytes.append(contentsOf: buffer.prefix(count))
            guard bytes.count <= ArcSidebarParser.maxInputBytes else { throw ArcSourceError.tooLarge }
        }
    }
}
