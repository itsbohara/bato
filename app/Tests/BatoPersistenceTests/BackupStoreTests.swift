import Foundation
import XCTest
@testable import BatoPersistence

final class BackupStoreTests: XCTestCase {
    private struct Document: Codable, Equatable {
        var version = 1
        var entries: [String]
    }

    private typealias Store = OrganizationStore<Document>

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: Date(timeIntervalSince1970: 1_800_000_000))!
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bato-backup-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try body(directory)
    }

    private func store(_ directory: URL) -> Store {
        Store(directory: directory) { document in
            guard document.version == 1 else { throw NSError(domain: "invalid", code: 1) }
        }
    }

    private func data(_ text: String) -> Data { Data(text.utf8) }

    func testDailyCopyIsWrittenOncePerDayAndKeepsSettingsFiles() throws {
        try withDirectory { directory in
            var clock = day(0)
            let backups = BackupStore(directory: directory, calendar: calendar, now: { clock })
            let files = ["blocking/AAAA/blocking-settings.json": data("{\"enabled\":false}")]
            XCTAssertTrue(try backups.captureDaily(organization: data("one"), files: files))
            XCTAssertFalse(try backups.captureDaily(organization: data("later today"), files: [:]))
            let contents = try backups.contents(of: try XCTUnwrap(backups.list().first).id)
            XCTAssertEqual(contents.organization, data("one"))
            XCTAssertEqual(contents.files, files)
            clock = day(1)
            XCTAssertTrue(try backups.captureDaily(organization: data("two"), files: [:]))
            XCTAssertEqual(backups.list().count, 2)
        }
    }

    func testOnlySevenDailyCopiesAreKept() throws {
        try withDirectory { directory in
            var clock = day(0)
            let backups = BackupStore(directory: directory, calendar: calendar, now: { clock })
            for offset in 0..<10 {
                clock = day(offset)
                try backups.captureDaily(organization: data("day \(offset)"), files: [:])
            }
            backups.prune()
            let kept = backups.list().filter { $0.kind == .daily }
            XCTAssertEqual(kept.count, 7)
            XCTAssertEqual(try backups.contents(of: kept[0].id).organization, data("day 9"))
            XCTAssertEqual(try backups.contents(of: kept[6].id).organization, data("day 3"))
        }
    }

    func testOnlyNewestPreChangeSnapshotIsKept() throws {
        try withDirectory { directory in
            let org = store(directory)
            _ = try org.load()
            try org.save(Document(entries: ["base"]))
            _ = try org.saveWithSnapshot(Document(entries: ["after migration"]), named: "pre-migration")
            let old = directory.appendingPathComponent("organization.snapshot.pre-migration.json")
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: old.path)
            _ = try org.saveWithSnapshot(Document(entries: ["after import"]), named: "pre-import")

            let backups = BackupStore(directory: directory)
            XCTAssertEqual(Set(backups.list().map(\.kind)), [.preMigration, .preImport])
            backups.prune()
            XCTAssertEqual(backups.list().map(\.kind), [.preImport])
        }
    }

    func testRestoreReplacesOrganizationAndSettingsAndKeepsPreRestoreSnapshot() throws {
        try withDirectory { directory in
            let org = store(directory)
            _ = try org.load()
            try org.save(Document(entries: ["current"]))
            let backups = BackupStore(directory: directory, calendar: calendar, now: { self.day(0) })
            let encoded = try JSONEncoder().encode(Document(entries: ["older"]))
            try backups.captureDaily(organization: encoded, files: ["blocking/P1/blocking-settings.json": data("restored")])

            let id = try XCTUnwrap(backups.list().first).id
            let result = try backups.restore(id, into: org)
            XCTAssertEqual(result.state, Document(entries: ["older"]))
            XCTAssertTrue(result.failedFiles.isEmpty)
            XCTAssertEqual(try store(directory).load(), Document(entries: ["older"]))
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("blocking/P1/blocking-settings.json")), data("restored"))
            let preRestore = try backups.contents(of: "pre-restore")
            XCTAssertEqual(try JSONDecoder().decode(Document.self, from: preRestore.organization), Document(entries: ["current"]))
        }
    }

    func testInvalidBackupChangesNothing() throws {
        try withDirectory { directory in
            let org = store(directory)
            _ = try org.load()
            try org.save(Document(entries: ["current"]))
            let before = try Data(contentsOf: directory.appendingPathComponent("organization.json"))
            let backups = BackupStore(directory: directory, calendar: calendar, now: { self.day(0) })

            try backups.captureDaily(organization: data("garbage"), files: ["blocking/P1/blocking-settings.json": data("x")])
            let id = try XCTUnwrap(backups.list().first).id
            XCTAssertThrowsError(try backups.restore(id, into: org)) { XCTAssertEqual($0 as? Store.StoreError, .corruptState) }

            try backups.captureLastSession(organization: try JSONEncoder().encode(Document(version: 7, entries: [])), files: [:])
            XCTAssertThrowsError(try backups.restore(BackupStore.lastSessionID, into: org)) {
                XCTAssertEqual($0 as? Store.StoreError, .invalidState)
            }
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("organization.json")), before)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("blocking").path))
        }
    }

    func testBackupFilesCannotEscapeTheStateDirectory() throws {
        try withDirectory { directory in
            let org = store(directory)
            _ = try org.load()
            try org.save(Document(entries: ["current"]))
            let backups = BackupStore(directory: directory, calendar: calendar, now: { self.day(0) })
            for hostile in ["../escape.json", "/tmp/escape.json", "a//b.json", "a/./b.json", ""] {
                XCTAssertThrowsError(try backups.captureDaily(organization: data("{}"), files: [hostile: data("x")]),
                                     hostile) { XCTAssertEqual($0 as? BackupError, .unsafePath) }
            }
            XCTAssertTrue(backups.list().isEmpty)
        }
    }

    func testStagedRestoreIsConsumedOnce() throws {
        try withDirectory { directory in
            let backups = BackupStore(directory: directory, calendar: calendar, now: { self.day(0) })
            try backups.captureLastSession(organization: data("{}"), files: [:])
            XCTAssertThrowsError(try backups.stageRestore("daily-2000-01-01"))
            try backups.stageRestore(BackupStore.lastSessionID)
            XCTAssertEqual(backups.takePendingRestore(), BackupStore.lastSessionID)
            XCTAssertNil(backups.takePendingRestore())
        }
    }

    func testStagedRestoreCanBeSeenAndCancelled() throws {
        try withDirectory { directory in
            let backups = BackupStore(directory: directory, calendar: calendar, now: { self.day(0) })
            XCTAssertNil(backups.stagedRestore())
            try backups.captureLastSession(organization: data("{}"), files: [:])
            try backups.stageRestore(BackupStore.lastSessionID)
            XCTAssertEqual(backups.stagedRestore()?.id, BackupStore.lastSessionID)
            backups.cancelStagedRestore()
            XCTAssertNil(backups.stagedRestore())
            XCTAssertNil(backups.takePendingRestore())
        }
    }

    func testIncompleteBackupWithoutManifestIsNotListed() throws {
        try withDirectory { directory in
            let broken = directory.appendingPathComponent("backups/daily-2026-01-01")
            try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
            try data("{}").write(to: broken.appendingPathComponent("organization.json"))
            XCTAssertTrue(BackupStore(directory: directory).list().isEmpty)
        }
    }
}
