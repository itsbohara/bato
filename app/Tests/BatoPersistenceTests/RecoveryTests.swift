import Foundation
import XCTest
@testable import BatoPersistence

final class RecoveryTests: XCTestCase {
    private struct Document: Codable, Equatable {
        var version = 1
        var entries: [String]
    }

    private typealias Store = OrganizationStore<Document>

    private func makeStore(_ directory: URL) -> Store {
        Store(directory: directory) { document in
            guard document.version == 1 else { throw NSError(domain: "invalid", code: 1) }
        }
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bato-recovery-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try body(directory)
    }

    private func coordinator(_ directory: URL, pid: Int32, alive: Set<Int32> = [],
                             backups: BackupStore? = nil) -> RecoveryCoordinator {
        RecoveryCoordinator(directory: directory, backups: backups ?? BackupStore(directory: directory),
                            processID: pid, isProcessAlive: { alive.contains($0) }, bootDate: { .distantPast })
    }

    private func bytes(_ text: String) -> Data { Data(text.utf8) }

    // MARK: Abnormal termination

    func testFirstLaunchAndCleanQuitAreNotAbnormal() throws {
        try withDirectory { directory in
            XCTAssertEqual(coordinator(directory, pid: 10).beginLaunch(), .clean)
            let first = coordinator(directory, pid: 10)
            _ = first.beginLaunch()
            first.endCleanly()
            XCTAssertEqual(coordinator(directory, pid: 11).beginLaunch(), .clean)
        }
    }

    func testMissingCleanQuitIsAbnormalAndReportsTheUnconfirmedLaunch() throws {
        try withDirectory { directory in
            _ = coordinator(directory, pid: 10).beginLaunch()
            let status = coordinator(directory, pid: 11).beginLaunch()
            guard case .abnormal(let crash) = status else { return XCTFail("expected abnormal, got \(status)") }
            XCTAssertFalse(crash.previousLaunchConfirmed)
            XCTAssertEqual(crash.consecutiveFailures, 1)
            XCTAssertFalse(crash.isRepeating)
        }
    }

    func testUnconfirmedLaunchesCountAsRepeatingAndConfirmationResetsTheCount() throws {
        try withDirectory { directory in
            _ = coordinator(directory, pid: 10).beginLaunch()
            _ = coordinator(directory, pid: 11).beginLaunch()
            guard case .abnormal(let second) = coordinator(directory, pid: 12).beginLaunch() else { return XCTFail() }
            XCTAssertEqual(second.consecutiveFailures, 2)
            XCTAssertTrue(second.isRepeating)

            let recovered = coordinator(directory, pid: 13)
            _ = recovered.beginLaunch()
            recovered.confirmLaunch(organization: bytes("{}"), files: [:])
            guard case .abnormal(let afterConfirmed) = coordinator(directory, pid: 14).beginLaunch() else { return XCTFail() }
            XCTAssertTrue(afterConfirmed.previousLaunchConfirmed)
            XCTAssertEqual(afterConfirmed.consecutiveFailures, 1)
        }
    }

    func testLiveOtherProcessLeavesMarkerAlone() throws {
        try withDirectory { directory in
            _ = coordinator(directory, pid: 10).beginLaunch()
            let intruder = coordinator(directory, pid: 11, alive: [10])
            XCTAssertEqual(intruder.beginLaunch(), .concurrent)
            intruder.endCleanly()
            guard case .abnormal = coordinator(directory, pid: 12).beginLaunch() else {
                return XCTFail("the live process's marker must survive the second launch")
            }
        }
    }

    func testMarkerFromBeforeBootIsNotMistakenForALiveProcess() throws {
        try withDirectory { directory in
            _ = coordinator(directory, pid: 10).beginLaunch()
            let rebooted = RecoveryCoordinator(directory: directory, backups: BackupStore(directory: directory), processID: 11,
                                               isProcessAlive: { _ in true }, bootDate: { Date().addingTimeInterval(3600) })
            guard case .abnormal = rebooted.beginLaunch() else { return XCTFail("a recycled PID must not hide a crash") }
        }
    }

    func testUnreadableMarkerIsAbnormal() throws {
        try withDirectory { directory in
            try bytes("not json").write(to: directory.appendingPathComponent("session.marker"))
            guard case .abnormal = coordinator(directory, pid: 10).beginLaunch() else { return XCTFail() }
        }
    }

    // MARK: Recovery snapshot retention

    func testRecoverySnapshotSurvivesCrashingLaunchesUntilOneIsConfirmed() throws {
        try withDirectory { directory in
            let backups = BackupStore(directory: directory)
            let good = coordinator(directory, pid: 10, backups: backups)
            _ = good.beginLaunch()
            good.captureSessionStart(organization: bytes("session-1"), files: [:])
            good.confirmLaunch(organization: bytes("edited-1"), files: [:])

            for pid: Int32 in 11...13 {
                let crashing = coordinator(directory, pid: pid, backups: backups)
                _ = crashing.beginLaunch()
                crashing.captureSessionStart(organization: bytes("crashed-\(pid)"), files: [:])
            }
            XCTAssertEqual(try backups.contents(of: BackupStore.lastSessionID).organization, bytes("session-1"))

            let recovered = coordinator(directory, pid: 14, backups: backups)
            _ = recovered.beginLaunch()
            recovered.captureSessionStart(organization: bytes("session-2"), files: [:])
            XCTAssertEqual(try backups.contents(of: BackupStore.lastSessionID).organization, bytes("session-1"),
                           "capturing at launch must not replace the snapshot")
            recovered.confirmLaunch(organization: bytes("edited-2"), files: [:])
            XCTAssertEqual(try backups.contents(of: BackupStore.lastSessionID).organization, bytes("session-2"),
                           "the snapshot is the session start, not the state at confirmation")
            XCTAssertFalse(backups.list().contains { $0.id == "pending-session" })
        }
    }

    func testLaunchNeverRestoresOrRelaunchesByItself() throws {
        try withDirectory { directory in
            let store = makeStore(directory)
            _ = try store.load()
            try store.save(Document(entries: ["crash-state"]))
            _ = coordinator(directory, pid: 10).beginLaunch()
            _ = coordinator(directory, pid: 11).beginLaunch()
            XCTAssertEqual(try makeStore(directory).load(), Document(entries: ["crash-state"]))
        }
    }

    // MARK: Store migration

    func testMigrationKeepsPreMigrationSnapshotAndSurvivesFailure() throws {
        try withDirectory { directory in
            let store = makeStore(directory)
            _ = try store.load()
            try store.save(Document(entries: ["old"]))
            let before = try Data(contentsOf: directory.appendingPathComponent("organization.json"))

            XCTAssertThrowsError(try store.migrate { _ in throw NSError(domain: "x", code: 1) }) {
                XCTAssertEqual($0 as? Store.StoreError, .migrationFailed)
            }
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("organization.json")), before)
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("organization.snapshot.pre-migration.json").path))

            XCTAssertThrowsError(try store.migrate { _ in Document(version: 2, entries: []) }) {
                XCTAssertEqual($0 as? Store.StoreError, .invalidState)
            }
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("organization.json")), before)

            let migrated = try store.migrate { Document(entries: $0.entries + ["new"]) }
            XCTAssertEqual(migrated.entries, ["old", "new"])
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("organization.snapshot.pre-migration.json")), before)
        }
    }

    func testUnsupportedStoredVersionFailsToLoadWithoutTouchingTheFile() throws {
        try withDirectory { directory in
            let future = bytes(#"{"version": 9, "entries": ["keep"]}"#)
            let url = directory.appendingPathComponent("organization.json")
            try future.write(to: url)
            XCTAssertThrowsError(try makeStore(directory).load()) {
                XCTAssertEqual($0 as? Store.StoreError, .invalidState)
            }
            XCTAssertEqual(try Data(contentsOf: url), future)
        }
    }

    func testCommittedDocumentMatchesDisk() throws {
        try withDirectory { directory in
            let store = makeStore(directory)
            XCTAssertNil(try store.committedDocument())
            _ = try store.load()
            try store.save(Document(entries: ["a"]))
            XCTAssertEqual(try store.committedDocument(),
                           try Data(contentsOf: directory.appendingPathComponent("organization.json")))
        }
    }
}
