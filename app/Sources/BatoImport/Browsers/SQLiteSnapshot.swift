import Foundation
import SQLite3

enum SQLValue: Equatable {
    case int(Int64), double(Double), text(String), blob(Data), null

    var int: Int64? {
        switch self {
        case .int(let value): value
        case .double(let value): Int64(value)
        default: nil
        }
    }
    var double: Double? {
        switch self {
        case .int(let value): Double(value)
        case .double(let value): value
        default: nil
        }
    }
    var text: String? { if case .text(let value) = self { value } else { nil } }
}

private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thin wrapper over the system libsqlite3. `copyOf` never opens the browser's own file: the
/// database (and its -wal/-shm companions) is copied to a private temp directory first, because the
/// original is locked while the browser runs, and the copy is opened read-only and deleted on close.
final class SQLiteDatabase {
    private var handle: OpaquePointer?
    private let cleanup: URL?

    static func copyOf(_ source: URL) throws -> SQLiteDatabase {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent("bato-import-\(UUID().uuidString)")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        do {
            let target = directory.appendingPathComponent("db.sqlite")
            try copy(source, to: target)
            for suffix in ["-wal", "-shm"] where fileManager.fileExists(atPath: source.path + suffix) {
                try? copy(URL(fileURLWithPath: source.path + suffix), to: URL(fileURLWithPath: target.path + suffix))
            }
            return try SQLiteDatabase(path: target.path, readOnly: true, cleanup: directory)
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    /// Read-write, for a database no browser has open. Creates the file when `create` is set.
    static func open(_ url: URL, create: Bool = false) throws -> SQLiteDatabase {
        try SQLiteDatabase(path: url.path, readOnly: false, create: create, cleanup: nil)
    }

    private static func copy(_ source: URL, to target: URL) throws {
        do {
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            let nsError = error as NSError
            let posix = nsError.domain == NSPOSIXErrorDomain ? nsError.code
                : (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.code
            if nsError.code == NSFileReadNoPermissionError || posix == Int(EPERM) || posix == Int(EACCES) {
                throw ImportReadError.permissionDenied
            }
            throw ImportReadError.unreadable
        }
    }

    private init(path: String, readOnly: Bool, create: Bool = false, cleanup: URL?) throws {
        self.cleanup = cleanup
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | (create ? SQLITE_OPEN_CREATE : 0)
        guard sqlite3_open_v2(path, &handle, flags | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            if let cleanup { try? FileManager.default.removeItem(at: cleanup) }
            throw ImportReadError.unreadable
        }
        sqlite3_busy_timeout(handle, 2_000)
    }

    deinit {
        sqlite3_close(handle)
        if let cleanup { try? FileManager.default.removeItem(at: cleanup) }
    }

    func execute(_ sql: String, _ bindings: [SQLValue] = []) throws {
        _ = try rows(sql, bindings)
    }

    func rows(_ sql: String, _ bindings: [SQLValue] = []) throws -> [[SQLValue]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw ImportReadError.unreadable }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .int(let number): sqlite3_bind_int64(statement, index, number)
            case .double(let number): sqlite3_bind_double(statement, index, number)
            case .text(let text): sqlite3_bind_text(statement, index, text, -1, transient)
            case .blob(let data):
                _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), transient) }
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        var result: [[SQLValue]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW else { throw ImportReadError.unreadable }
            result.append((0..<sqlite3_column_count(statement)).map { column in
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: .int(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT: .double(sqlite3_column_double(statement, column))
                case SQLITE_TEXT: .text(String(cString: sqlite3_column_text(statement, column)))
                case SQLITE_BLOB:
                    .blob(Data(bytes: sqlite3_column_blob(statement, column), count: Int(sqlite3_column_bytes(statement, column))))
                default: .null
                }
            })
        }
    }

    func scalarInt(_ sql: String) throws -> Int {
        Int(try rows(sql).first?.first?.int ?? 0)
    }

    func hasTable(_ name: String) throws -> Bool {
        try !rows("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", [.text(name)]).isEmpty
    }

    func columns(of table: String) throws -> Set<String> {
        Set(try rows("PRAGMA table_info(\(table))").compactMap { $0[1].text })
    }
}
