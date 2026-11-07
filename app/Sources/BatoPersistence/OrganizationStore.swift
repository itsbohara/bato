import Foundation
import Darwin

/// A single local organization document. Engine-owned browser data is never stored here.
/// Call `load` before saving; a changed on-disk document requires an explicit reload.
public final class OrganizationStore<State: Codable> {
    public enum StoreError: Error, LocalizedError, Equatable {
        case loadRequired
        case conflict
        case unsafeFile
        case corruptState
        case invalidState
        case fileOperationFailed
        case snapshotUnavailable
        case snapshotStale
        case migrationFailed

        public var errorDescription: String? {
            switch self {
            case .loadRequired: "Load organization before saving changes."
            case .conflict: "Organization changed outside this session. Reload before saving."
            case .unsafeFile: "Organization storage contains an unsupported file type."
            case .corruptState: "Organization could not be decoded. The existing document was preserved."
            case .invalidState: "Organization is invalid or uses an unsupported format."
            case .fileOperationFailed: "Organization could not be read or saved."
            case .snapshotUnavailable: "No saved snapshot is available to restore."
            case .snapshotStale: "Organization changed after this snapshot, so it can no longer be restored."
            case .migrationFailed: "Organization could not be upgraded. The previous document and its pre-migration snapshot were kept."
            }
        }
    }

    private let directory: URL
    private let validate: (State) throws -> Void
    private var loaded = false
    private var knownBytes: Data?

    public init(directory: URL, validate: @escaping (State) throws -> Void) {
        self.directory = directory
        self.validate = validate
    }

    public func load() throws -> State? {
        loaded = false
        return try withLock {
            try checkRegularOrAbsent(backupURL)
            let bytes = try readDocument()
            let state: State?
            if let bytes {
                let decoded: State
                do { decoded = try JSONDecoder().decode(State.self, from: bytes) }
                catch { throw StoreError.corruptState }
                do { try validate(decoded) }
                catch { throw StoreError.invalidState }
                state = decoded
            } else {
                state = nil
            }
            knownBytes = bytes
            loaded = true
            return state
        }
    }

    public func save(_ state: State) throws {
        guard loaded else { throw StoreError.loadRequired }
        do { try validate(state) }
        catch { throw StoreError.invalidState }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes: Data
        do { bytes = try encoder.encode(state) }
        catch { throw StoreError.invalidState }

        try withLock {
            try checkRegularOrAbsent(backupURL)
            let current = try readDocument()
            guard current == knownBytes else { throw StoreError.conflict }
            // Keep the previous successfully loaded document before replacing it.
            // Backup failure aborts the save, preserving the current document.
            if let current {
                try atomicWrite(current, to: backupURL)
            }
            try atomicWrite(bytes, to: documentURL)
            knownBytes = bytes
        }
    }

    /// Proof of one `saveWithSnapshot`: restoring is allowed only while the document is still the committed bytes.
    public struct Snapshot: Equatable, Sendable {
        fileprivate let name: String
        fileprivate let committedBytes: Data
    }

    /// Saves `state` and keeps the previous document as a named snapshot in one locked step.
    /// A failure at any point leaves the committed document byte-identical. Snapshot names are
    /// single-slot: a later call with the same name replaces the earlier snapshot.
    public func saveWithSnapshot(_ state: State, named name: String) throws -> Snapshot {
        guard loaded else { throw StoreError.loadRequired }
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            throw StoreError.invalidState
        }
        do { try validate(state) }
        catch { throw StoreError.invalidState }
        let bytes = try encode(state)
        return try withLock {
            try checkRegularOrAbsent(backupURL)
            let current = try readDocument()
            guard current == knownBytes else { throw StoreError.conflict }
            guard let current else { throw StoreError.snapshotUnavailable }
            try atomicWrite(current, to: snapshotURL(name))
            try atomicWrite(current, to: backupURL)
            try atomicWrite(bytes, to: documentURL)
            knownBytes = bytes
            return Snapshot(name: name, committedBytes: bytes)
        }
    }

    /// Replaces the document with the snapshot's content, only if nothing has been saved since
    /// `saveWithSnapshot` returned it. Returns the restored state.
    public func restore(_ snapshot: Snapshot) throws -> State {
        guard loaded else { throw StoreError.loadRequired }
        return try withLock {
            try checkRegularOrAbsent(backupURL)
            let current = try readDocument()
            guard current == knownBytes else { throw StoreError.conflict }
            guard current == snapshot.committedBytes else { throw StoreError.snapshotStale }
            try checkRegularOrAbsent(snapshotURL(snapshot.name))
            guard let saved = try readFile(snapshotURL(snapshot.name)) else { throw StoreError.snapshotUnavailable }
            let restored: State
            do { restored = try JSONDecoder().decode(State.self, from: saved) }
            catch { throw StoreError.corruptState }
            do { try validate(restored) }
            catch { throw StoreError.invalidState }
            if let current { try atomicWrite(current, to: backupURL) }
            try atomicWrite(saved, to: documentURL)
            knownBytes = saved
            return restored
        }
    }

    public static var preMigrationSnapshotName: String { "pre-migration" }

    /// Upgrades the loaded document in one step, keeping the previous one as the pre-migration snapshot.
    /// If `transform` or the save fails, the committed document is untouched.
    public func migrate(_ transform: (State) throws -> State) throws -> State {
        guard loaded else { throw StoreError.loadRequired }
        guard let knownBytes else { throw StoreError.snapshotUnavailable }
        let current: State
        do { current = try JSONDecoder().decode(State.self, from: knownBytes) }
        catch { throw StoreError.corruptState }
        let migrated: State
        do { migrated = try transform(current) }
        catch { throw StoreError.migrationFailed }
        _ = try saveWithSnapshot(migrated, named: Self.preMigrationSnapshotName)
        return migrated
    }

    /// The committed document's bytes, read under the store lock so a backup never sees a half-written save.
    public func committedDocument() throws -> Data? {
        try withLock { try readDocument() }
    }

    private func snapshotURL(_ name: String) -> URL {
        directory.appendingPathComponent("organization.snapshot.\(name).json")
    }

    private func encode(_ state: State) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { return try encoder.encode(state) }
        catch { throw StoreError.invalidState }
    }

    private var documentURL: URL { directory.appendingPathComponent("organization.json") }
    private var backupURL: URL { directory.appendingPathComponent("organization.last-good.json") }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        try prepareDirectory()
        let lockURL = directory.appendingPathComponent("organization.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            if errno == ELOOP { throw StoreError.unsafeFile }
            throw StoreError.fileOperationFailed
        }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw StoreError.fileOperationFailed }
        guard info.st_mode & S_IFMT == S_IFREG else { throw StoreError.unsafeFile }
        guard flock(descriptor, LOCK_EX) == 0 else { throw StoreError.fileOperationFailed }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }

    private func prepareDirectory() throws {
        var info = stat()
        if lstat(directory.path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFDIR else { throw StoreError.unsafeFile }
            return
        }
        guard errno == ENOENT else { throw StoreError.fileOperationFailed }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        } catch { throw StoreError.fileOperationFailed }
        // Recheck if another cooperating process created the directory first.
        guard lstat(directory.path, &info) == 0 else { throw StoreError.fileOperationFailed }
        guard info.st_mode & S_IFMT == S_IFDIR else { throw StoreError.unsafeFile }
    }

    private func checkRegularOrAbsent(_ url: URL) throws {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFREG else { throw StoreError.unsafeFile }
        } else if errno != ENOENT {
            throw StoreError.fileOperationFailed
        }
    }

    private func readDocument() throws -> Data? { try readFile(documentURL) }

    private func readFile(_ url: URL) throws -> Data? {
        try checkRegularOrAbsent(url)
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            if errno == ELOOP { throw StoreError.unsafeFile }
            throw StoreError.fileOperationFailed
        }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw StoreError.fileOperationFailed }
        guard info.st_mode & S_IFMT == S_IFREG else { throw StoreError.unsafeFile }
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 { return bytes }
            if count < 0 {
                if errno == EINTR { continue }
                throw StoreError.fileOperationFailed
            }
            bytes.append(contentsOf: buffer.prefix(count))
        }
    }

    private func atomicWrite(_ bytes: Data, to url: URL) throws {
        try checkRegularOrAbsent(url)
        let temporary = directory.appendingPathComponent(".organization-\(UUID().uuidString).tmp")
        let descriptor = open(
            temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw StoreError.fileOperationFailed }
        var descriptorOpen = true
        defer {
            if descriptorOpen { Darwin.close(descriptor) }
            _ = unlink(temporary.path)
        }

        try bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw StoreError.fileOperationFailed
                }
                guard count > 0 else { throw StoreError.fileOperationFailed }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw StoreError.fileOperationFailed }
        let closeResult = Darwin.close(descriptor)
        descriptorOpen = false
        guard closeResult == 0 else { throw StoreError.fileOperationFailed }
        // Permissions and all fallible preparation happen before this commit point.
        // After replacement succeeds, callers must adopt the committed document.
        guard rename(temporary.path, url.path) == 0 else { throw StoreError.fileOperationFailed }

        // Directory metadata synchronization is best effort: a failure cannot undo
        // the committed rename and must not be reported as an uncommitted save.
        let directoryDescriptor = open(directory.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if directoryDescriptor >= 0 {
            _ = fsync(directoryDescriptor)
            Darwin.close(directoryDescriptor)
        }
    }
}
