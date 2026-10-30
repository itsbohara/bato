import Foundation
import XCTest
import Darwin
@testable import BatoPersistence

final class OrganizationStoreTests: XCTestCase {
    private struct Document: Codable, Equatable {
        var version = 1
        var entries: [String]
    }

    private typealias Store = OrganizationStore<Document>

    private func store(_ directory: URL) -> Store {
        Store(directory: directory) { document in
            guard document.version == 1, !document.entries.contains("") else {
                throw ValidationError.invalid
            }
        }
    }

    private enum ValidationError: Error { case invalid }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bato-store-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    func testRoundTripAndPreviousGoodBackup() throws {
        try withDirectory { directory in
            let first = Document(entries: ["first"])
            let second = Document(entries: ["first", "second"])
            let writer = store(directory)
            XCTAssertNil(try writer.load())
            try writer.save(first)
            try writer.save(second)
            XCTAssertEqual(try store(directory).load(), second)
            let backup = try Data(contentsOf: directory.appendingPathComponent("organization.last-good.json"))
            XCTAssertEqual(try JSONDecoder().decode(Document.self, from: backup), first)
        }
    }

    func testValidationFailurePreservesCommittedDocument() throws {
        try withDirectory { directory in
            let writer = store(directory)
            _ = try writer.load()
            try writer.save(Document(entries: ["saved"]))
            let path = directory.appendingPathComponent("organization.json")
            let before = try Data(contentsOf: path)
            XCTAssertThrowsError(try writer.save(Document(entries: [""]))) {
                XCTAssertEqual($0 as? Store.StoreError, .invalidState)
            }
            XCTAssertEqual(try Data(contentsOf: path), before)
            XCTAssertEqual(try store(directory).load(), Document(entries: ["saved"]))
        }
    }

    func testCorruptAndUnsupportedDocumentsArePreserved() throws {
        for bytes in [Data("not json".utf8), try JSONEncoder().encode(Document(version: 2, entries: ["future"]))] {
            try withDirectory { directory in
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let path = directory.appendingPathComponent("organization.json")
                try bytes.write(to: path)
                let writer = store(directory)
                XCTAssertThrowsError(try writer.load())
                XCTAssertThrowsError(try writer.save(Document(entries: ["replacement"]))) {
                    XCTAssertEqual($0 as? Store.StoreError, .loadRequired)
                }
                XCTAssertEqual(try Data(contentsOf: path), bytes)
            }
        }
    }

    func testStaleWriterCannotOverwriteNewerCommit() throws {
        try withDirectory { directory in
            let first = store(directory)
            let stale = store(directory)
            _ = try first.load()
            _ = try stale.load()
            try first.save(Document(entries: ["newer"]))
            XCTAssertThrowsError(try stale.save(Document(entries: ["stale"]))) {
                XCTAssertEqual($0 as? Store.StoreError, .conflict)
            }
            XCTAssertEqual(try stale.load(), Document(entries: ["newer"]))
            try stale.save(Document(entries: ["reloaded"]))
            XCTAssertEqual(try first.load(), Document(entries: ["reloaded"]))
        }
    }

    func testSaveRequiresSuccessfulLoad() throws {
        try withDirectory { directory in
            XCTAssertThrowsError(try store(directory).save(Document(entries: ["new"]))) {
                XCTAssertEqual($0 as? Store.StoreError, .loadRequired)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        }
    }

    func testSymlinkTargetsAreRefusedWithoutFollowingThem() throws {
        for filename in ["organization.json", "organization.last-good.json", "organization.lock"] {
            try withDirectory { directory in
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let target = directory.appendingPathComponent("untouched.json")
                let bytes = try JSONEncoder().encode(Document(entries: ["untouched"]))
                try bytes.write(to: target)
                try FileManager.default.createSymbolicLink(
                    at: directory.appendingPathComponent(filename), withDestinationURL: target)
                XCTAssertThrowsError(try store(directory).load()) {
                    XCTAssertEqual($0 as? Store.StoreError, .unsafeFile)
                }
                XCTAssertEqual(try Data(contentsOf: target), bytes)
            }
        }
    }

    func testBackupFailureDoesNotReplaceCurrentDocument() throws {
        try withDirectory { directory in
            let writer = store(directory)
            _ = try writer.load()
            try writer.save(Document(entries: ["committed"]))
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("organization.last-good.json"),
                withIntermediateDirectories: false)
            XCTAssertThrowsError(try writer.save(Document(entries: ["replacement"]))) {
                XCTAssertEqual($0 as? Store.StoreError, .unsafeFile)
            }
            let bytes = try Data(contentsOf: directory.appendingPathComponent("organization.json"))
            XCTAssertEqual(try JSONDecoder().decode(Document.self, from: bytes), Document(entries: ["committed"]))
        }
    }

    func testUnwritableDirectoryPreservesCommittedDocument() throws {
        guard geteuid() != 0 else { throw XCTSkip("Permission failure requires an unprivileged user.") }
        try withDirectory { directory in
            let writer = store(directory)
            _ = try writer.load()
            try writer.save(Document(entries: ["committed"]))
            let path = directory.appendingPathComponent("organization.json")
            let before = try Data(contentsOf: path)
            XCTAssertEqual(chmod(directory.path, 0o500), 0)
            defer { _ = chmod(directory.path, 0o700) }
            XCTAssertThrowsError(try writer.save(Document(entries: ["replacement"]))) {
                XCTAssertEqual($0 as? Store.StoreError, .fileOperationFailed)
            }
            XCTAssertEqual(try Data(contentsOf: path), before)
            XCTAssertEqual(try store(directory).load(), Document(entries: ["committed"]))
        }
    }

    func testCommittedDocumentsHavePrivatePermissions() throws {
        try withDirectory { directory in
            let writer = store(directory)
            _ = try writer.load()
            try writer.save(Document(entries: ["first"]))
            try writer.save(Document(entries: ["second"]))
            for name in ["organization.json", "organization.last-good.json"] {
                let attributes = try FileManager.default.attributesOfItem(
                    atPath: directory.appendingPathComponent(name).path)
                XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            }
        }
    }
}
