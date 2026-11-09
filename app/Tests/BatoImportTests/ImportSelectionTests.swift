import Foundation
import XCTest
@testable import BatoImport

final class ImportSelectionTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    func testRowsFollowCountsAndAreOnlyOnWhenThereIsSomethingToBring() {
        let selection = ImportSelection(source: .chrome, counts: [
            .history: .available(2019), .favorites: .available(48), .bookmarks: .available(0),
        ], locale: english)
        XCTAssertEqual(selection.rows.map(\.title), ["Favorites", "Bookmarks", "History"])
        XCTAssertEqual(selection.rows.map(\.detail), ["48 sites", "0 sites", "2,019 pages"])
        XCTAssertEqual(selection.selectedItems, [.favorites, .history])
        XCTAssertTrue(selection.canContinue)
    }

    func testEmptyRowCannotBeToggledOn() {
        var selection = ImportSelection(source: .chrome, counts: [.bookmarks: .available(0), .history: .available(3)], locale: english)
        selection.toggle(.bookmarks)
        XCTAssertEqual(selection.selectedItems, [.history])
        selection.toggle(.history)
        XCTAssertFalse(selection.canContinue)
        XCTAssertEqual(selection.access, .ready)
    }

    func testSpacesRowAppearsWhenSupported() {
        let selection = ImportSelection(source: .arc, counts: [.spaces: .available(3), .favorites: .available(1)], locale: english)
        XCTAssertEqual(selection.rows.map(\.detail), ["1 site", "3 spaces"])
    }

    func testBlockedSafariAsksForFullDiskAccess() {
        let selection = ImportSelection(source: .safari, counts: [.favorites: .needsFullDiskAccess, .history: .needsFullDiskAccess])
        XCTAssertEqual(selection.access, .needsFullDiskAccess)
        XCTAssertTrue(selection.selectedItems.isEmpty)
        XCTAssertFalse(selection.canContinue)
    }

    func testNothingFoundReportsNothingToImport() {
        let selection = ImportSelection(source: .firefox, counts: [.history: .missing])
        XCTAssertEqual(selection.access, .nothingToImport)
        XCTAssertFalse(selection.canContinue)
    }

    func testCountsFromSyntheticChromeProfile() throws {
        let home = try FakeHome()
        defer { home.remove() }
        try home.addChrome()
        let detected = BrowserDetector(home: home.root, applicationDirectories: []).detect()
        let chrome = try XCTUnwrap(detected.first { $0.source == .chrome })
        let counts = BrowserImporter(home: home.root).counts(.chrome, profile: chrome.profiles[0])
        let selection = ImportSelection(source: .chrome, counts: counts, locale: english)
        XCTAssertTrue(selection.canContinue)
        XCTAssertEqual(selection.rows.first?.title, "Favorites")
    }

    func testBrowserChoicesMarkTheDefaultAndListOnlyDetected() throws {
        let home = try FakeHome()
        defer { home.remove() }
        try home.addChrome()
        try home.addFirefox()
        let detected = BrowserDetector(home: home.root, applicationDirectories: []).detect()
        let choices = BrowserChoice.choices(from: detected, defaultSource: .firefox)
        XCTAssertEqual(Set(choices.map(\.source)), [.chrome, .firefox])
        XCTAssertEqual(choices.filter(\.isCurrentDefault).map(\.name), ["Firefox"])
        XCTAssertTrue(BrowserChoice.choices(from: [], defaultSource: nil).isEmpty)
    }

    func testBundleIdentifiersMapToSources() {
        XCTAssertEqual(ImportSource(bundleIdentifier: "com.apple.Safari"), .safari)
        XCTAssertEqual(ImportSource(bundleIdentifier: "company.thebrowser.Browser"), .arc)
        XCTAssertNil(ImportSource(bundleIdentifier: "com.example.Other"))
    }
}
