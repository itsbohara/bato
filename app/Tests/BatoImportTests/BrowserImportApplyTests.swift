import BatoCore
import BatoPersistence
import Foundation
import XCTest
@testable import BatoImport

final class BrowserImportApplyTests: XCTestCase {
    private typealias Store = OrganizationStore<BrowserState>

    private var home: FakeHome!
    private var directory: URL!

    override func setUpWithError() throws {
        home = try FakeHome()
        directory = home.root.appendingPathComponent("bato")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() { home.remove() }

    private var importer: BrowserImporter { BrowserImporter(home: home.root) }
    private var pendingStore: PendingImportStore { PendingImportStore(directory: directory.appendingPathComponent("import-pending")) }

    private func openStore() throws -> (Store, BrowserState) {
        let store = Store(directory: directory.appendingPathComponent("org"), validate: { try $0.validate() })
        let initial = try store.load() ?? BrowserState.initial()
        try store.save(initial)
        return (store, initial)
    }

    private func snapshot(_ source: ImportSource, items: Set<ImportItem> = Set(ImportItem.allCases)) throws -> BrowserSnapshot {
        let browser = try XCTUnwrap(BrowserDetector(home: home.root, applicationDirectories: []).detect(source))
        return try importer.read(source, profile: browser.profiles[0], items: items)
    }

    // MARK: Organization

    func testFavoritesGoToTheTargetProfileAndReimportAddsNothing() throws {
        try home.addChrome()
        let (store, initial) = try openStore()
        let target = initial.profiles[0].id
        let chrome = try snapshot(.chrome)

        let plan = try BrowserImportPlan.make(chrome, items: [.favorites], into: initial, targetProfileID: target)
        XCTAssertEqual(plan.preview.favoritesToAdd, 2)
        XCTAssertNil(plan.pending)
        _ = try plan.apply(to: store, pending: pendingStore)
        let saved = try XCTUnwrap(try store.load())
        XCTAssertEqual(saved.profiles[0].favorites.map(\.title), ["Swift", "Apple"])
        XCTAssertTrue(saved.profiles[0].favorites.allSatisfy { $0.kind == .favorite && $0.savedURL == $0.lastURL })

        let again = try BrowserImportPlan.make(chrome, items: [.favorites], into: saved, targetProfileID: target)
        XCTAssertEqual(again.preview.favoritesToAdd, 0)
        XCTAssertEqual(again.preview.favoritesSkipped, 2)
        XCTAssertEqual(again.state, saved)
    }

    func testExistingFavoriteWithSameAddressIsNotDuplicated() throws {
        try home.addChrome()
        var (_, state) = try openStore()
        let target = state.profiles[0].id
        let url = URL(string: "HTTPS://Swift.org")!
        state.profiles[0].favorites.append(PageEntry(title: "Mine", savedURL: url, lastURL: url, kind: .favorite))
        let plan = try BrowserImportPlan.make(try snapshot(.chrome), items: [.favorites], into: state, targetProfileID: target)
        XCTAssertEqual(plan.preview.favoritesToAdd, 1)
        XCTAssertEqual(plan.state.profiles[0].favorites.first?.title, "Mine")
    }

    func testSaltedReimportDoesNotCollideIdentifiers() throws {
        try home.addZen()
        let (_, initial) = try openStore()
        let target = initial.profiles[0].id
        let zen = try snapshot(.zen)
        let first = try BrowserImportPlan.make(zen, items: [.spaces], into: initial, targetProfileID: target)
        let second = try BrowserImportPlan.make(zen, items: [.spaces], into: first.state, targetProfileID: target, idSalt: "again")
        XCTAssertEqual(second.state.workspaces.count, initial.workspaces.count + 4)
    }

    func testZenSpacesBecomeWorkspacesWithPinsAndFolders() throws {
        try home.addZen()
        let (store, initial) = try openStore()
        let target = initial.profiles[0].id
        let plan = try BrowserImportPlan.make(try snapshot(.zen), items: [.spaces, .favorites], into: initial, targetProfileID: target)
        XCTAssertEqual(plan.preview.spaces?.workspaces, 2)
        XCTAssertEqual(plan.preview.favoritesToAdd, 2)
        let applied = try plan.apply(to: store, pending: pendingStore)

        let work = try XCTUnwrap(applied.organization.state.workspaces.first { $0.name == "Work" })
        XCTAssertEqual(work.pins.map(\.title), ["Docs", "Inside"])
        XCTAssertEqual(work.folders.map(\.name), ["Group"])
        XCTAssertEqual(applied.organization.state.profiles.count, initial.profiles.count + 2, "one Profile per Zen container")

        let again = try BrowserImportPlan.make(try snapshot(.zen), items: [.spaces], into: applied.organization.state, targetProfileID: target)
        XCTAssertNil(again.preview.spaces)
        XCTAssertEqual(again.preview.spacesAlreadyImported, 2)
        XCTAssertEqual(again.state, applied.organization.state)
    }

    func testArcSpacesFollowExistingImportPlanAndUndoRestoresOrganization() throws {
        let sidebar = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("spikes/arc-import/fixtures/basic.json")
        try home.addArc(sidebar: sidebar)
        let (store, initial) = try openStore()
        let before = try Data(contentsOf: directory.appendingPathComponent("org/organization.json"))
        let plan = try BrowserImportPlan.make(try snapshot(.arc), items: [.spaces, .favorites], into: initial, targetProfileID: initial.profiles[0].id)
        XCTAssertEqual(plan.preview.spaces?.workspaces, 3)
        let applied = try plan.apply(to: store, pending: pendingStore)
        XCTAssertEqual(try store.load()?.workspaces.count, initial.workspaces.count + 3)
        _ = try ImportTransaction.undo(applied.organization, in: store)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("org/organization.json")), before)
    }

    func testFailedOrganizationSaveStagesNothing() throws {
        try home.addChrome()
        let (store, initial) = try openStore()
        let plan = try BrowserImportPlan.make(try snapshot(.chrome), items: [.favorites, .history], into: initial,
                                              targetProfileID: initial.profiles[0].id)
        chmod(directory.appendingPathComponent("org").path, 0o500)
        XCTAssertThrowsError(try plan.apply(to: store, pending: pendingStore))
        XCTAssertTrue(pendingStore.pending(profileKey: initial.profiles[0].id.uuidString).isEmpty)
    }

    func testUnknownTargetProfileIsRejected() throws {
        try home.addChrome()
        let (_, initial) = try openStore()
        XCTAssertThrowsError(try BrowserImportPlan.make(try snapshot(.chrome), items: [.favorites], into: initial, targetProfileID: UUID()))
    }

    // MARK: Chromium profile writer

    private func stagedChromeBatch() throws -> (PendingBrowserData, URL, URL) {
        try home.addChrome()
        let (_, initial) = try openStore()
        let plan = try BrowserImportPlan.make(try snapshot(.chrome), items: [.bookmarks, .history], into: initial,
                                              targetProfileID: initial.profiles[0].id)
        let batch = try XCTUnwrap(plan.pending)
        let root = home.root.appendingPathComponent("engine")
        let profile = root.appendingPathComponent("Default")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        return (batch, root, profile)
    }

    private func makeEngineHistory(at profile: URL, rows: [String] = []) throws {
        let database = try SQLiteDatabase.open(profile.appendingPathComponent("History"), create: true)
        for statement in FakeHome.chromiumHistorySQL.prefix(3) + rows { try database.execute(statement) }
    }

    func testPendingDataIsStagedAndAppliedToIdleProfile() throws {
        let (batch, root, profile) = try stagedChromeBatch()
        try makeEngineHistory(at: profile, rows: [FakeHome.chromiumHistorySQL[3]])
        let store = pendingStore
        try store.stage(batch, profileKey: "P1")

        let outcomes = store.applyPending(profileKey: "P1", profileDirectory: profile, userDataDirectory: root)
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].result?.bookmarksAdded, 2)
        XCTAssertEqual(outcomes[0].result?.historyAdded, 1, "swift.org already existed and keeps its own record")
        XCTAssertEqual(outcomes[0].result?.historySkippedExisting, 1)
        XCTAssertTrue(store.pending(profileKey: "P1").isEmpty)

        let database = try SQLiteDatabase.open(profile.appendingPathComponent("History"))
        XCTAssertEqual(try database.scalarInt("SELECT COUNT(*) FROM urls"), 2)
        XCTAssertEqual(try database.scalarInt("SELECT COUNT(*) FROM visits"), 1)
        XCTAssertEqual(try database.rows("SELECT transition FROM visits")[0][0].int, 0x3000_0000)

        let bookmarks = try JSONSerialization.jsonObject(with: Data(contentsOf: profile.appendingPathComponent("Bookmarks"))) as! [String: Any]
        let other = (bookmarks["roots"] as! [String: Any])["other"] as! [String: Any]
        let folder = (other["children"] as! [[String: Any]])[0]
        XCTAssertEqual(folder["name"] as? String, "Imported from Chrome")
        XCTAssertEqual((folder["meta_info"] as? [String: String])?[ChromiumProfileWriter.batchKey], batch.batchID)
        XCTAssertNil(bookmarks["checksum"])
    }

    func testApplyingTheSameBatchTwiceAddsNothing() throws {
        let (batch, root, profile) = try stagedChromeBatch()
        try makeEngineHistory(at: profile)
        let first = try ChromiumProfileWriter.apply(batch, profileDirectory: profile, userDataDirectory: root)
        let second = try ChromiumProfileWriter.apply(batch, profileDirectory: profile, userDataDirectory: root)
        XCTAssertEqual(first.historyAdded, 2)
        XCTAssertEqual(second.bookmarksAdded, 0)
        XCTAssertEqual(second.historyAdded, 0)
        XCTAssertEqual(second.historySkippedExisting, 2)
    }

    func testExistingBookmarksAreMergedWithUniqueIDsAndBackedUp() throws {
        let (batch, root, profile) = try stagedChromeBatch()
        let original = """
        {"checksum":"x","roots":{"bookmark_bar":{"id":"1","type":"folder","name":"bar","children":[{"id":"7","type":"url","name":"k","url":"https://keep.example/"}]},
        "other":{"id":"2","type":"folder","name":"o","children":[]},"synced":{"id":"3","type":"folder","name":"s","children":[]}},"version":1}
        """
        try original.write(to: profile.appendingPathComponent("Bookmarks"), atomically: true, encoding: .utf8)
        _ = try ChromiumProfileWriter.apply(batch, profileDirectory: profile, userDataDirectory: root)

        XCTAssertEqual(try String(contentsOf: profile.appendingPathComponent("Bookmarks.bato-pre-import"), encoding: .utf8), original)
        let text = try String(contentsOf: profile.appendingPathComponent("Bookmarks"), encoding: .utf8)
        XCTAssertTrue(text.contains("https://keep.example/"))
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        var ids: [String] = []
        func collect(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                if let id = dictionary["id"] as? String { ids.append(id) }
                dictionary.values.forEach(collect)
            } else if let array = value as? [Any] { array.forEach(collect) }
        }
        collect(object)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.compactMap(Int.init).filter { $0 > 7 }.count >= 4)
    }

    func testUnreadableBookmarksFileIsLeftAlone() throws {
        let (batch, root, profile) = try stagedChromeBatch()
        try "garbage".write(to: profile.appendingPathComponent("Bookmarks"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ChromiumProfileWriter.apply(batch, profileDirectory: profile, userDataDirectory: root)) {
            XCTAssertEqual($0 as? ChromiumWriteError, .unreadableBookmarks)
        }
        XCTAssertEqual(try String(contentsOf: profile.appendingPathComponent("Bookmarks"), encoding: .utf8), "garbage")
    }

    func testRunningEngineDefersAndStaleLockDoesNot() throws {
        let (batch, root, profile) = try stagedChromeBatch()
        try makeEngineHistory(at: profile)
        let lock = root.appendingPathComponent("SingletonLock")
        try FileManager.default.createSymbolicLink(atPath: lock.path, withDestinationPath: "host-\(getpid())")
        XCTAssertTrue(ChromiumProfileWriter.isInUse(userDataDirectory: root))
        XCTAssertThrowsError(try ChromiumProfileWriter.apply(batch, profileDirectory: profile, userDataDirectory: root)) {
            XCTAssertEqual($0 as? ChromiumWriteError, .engineRunning)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.appendingPathComponent("Bookmarks").path))
        let database = try SQLiteDatabase.open(profile.appendingPathComponent("History"))
        XCTAssertEqual(try database.scalarInt("SELECT COUNT(*) FROM urls"), 0)

        try FileManager.default.removeItem(at: lock)
        try FileManager.default.createSymbolicLink(atPath: lock.path, withDestinationPath: "host-999999999")
        XCTAssertFalse(ChromiumProfileWriter.isInUse(userDataDirectory: root))
    }

    func testMissingHistoryDatabaseKeepsBatchStaged() throws {
        let (batch, root, profile) = try stagedChromeBatch()
        let store = pendingStore
        try store.stage(batch, profileKey: "P1")
        let outcome = store.applyPending(profileKey: "P1", profileDirectory: profile, userDataDirectory: root)[0]
        XCTAssertEqual(outcome.result?.historyDeferred, true)
        XCTAssertEqual(outcome.result?.bookmarksAdded, 2)
        XCTAssertEqual(store.pending(profileKey: "P1").count, 1)

        try makeEngineHistory(at: profile)
        let retry = store.applyPending(profileKey: "P1", profileDirectory: profile, userDataDirectory: root)[0]
        XCTAssertEqual(retry.result?.historyAdded, 2)
        XCTAssertEqual(retry.result?.bookmarksAdded, 0)
        XCTAssertTrue(store.pending(profileKey: "P1").isEmpty)
    }

    func testUnexpectedHistorySchemaIsNotTouched() throws {
        let (batch, root, profile) = try stagedChromeBatch()
        let database = try SQLiteDatabase.open(profile.appendingPathComponent("History"), create: true)
        try database.execute("CREATE TABLE urls(id INTEGER PRIMARY KEY, url TEXT)")
        try database.execute("CREATE TABLE visits(id INTEGER PRIMARY KEY, url INTEGER)")
        let result = try ChromiumProfileWriter.apply(batch, profileDirectory: profile, userDataDirectory: root)
        XCTAssertTrue(result.historyDeferred)
        XCTAssertEqual(try database.scalarInt("SELECT COUNT(*) FROM urls"), 0)
    }

    func testLaunchProfileIsAppliedInDefaultAndWaitsForAnotherBrowserHoldingTheLock() throws {
        let (batch, root, profile) = try stagedChromeBatch()
        try makeEngineHistory(at: profile)
        let store = pendingStore
        let key = "LAUNCH"
        try store.stage(batch, profileKey: key)
        let lock = root.appendingPathComponent("SingletonLock")
        try FileManager.default.createSymbolicLink(atPath: lock.path, withDestinationPath: "host-\(getpid())")
        let blocked = store.applyBeforeEngineOpens(profileKey: key, isLaunchProfile: true, userDataDirectory: root)
        XCTAssertEqual(blocked.first?.error, .engineRunning)
        XCTAssertEqual(store.pending(profileKey: key).count, 1)

        try FileManager.default.removeItem(at: lock)
        let applied = store.applyBeforeEngineOpens(profileKey: key, isLaunchProfile: true, userDataDirectory: root)
        XCTAssertEqual(applied.first?.result?.historyAdded, 2)
        XCTAssertTrue(store.pending(profileKey: key).isEmpty)
    }

    func testOtherProfileIsAppliedInItsOwnDirectoryDespiteTheEnginesLock() throws {
        let (batch, root, _) = try stagedChromeBatch()
        let key = UUID().uuidString
        let directory = root.appendingPathComponent(key)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try makeEngineHistory(at: directory)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("SingletonLock").path,
                                                   withDestinationPath: "host-\(getpid())")
        let store = pendingStore
        try store.stage(batch, profileKey: key)
        let applied = store.applyBeforeEngineOpens(profileKey: key, isLaunchProfile: false, userDataDirectory: root)
        XCTAssertEqual(applied.first?.result?.historyAdded, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Bookmarks").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Default/Bookmarks").path))
        XCTAssertTrue(store.pending(profileKey: key).isEmpty)
    }
}
