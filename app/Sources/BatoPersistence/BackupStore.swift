import Foundation
import Darwin

public enum BackupError: Error, LocalizedError, Equatable {
    case unknownBackup
    case unsafePath
    case unreadable
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .unknownBackup: "That backup no longer exists."
        case .unsafePath: "The backup contains a file outside Bato’s storage."
        case .unreadable: "The backup could not be read."
        case .writeFailed: "The backup could not be written. Check free disk space."
        }
    }
}

public struct BackupInfo: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable { case daily, lastSession, preImport, preMigration, preRestore }
    public let id: String
    public let kind: Kind
    public let createdAt: Date
}

public struct BackupContents: Equatable, Sendable {
    public let organization: Data
    /// Settings kept beside the organization, keyed by path relative to the state directory.
    public let files: [String: Data]
}

public struct RestoreResult<State> {
    public let state: State
    public let failedFiles: [String]
}

/// Rolling copies of organization and Bato settings. Engine data (cookies, credentials) is never included.
///
/// `last-session` and `daily-<day>` copies live in `<state>/backups`. The pre-import, pre-migration and
/// pre-restore copies are the single-slot snapshots `OrganizationStore.saveWithSnapshot` already writes
/// beside the document; this type lists and prunes them instead of making a second copy.
public final class BackupStore {
    public static let dailyRetention = 7
    public static let lastSessionID = "last-session"
    static let preChangeNames = ["pre-import", "pre-migration", "pre-restore"]

    private struct Manifest: Codable {
        var schema = 1
        var createdAt: Date
    }

    private let directory: URL
    private let calendar: Calendar
    private let now: () -> Date

    public init(directory: URL, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.calendar = calendar
        self.now = now
    }

    private var root: URL { directory.appendingPathComponent("backups", isDirectory: true) }
    private var pendingRestoreURL: URL { directory.appendingPathComponent("recovery-pending-restore.json") }

    /// Writes today's copy unless one exists. Returns whether a copy was written.
    @discardableResult
    public func captureDaily(organization: Data, files: [String: Data]) throws -> Bool {
        let id = dailyID(for: now())
        guard !FileManager.default.fileExists(atPath: root.appendingPathComponent(id).path) else { return false }
        try write(id: id, organization: organization, files: files)
        return true
    }

    /// Replaces the previous last-session copy; a failure leaves the previous copy in place.
    public func captureLastSession(organization: Data, files: [String: Data]) throws {
        try write(id: Self.lastSessionID, organization: organization, files: files)
    }

    /// Newest first.
    public func list() -> [BackupInfo] {
        var found: [BackupInfo] = []
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for name in names where Self.isDirectoryBackupID(name) {
            guard let manifest = readManifest(name) else { continue }
            found.append(BackupInfo(id: name, kind: name == Self.lastSessionID ? .lastSession : .daily,
                                    createdAt: manifest.createdAt))
        }
        for name in Self.preChangeNames {
            guard let modified = modificationDate(snapshotURL(name)) else { continue }
            let kind: BackupInfo.Kind = name == "pre-import" ? .preImport : name == "pre-migration" ? .preMigration : .preRestore
            found.append(BackupInfo(id: name, kind: kind, createdAt: modified))
        }
        return found.sorted { $0.createdAt > $1.createdAt }
    }

    public func contents(of id: String) throws -> BackupContents {
        if Self.preChangeNames.contains(id) {
            return BackupContents(organization: try readRegular(snapshotURL(id)), files: [:])
        }
        guard Self.isDirectoryBackupID(id), readManifest(id) != nil else { throw BackupError.unknownBackup }
        let base = root.appendingPathComponent(id, isDirectory: true)
        let organization = try readRegular(base.appendingPathComponent("organization.json"))
        var files: [String: Data] = [:]
        let filesRoot = base.appendingPathComponent("files", isDirectory: true).resolvingSymlinksInPath()
        if let enumerator = FileManager.default.enumerator(at: filesRoot, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let url as URL in enumerator {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                let relative = String(url.resolvingSymlinksInPath().path.dropFirst(filesRoot.path.count + 1))
                files[relative] = try readRegular(url)
            }
        }
        return BackupContents(organization: organization, files: files)
    }

    /// Keeps the newest `dailyRetention` daily copies and only the newest pre-change snapshot.
    public func prune() {
        let backups = list()
        for stale in backups.filter({ $0.kind == .daily }).dropFirst(Self.dailyRetention) {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(stale.id))
        }
        for stale in backups.filter({ [.preImport, .preMigration, .preRestore].contains($0.kind) }).dropFirst() {
            try? FileManager.default.removeItem(at: snapshotURL(stale.id))
        }
    }

    /// Replaces the organization with a backup and restores its settings files. The previous document
    /// stays as the `pre-restore` snapshot; an invalid or unreadable backup changes nothing.
    public func restore<State: Codable>(_ id: String, into store: OrganizationStore<State>) throws -> RestoreResult<State> {
        let backup = try contents(of: id)
        let restored: State
        do { restored = try JSONDecoder().decode(State.self, from: backup.organization) }
        catch { throw OrganizationStore<State>.StoreError.corruptState }
        _ = try store.saveWithSnapshot(restored, named: "pre-restore")
        var failed: [String] = []
        for (relative, bytes) in backup.files {
            do { try writeSettingsFile(bytes, relativePath: relative) }
            catch { failed.append(relative) }
        }
        return RestoreResult(state: restored, failedFiles: failed.sorted())
    }

    /// Asks the next launch to restore `id` before anything reads the organization.
    public func stageRestore(_ id: String) throws {
        guard list().contains(where: { $0.id == id }) else { throw BackupError.unknownBackup }
        do { try Data(id.utf8).write(to: pendingRestoreURL, options: .atomic) }
        catch { throw BackupError.writeFailed }
    }

    /// Consumes the staged request, so a failing restore cannot repeat on every launch.
    public func takePendingRestore() -> String? {
        defer { try? FileManager.default.removeItem(at: pendingRestoreURL) }
        guard let bytes = try? Data(contentsOf: pendingRestoreURL), let id = String(data: bytes, encoding: .utf8),
              Self.preChangeNames.contains(id) || Self.isDirectoryBackupID(id) else { return nil }
        return id
    }

    // MARK: Files

    static func isDirectoryBackupID(_ id: String) -> Bool {
        if id == lastSessionID { return true }
        let parts = id.split(separator: "-", omittingEmptySubsequences: false)
        return parts.count == 4 && parts[0] == "daily" && parts[1].count == 4 && parts[2].count == 2 && parts[3].count == 2
            && parts.dropFirst().allSatisfy { $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }
    }

    private func dailyID(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "daily-%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func snapshotURL(_ name: String) -> URL {
        directory.appendingPathComponent("organization.snapshot.\(name).json")
    }

    private func readManifest(_ id: String) -> Manifest? {
        guard let bytes = try? readRegular(root.appendingPathComponent(id).appendingPathComponent("manifest.json")) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Manifest.self, from: bytes)
    }

    private func modificationDate(_ url: URL) -> Date? {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
    }

    private func readRegular(_ url: URL) throws -> Data {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              let bytes = try? Data(contentsOf: url) else { throw BackupError.unreadable }
        return bytes
    }

    /// Settings paths come from a backup, so they must stay inside the state directory and never follow a link.
    private func writeSettingsFile(_ bytes: Data, relativePath: String) throws {
        let target = try Self.safeURL(relativePath, under: directory)
        var info = stat()
        if lstat(target.path, &info) == 0, info.st_mode & S_IFMT != S_IFREG { throw BackupError.unsafePath }
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: target, options: .atomic)
        } catch { throw BackupError.writeFailed }
    }

    static func safeURL(_ relativePath: String, under base: URL) throws -> URL {
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = parts.allSatisfy { part in
            !part.isEmpty && part != "." && part != ".." && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
        }
        guard allowed, !parts.isEmpty else { throw BackupError.unsafePath }
        return parts.reduce(base) { $0.appendingPathComponent(String($1)) }
    }

    private func write(id: String, organization: Data, files: [String: Data]) throws {
        let manager = FileManager.default
        let staging = root.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: staging) }
        do {
            try manager.createDirectory(at: staging, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try organization.write(to: staging.appendingPathComponent("organization.json"))
            for (relative, bytes) in files {
                let target = try Self.safeURL(relative, under: staging.appendingPathComponent("files", isDirectory: true))
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: target)
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            // The manifest goes last: a copy without one is incomplete and never listed.
            try encoder.encode(Manifest(createdAt: now())).write(to: staging.appendingPathComponent("manifest.json"))
            let destination = root.appendingPathComponent(id, isDirectory: true)
            if manager.fileExists(atPath: destination.path) {
                _ = try manager.replaceItemAt(destination, withItemAt: staging)
            } else {
                try manager.moveItem(at: staging, to: destination)
            }
        } catch let error as BackupError {
            throw error
        } catch { throw BackupError.writeFailed }
    }
}
