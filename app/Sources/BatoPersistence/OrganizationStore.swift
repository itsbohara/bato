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

        public var errorDescription: String? {
            switch self {
            case .loadRequired: "Load organization before saving changes."
            case .conflict: "Organization changed outside this session. Reload before saving."
            case .unsafeFile: "Organization storage contains an unsupported file type."
            case .corruptState: "Organization could not be decoded. The existing document was preserved."
            case .invalidState: "Organization is invalid or uses an unsupported format."
            case .fileOperationFailed: "Organization could not be read or saved."
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

    private func readDocument() throws -> Data? {
        try checkRegularOrAbsent(documentURL)
        let descriptor = open(documentURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
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
