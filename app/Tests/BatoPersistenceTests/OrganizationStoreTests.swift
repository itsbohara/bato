import Foundation
import XCTest
import Darwin
@testable import BatoPersistence
import BatoCore

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

    func testFlatFolderDocumentSurvivesLoadAndSaveByteForByte() throws {
        try withDirectory { directory in
            var state = BrowserState.initial()
            let pin = try state.addTab(url: URL(string: "https://example.invalid/a")!, title: "A")
            try state.pinEntry(pin)
            try state.movePin(pin, toFolder: try state.createFolder(name: "Flat"))
            let writer = OrganizationStore<BrowserState>(directory: directory) { try $0.validate() }
            XCTAssertNil(try writer.load())
            try writer.save(state)
            let document = directory.appendingPathComponent("organization.json")
            let original = try Data(contentsOf: document)
            XCTAssertFalse(String(decoding: original, as: UTF8.self).contains("parentID"))
            let reader = OrganizationStore<BrowserState>(directory: directory) { try $0.validate() }
            let loaded = try XCTUnwrap(try reader.load())
            XCTAssertEqual(loaded.version, 1)
            try reader.save(loaded)
            XCTAssertEqual(try Data(contentsOf: document), original)
        }
    }

    func testNestedFoldersPersistAsVersionTwoAndRoundTrip() throws {
        try withDirectory { directory in
            var state = BrowserState.initial()
            let parent = try state.createFolder(name: "Parent")
            let child = try state.createFolder(name: "Child", parentID: parent)
            let writer = OrganizationStore<BrowserState>(directory: directory) { try $0.validate() }
            XCTAssertNil(try writer.load())
            try writer.save(state)
            let loaded = try XCTUnwrap(try OrganizationStore<BrowserState>(directory: directory) { try $0.validate() }.load())
            XCTAssertEqual(loaded.version, 2)
            XCTAssertEqual(loaded.currentWorkspace.folder(child)?.parentID, parent)
            XCTAssertEqual(loaded, state)
        }
    }

    func testVersionOneDocumentWithNestingIsRejectedOnLoad() throws {
        try withDirectory { directory in
            var state = BrowserState.initial()
            let parent = try state.createFolder(name: "Parent")
            try state.createFolder(name: "Child", parentID: parent)
            state.version = 1
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: directory.appendingPathComponent("organization.json"))
            let reader = OrganizationStore<BrowserState>(directory: directory) { try $0.validate() }
            XCTAssertThrowsError(try reader.load()) { XCTAssertEqual($0 as? OrganizationStore<BrowserState>.StoreError, .invalidState) }
        }
    }

    func testArchivePersistsAsVersionThreeWhileUnusedDocumentsKeepTheirBytes() throws {
        try withDirectory { directory in
            var state = BrowserState.initial()
            let writer = OrganizationStore<BrowserState>(directory: directory) { try $0.validate() }
            XCTAssertNil(try writer.load())
            try writer.save(state)
            let document = directory.appendingPathComponent("organization.json")
            let original = try Data(contentsOf: document)
            XCTAssertFalse(String(decoding: original, as: UTF8.self).contains("archive"))
            let reader = OrganizationStore<BrowserState>(directory: directory) { try $0.validate() }
            var loaded = try XCTUnwrap(try reader.load())
            try reader.save(loaded)
            XCTAssertEqual(try Data(contentsOf: document), original)

            let tab = try loaded.addTab(url: URL(string: "https://example.invalid/a")!, title: "A")
            try loaded.archiveTab(tab, at: Date(timeIntervalSinceReferenceDate: 1))
            try reader.save(loaded)
            let again = try XCTUnwrap(try OrganizationStore<BrowserState>(directory: directory) { try $0.validate() }.load())
            XCTAssertEqual(again.version, 3)
            XCTAssertEqual(again, loaded)
            state = again
            XCTAssertEqual(state.archive.records.map(\.title), ["A"])
        }
    }
}
