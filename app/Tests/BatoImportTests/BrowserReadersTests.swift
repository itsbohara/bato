import CryptoKit
import Foundation
import XCTest
@testable import BatoImport

final class BrowserReadersTests: XCTestCase {
    private var home: FakeHome!
    private var importer: BrowserImporter { BrowserImporter(home: home.root) }
    private var detector: BrowserDetector { BrowserDetector(home: home.root, applicationDirectories: [home.root.appendingPathComponent("Applications")]) }

    override func setUpWithError() throws { home = try FakeHome() }
    override func tearDown() { home.remove() }

    private func profile(_ source: ImportSource, _ id: String? = nil) throws -> DetectedProfile {
        let browser = try XCTUnwrap(detector.detect(source))
        return try XCTUnwrap(browser.profiles.first { id == nil || $0.id == id })
    }

    private func sidebarFixture() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("spikes/arc-import/fixtures/basic.json")
    }

    // MARK: Detection

    func testNothingDetectedInEmptyHome() {
        XCTAssertTrue(detector.detect().isEmpty)
    }

    func testChromeProfilesComeFromLocalStateInOrder() throws {
        try home.addChrome(profiles: [("Profile 10", "Ten"), ("Default", "Person 1"), ("Profile 2", "Two")])
        let browser = try XCTUnwrap(detector.detect(.chrome))
        XCTAssertEqual(browser.profiles.map(\.id), ["Default", "Profile 2", "Profile 10"])
        XCTAssertEqual(browser.profiles.map(\.name), ["Person 1", "Two", "Ten"])
        XCTAssertEqual(browser.subtitle, "Favorites, bookmarks, history")
    }

    func testChromeProfileWithoutDirectoryIsDropped() throws {
        try home.addChrome(profiles: [("Default", "A")])
        try home.write("Library/Application Support/Google/Chrome/Local State",
                       "{\"profile\":{\"info_cache\":{\"Default\":{\"name\":\"A\"},\"Profile 1\":{\"name\":\"Gone\"}}}}")
        XCTAssertEqual(try XCTUnwrap(detector.detect(.chrome)).profiles.map(\.id), ["Default"])
    }

    func testFirefoxProfilesListDefaultFirst() throws {
        try home.addFirefox()
        let browser = try XCTUnwrap(detector.detect(.firefox))
        XCTAssertEqual(browser.profiles.map(\.name), ["default-release", "old"])
    }

    func testAppBundleAloneMakesBrowserDetected() throws {
        let apps = home.root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: apps.appendingPathComponent("Safari.app"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: apps.appendingPathComponent("Orion.app"), withIntermediateDirectories: true)
        let found = BrowserDetector(home: home.root, applicationDirectories: [apps]).detect()
        XCTAssertEqual(found.map(\.source), [.safari, .orion])
        XCTAssertEqual(found.last?.supportedItems, [])
    }

    // MARK: Chromium

    func testChromiumCountsAndRead() throws {
        try home.addChrome()
        let profile = try profile(.chrome)
        let counts = importer.counts(.chrome, profile: profile)
        XCTAssertEqual(counts[.favorites], .available(2))
        XCTAssertEqual(counts[.bookmarks], .available(2))
        XCTAssertEqual(counts[.history], .available(2))

        let snapshot = try importer.read(.chrome, profile: profile, items: Set(ImportItem.allCases))
        XCTAssertEqual(snapshot.favorites.map(\.title), ["Swift", "Apple"])
        XCTAssertEqual(snapshot.bookmarks, [
            .folder(name: "Bookmarks Bar", children: [.folder(name: "Dev", children: [
                .page(ImportedPage(title: "GitHub", url: URL(string: "https://github.com/")!))])]),
            .folder(name: "Other Bookmarks", children: [
                .page(ImportedPage(title: "Café", url: URL(string: "https://example.com/caf%C3%A9")!))]),
        ])
        XCTAssertEqual(snapshot.history.map(\.url.absoluteString), ["https://example.com/a", "https://swift.org/"])
        XCTAssertEqual(snapshot.history.last?.visitCount, 3)
        XCTAssertEqual(snapshot.history.last?.lastVisit.timeIntervalSince1970 ?? 0, 1_700_000_000, accuracy: 1)
    }

    func testReadingOnlyTheSelectedItems() throws {
        try home.addChrome()
        let snapshot = try importer.read(.chrome, profile: try profile(.chrome), items: [.history])
        XCTAssertTrue(snapshot.favorites.isEmpty)
        XCTAssertTrue(snapshot.bookmarks.isEmpty)
        XCTAssertEqual(snapshot.history.count, 2)
    }

    func testSourceFilesAreUnchangedAndNoTempCopiesRemain() throws {
        try home.addChrome()
        let directory = try profile(.chrome).directory
        func digest() throws -> [String] {
            try ["History", "Bookmarks"].map { SHA256.hash(data: try Data(contentsOf: directory.appendingPathComponent($0))).description }
        }
        let before = try digest()
        let leftovers = { (try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path))?
            .filter { $0.hasPrefix("bato-import-") }.count ?? 0 }
        let tempBefore = leftovers()
        _ = try importer.read(.chrome, profile: try profile(.chrome), items: Set(ImportItem.allCases))
        XCTAssertEqual(try digest(), before)
        XCTAssertEqual(leftovers(), tempBefore)
    }

    func testMissingHistoryAndCorruptBookmarksReportAsMissing() throws {
        try home.addChrome()
        let directory = try profile(.chrome).directory
        try FileManager.default.removeItem(at: directory.appendingPathComponent("History"))
        try "not json".write(to: directory.appendingPathComponent("Bookmarks"), atomically: true, encoding: .utf8)
        let counts = importer.counts(.chrome, profile: try profile(.chrome))
        XCTAssertEqual(counts[.history], .missing)
        XCTAssertEqual(counts[.favorites], .missing)
        XCTAssertThrowsError(try importer.read(.chrome, profile: try profile(.chrome), items: [.history]))
    }

    func testDiaIsReadAsChromiumWithANote() throws {
        try home.write("Library/Application Support/Dia/User Data/Local State", "{\"profile\":{\"info_cache\":{\"Default\":{\"name\":\"Me\"}}}}")
        try home.write("Library/Application Support/Dia/User Data/Default/Bookmarks", FakeHome.chromiumBookmarks)
        _ = try home.database("Library/Application Support/Dia/User Data/Default/History", FakeHome.chromiumHistorySQL)
        let profile = try profile(.dia)
        XCTAssertEqual(importer.counts(.dia, profile: profile)[.history], .available(2))
        XCTAssertTrue(try XCTUnwrap(detector.detect(.dia)).notes.joined().contains("no documented file format"))
    }

    // MARK: Safari

    func testSafariCountsAndRead() throws {
        try home.addSafari()
        let profile = try profile(.safari)
        let counts = importer.counts(.safari, profile: profile)
        XCTAssertEqual(counts[.favorites], .available(1))
        XCTAssertEqual(counts[.bookmarks], .available(1))
        XCTAssertEqual(counts[.history], .available(2))
        let snapshot = try importer.read(.safari, profile: profile, items: Set(ImportItem.allCases))
        XCTAssertEqual(snapshot.favorites.map(\.title), ["Apple"])
        XCTAssertEqual(snapshot.bookmarks, [.folder(name: "Favorites", children: [
            .folder(name: "Reads", children: [.page(ImportedPage(title: "News", url: URL(string: "https://news.example/")!))])])])
        XCTAssertEqual(snapshot.history.map(\.title), ["Apple", "News"])
        XCTAssertEqual(snapshot.history[0].lastVisit.timeIntervalSince1970, 1_700_000_500, accuracy: 1)
    }

    func testSafariWithoutFullDiskAccessReportsPermissionNotFailure() throws {
        try home.addSafari()
        let profile = try profile(.safari)
        for name in ["Bookmarks.plist", "History.db"] { chmod(profile.directory.appendingPathComponent(name).path, 0o000) }
        let counts = importer.counts(.safari, profile: profile)
        XCTAssertEqual(counts[.favorites], .needsFullDiskAccess)
        XCTAssertEqual(counts[.bookmarks], .needsFullDiskAccess)
        XCTAssertEqual(counts[.history], .needsFullDiskAccess)
        XCTAssertThrowsError(try importer.read(.safari, profile: profile, items: [.history])) {
            XCTAssertEqual($0 as? ImportReadError, .permissionDenied)
        }
        XCTAssertThrowsError(try importer.read(.safari, profile: profile, items: [.favorites])) {
            XCTAssertEqual($0 as? ImportReadError, .permissionDenied)
        }
    }

    func testNonSafariPermissionErrorIsNotReportedAsFullDiskAccess() throws {
        try home.addChrome()
        let profile = try profile(.chrome)
        chmod(profile.directory.appendingPathComponent("History").path, 0o000)
        XCTAssertEqual(importer.counts(.chrome, profile: profile)[.history], .missing)
    }

    // MARK: Firefox and Zen

    func testFirefoxCountsAndRead() throws {
        try home.addFirefox()
        let profile = try profile(.firefox)
        let counts = importer.counts(.firefox, profile: profile)
        XCTAssertEqual(counts[.favorites], .available(1))
        XCTAssertEqual(counts[.bookmarks], .available(1))
        XCTAssertEqual(counts[.history], .available(2))
        let snapshot = try importer.read(.firefox, profile: profile, items: Set(ImportItem.allCases))
        XCTAssertEqual(snapshot.favorites.map(\.title), ["Mozilla"])
        XCTAssertEqual(snapshot.bookmarks, [.folder(name: "Bookmarks Menu", children: [
            .folder(name: "Folder", children: [.page(ImportedPage(title: "B", url: URL(string: "https://example.com/b")!))])])])
        XCTAssertEqual(snapshot.history.first?.lastVisit.timeIntervalSince1970 ?? 0, 1_700_000_100, accuracy: 1)
    }

    func testZenWorkspacesPinsFoldersAndEssentials() throws {
        try home.addZen()
        let profile = try profile(.zen)
        let counts = importer.counts(.zen, profile: profile)
        XCTAssertEqual(counts[.spaces], .available(2))
        XCTAssertEqual(counts[.favorites], .available(2), "toolbar page plus one Essential")

        let snapshot = try importer.read(.zen, profile: profile, items: [.favorites, .spaces])
        XCTAssertEqual(snapshot.favorites.map(\.title), ["Mozilla", "Mail"])
        let staging = try XCTUnwrap(snapshot.spaces)
        XCTAssertEqual(staging.spaces.map(\.title), ["Work", "Play"])
        XCTAssertEqual(staging.profiles.map(\.key), ["zen-container-0", "zen-container-2"])
        XCTAssertTrue(staging.profiles.allSatisfy { $0.favorites.isEmpty }, "favorites travel in the snapshot, not the plan")
        guard case .page(let docs) = staging.spaces[0].pinned[0], case .folder(let group) = staging.spaces[0].pinned[1] else {
            return XCTFail("expected a page then a folder")
        }
        XCTAssertEqual(docs.title, "Docs")
        XCTAssertEqual(group.children.count, 1)
        XCTAssertEqual(staging.spaces[0].pinned.count, 2, "about: pins and Essentials are not Space pins")
    }

    func testZenWithoutWorkspaceTablesHasNoSpaces() throws {
        try home.addFirefox()
        try FileManager.default.moveItem(at: home.support.appendingPathComponent("Firefox"), to: home.support.appendingPathComponent("zen"))
        let profile = try profile(.zen)
        XCTAssertEqual(importer.counts(.zen, profile: profile)[.spaces], .available(0))
    }

    // MARK: Arc

    func testArcSpacesFavoritesAndHistory() throws {
        try home.addArc(sidebar: sidebarFixture())
        let profile = try profile(.arc)
        let counts = importer.counts(.arc, profile: profile)
        XCTAssertEqual(counts[.spaces], .available(3))
        XCTAssertEqual(counts[.history], .available(2))
        guard case .available(let favorites) = counts[.favorites] else { return XCTFail("favorites unavailable") }
        XCTAssertGreaterThan(favorites, 0)

        let snapshot = try importer.read(.arc, profile: profile, items: Set(ImportItem.allCases))
        XCTAssertEqual(snapshot.favorites.count, favorites)
        XCTAssertEqual(snapshot.spaces?.spaces.count, 3)
        XCTAssertTrue(snapshot.bookmarks.isEmpty, "Arc keeps no Chromium bookmarks")
    }

    // MARK: Bookmarks HTML (Orion route)

    func testBookmarksHTMLExport() throws {
        let file = try home.write("export.html", """
        <!DOCTYPE NETSCAPE-Bookmark-file-1><DL><p>
        <DT><H3 PERSONAL_TOOLBAR_FOLDER="true">Bar</H3><DL><p>
          <DT><A HREF="https://orion.example/?a=1&amp;b=2">Orion &amp; Co</A>
          <DT><H3>Nested</H3><DL><p><DT><A HREF="https://nested.example/">Nested</A></DL><p>
        </DL><p>
        <DT><H3>Reading</H3><DL><p><DT><A HREF="https://r.example/">R</A><DT><A HREF="javascript:void(0)">JS</A></DL><p>
        </DL>
        """)
        let snapshot = try importer.readBookmarksHTML(file, source: .orion)
        XCTAssertEqual(snapshot.favorites, [ImportedPage(title: "Orion & Co", url: URL(string: "https://orion.example/?a=1&b=2")!)])
        XCTAssertEqual(snapshot.bookmarkCount, 2)
        XCTAssertEqual(snapshot.bookmarks.count, 2)
    }
}
