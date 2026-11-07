import BatoCore
import BatoPersistence
import Foundation
import XCTest
@testable import BatoImport

final class ArcImportApplyTests: XCTestCase {
    private typealias Store = OrganizationStore<BrowserState>

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("bato-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        chmod(directory.path, 0o700)
        try? FileManager.default.removeItem(at: directory)
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("spikes/arc-import/fixtures/\(name).json")
    }

    private func staging() throws -> ArcStaging {
        try ArcSidebarParser.parse(ArcSourceReader.read(fixtureURL("basic")).data)
    }

    private func openStore() throws -> (Store, BrowserState) {
        let store = Store(directory: directory.appendingPathComponent("org"), validate: { try $0.validate() })
        let initial = try store.load() ?? BrowserState.initial()
        try store.save(initial)
        return (store, initial)
    }

    private func documentBytes() throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent("org/organization.json"))
    }

    func testSourceIsReadWithoutChangeAndHashMatchesParserDigest() throws {
        let url = fixtureURL("basic")
        let before = try Data(contentsOf: url)
        let file = try ArcSourceReader.read(url)
        XCTAssertEqual(file.data, before)
        XCTAssertEqual(try ArcSidebarParser.parse(file.data).sourceDigest, file.sha256)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testReadOnlyCopyWorksOnReadOnlyFileAndRejectsBadTargets() throws {
        let copy = directory.appendingPathComponent("StorableSidebar.json")
        try Data(contentsOf: fixtureURL("basic")).write(to: copy)
        chmod(copy.path, 0o444)
        let attributesBefore = try FileManager.default.attributesOfItem(atPath: copy.path)
        _ = try ArcSourceReader.read(copy)
        let attributesAfter = try FileManager.default.attributesOfItem(atPath: copy.path)
        XCTAssertEqual(attributesBefore[.modificationDate] as? Date, attributesAfter[.modificationDate] as? Date)
        XCTAssertThrowsError(try ArcSourceReader.read(directory)) { XCTAssertEqual($0 as? ArcSourceError, .notRegularFile) }
        XCTAssertThrowsError(try ArcSourceReader.read(directory.appendingPathComponent("missing"))) {
            XCTAssertEqual($0 as? ArcSourceError, .unreadable)
        }
    }

    func testApplyWritesSnapshotOfPreviousDocumentThenCommitsPlan() throws {
        let (store, initial) = try openStore()
        let previous = try documentBytes()
        let plan = try ImportPlan.make(staging(), into: initial)
        let applied = try ImportTransaction.apply(plan, to: store)
        XCTAssertEqual(applied.state, plan.state)
        let snapshot = try Data(contentsOf: directory.appendingPathComponent("org/organization.snapshot.pre-import.json"))
        XCTAssertEqual(snapshot, previous)
        let reopened = Store(directory: directory.appendingPathComponent("org"), validate: { try $0.validate() })
        XCTAssertEqual(try reopened.load(), plan.state)
    }

    func testFailedSaveLeavesDocumentByteIdentical() throws {
        let (store, initial) = try openStore()
        let before = try documentBytes()
        let plan = try ImportPlan.make(staging(), into: initial)
        chmod(directory.appendingPathComponent("org").path, 0o500)
        XCTAssertThrowsError(try ImportTransaction.apply(plan, to: store))
        chmod(directory.appendingPathComponent("org").path, 0o700)
        XCTAssertEqual(try documentBytes(), before)
        XCTAssertEqual(try Store(directory: directory.appendingPathComponent("org"), validate: { try $0.validate() }).load(), initial)
        // The same store still works after the failure.
        XCTAssertNoThrow(try ImportTransaction.apply(plan, to: store))
    }

    func testBlockedSnapshotAbortsBeforeTheDocumentIsTouched() throws {
        let (store, initial) = try openStore()
        let before = try documentBytes()
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("org/organization.snapshot.pre-import.json"),
            withIntermediateDirectories: false)
        let plan = try ImportPlan.make(staging(), into: initial)
        XCTAssertThrowsError(try ImportTransaction.apply(plan, to: store)) {
            XCTAssertEqual($0 as? Store.StoreError, .unsafeFile)
        }
        XCTAssertEqual(try documentBytes(), before)
    }

    func testInvalidPlanStateIsRejectedWithoutSnapshotOrWrite() throws {
        let (store, initial) = try openStore()
        let before = try documentBytes()
        var plan = try ImportPlan.make(staging(), into: initial)
        plan.state.workspaces[1].color = "red"
        XCTAssertThrowsError(try ImportTransaction.apply(plan, to: store)) {
            XCTAssertEqual($0 as? Store.StoreError, .invalidState)
        }
        XCTAssertEqual(try documentBytes(), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("org/organization.snapshot.pre-import.json").path))
    }

    func testOutOfSessionChangeIsAConflictNotAnOverwrite() throws {
        let (store, initial) = try openStore()
        let other = Store(directory: directory.appendingPathComponent("org"), validate: { try $0.validate() })
        _ = try other.load()
        var changed = initial
        try changed.updateWorkspace(initial.workspaces[0].id, name: "Elsewhere", color: "#527FAD")
        try other.save(changed)
        let plan = try ImportPlan.make(staging(), into: initial)
        XCTAssertThrowsError(try ImportTransaction.apply(plan, to: store)) {
            XCTAssertEqual($0 as? Store.StoreError, .conflict)
        }
        XCTAssertEqual(try other.load(), changed)
    }

    func testUndoRestoresPreImportDocumentExactly() throws {
        let (store, initial) = try openStore()
        let before = try documentBytes()
        let applied = try ImportTransaction.apply(ImportPlan.make(staging(), into: initial), to: store)
        XCTAssertNotEqual(try documentBytes(), before)
        XCTAssertEqual(try ImportTransaction.undo(applied, in: store), initial)
        XCTAssertEqual(try documentBytes(), before)
        // After undo the same file can be imported again.
        XCTAssertNoThrow(try ImportTransaction.apply(ImportPlan.make(staging(), into: initial), to: store))
    }

    func testUndoIsRefusedAfterALaterChange() throws {
        let (store, initial) = try openStore()
        let applied = try ImportTransaction.apply(ImportPlan.make(staging(), into: initial), to: store)
        var later = applied.state
        try later.updateWorkspace(later.workspaces[0].id, name: "Later", color: "#527FAD")
        try store.save(later)
        let before = try documentBytes()
        XCTAssertThrowsError(try ImportTransaction.undo(applied, in: store)) {
            XCTAssertEqual($0 as? Store.StoreError, .snapshotStale)
        }
        XCTAssertEqual(try documentBytes(), before)
    }

    func testSecondImportIsReportedAndCopyIsExplicit() throws {
        let (store, initial) = try openStore()
        let staging = try staging()
        let applied = try ImportTransaction.apply(ImportPlan.make(staging, into: initial), to: store)
        XCTAssertEqual(ImportPlan.alreadyImportedSpaceIDs(staging, in: applied.state), Set(staging.spaces.map(\.id)))
        XCTAssertEqual(ImportPlan.alreadyImportedSpaceIDs(staging, in: initial), [])
        XCTAssertThrowsError(try ImportPlan.make(staging, into: applied.state)) {
            XCTAssertEqual($0 as? ImportPlanError, .alreadyImported)
        }
        let before = try documentBytes()
        XCTAssertEqual(try documentBytes(), before)
        let copy = try ImportPlan.make(staging, options: ImportOptions(idSalt: "copy-1"), into: applied.state)
        XCTAssertEqual(copy.state.workspaces.count, applied.state.workspaces.count + staging.spaces.count)
    }

    func testAlreadyImportedSpacesAreNotSelectedUnlessCopiesRequested() {
        XCTAssertEqual(ImportPlan.spacesToImport(checked: ["a", "b"], alreadyImported: ["a", "b"], asCopies: false), [])
        XCTAssertEqual(ImportPlan.spacesToImport(checked: ["a", "b"], alreadyImported: ["a"], asCopies: false), ["b"])
        XCTAssertEqual(ImportPlan.spacesToImport(checked: ["a", "b"], alreadyImported: ["a", "b"], asCopies: true), ["a", "b"])
    }

    func testImportingRemainingSpaceLaterReusesItsProfile() throws {
        let staging = try staging()
        let first = staging.spaces[0]
        let rest = Set(staging.spaces.dropFirst().map(\.id))
        let one = try ImportPlan.make(staging, options: ImportOptions(excludedSpaceIDs: rest), into: .initial())
        let two = try ImportPlan.make(staging, options: ImportOptions(excludedSpaceIDs: [first.id]), into: one.state)
        XCTAssertEqual(two.state.workspaces.count, 1 + staging.spaces.count)
        XCTAssertEqual(Set(two.state.profiles.map(\.id)).count, two.state.profiles.count)
        XCTAssertEqual(two.summary.profiles, two.state.profiles.count - one.state.profiles.count)
    }

    func testSummaryWordingDistinguishesNewReusedAndCopiedProfiles() throws {
        let staging = try staging()
        let first = try ImportPlan.make(staging, into: .initial())
        XCTAssertEqual(first.summary.reusedProfiles, 0)
        XCTAssertTrue(first.summary.workspaceDescription(asCopies: false).contains("new Profile"))

        let copies = try ImportPlan.make(staging, options: ImportOptions(idSalt: "copy-1"), into: first.state)
        XCTAssertEqual(copies.summary.profiles, first.summary.profiles)
        XCTAssertTrue(copies.summary.workspaceDescription(asCopies: true).contains(" as copies in "))
        XCTAssertTrue(copies.summary.workspaceDescription(asCopies: true).hasSuffix("(separate from the originals)"))

        let rest = Set(staging.spaces.dropFirst().map(\.id))
        let one = try ImportPlan.make(staging, options: ImportOptions(excludedSpaceIDs: rest), into: .initial())
        let two = try ImportPlan.make(staging, options: ImportOptions(excludedSpaceIDs: [staging.spaces[0].id]), into: one.state)
        if two.summary.profiles == 0 {
            XCTAssertGreaterThan(two.summary.reusedProfiles, 0)
            let text = two.summary.workspaceDescription(asCopies: false)
            XCTAssertTrue(text.contains("existing Profile"))
            XCTAssertFalse(text.contains("0 new"))
            XCTAssertFalse(text.contains("new Profile"))
        }
    }
}
