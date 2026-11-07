import Foundation
import XCTest
@testable import BatoCore

final class SettingsModelTests: XCTestCase {
    func testPanesAreUniqueAndLabelled() {
        XCTAssertEqual(Set(SettingsPane.allCases.map(\.title)).count, SettingsPane.allCases.count)
        XCTAssertTrue(SettingsPane.allCases.allSatisfy { !$0.symbolName.isEmpty })
    }

    func testProfileRowsMarkCurrentProfileAndCountWorkspaces() throws {
        var state = BrowserState.initial()
        let first = state.currentWorkspace.profileID
        _ = try state.addWorkspace(name: "Extra", profileID: first)
        let second = try state.addProfile(name: "Second")
        _ = try state.addWorkspace(name: "Second space", profileID: second)
        let rows = SettingsProfileRow.rows(from: state)
        XCTAssertEqual(rows.map(\.id), state.profiles.map(\.id))
        XCTAssertEqual(rows.filter(\.isCurrent).map(\.id), [first])
        XCTAssertEqual(rows.first { $0.id == first }?.workspaceCount, 2)
        XCTAssertEqual(rows.first { $0.id == first }?.detail, "Current · 2 workspaces")
        XCTAssertEqual(rows.first { $0.id == second }?.detail, "1 workspace")
        XCTAssertTrue(rows.allSatisfy { $0.colorHex.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil })
    }

    func testShortcutCatalogHasNoDuplicateChords() {
        let keys = ShortcutCatalog.rows.map(\.keys)
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertTrue(ShortcutCatalog.rows.contains(ShortcutRow(title: "History", keys: "⌘Y")))
        XCTAssertTrue(ShortcutCatalog.rows.contains(ShortcutRow(title: "Downloads", keys: "⇧⌘J")))
    }

    func testAboutVersionPrefersBundleThenVersionFileThenDevelopment() {
        XCTAssertEqual(AboutInfo(bundleVersion: "0.2.0", bundleBuild: "170", versionFileText: "0.1.0\n").displayVersion, "0.2.0 (170)")
        XCTAssertEqual(AboutInfo(bundleVersion: " ", bundleBuild: nil, versionFileText: "0.1.0\n").displayVersion, "0.1.0")
        XCTAssertEqual(AboutInfo(bundleVersion: nil, bundleBuild: nil, versionFileText: nil).displayVersion, "development")
    }

    func testSettingsPanesIncludeGeneralAndAbout() {
        XCTAssertEqual(SettingsPane.allCases.first, .general)
        XCTAssertEqual(SettingsPane.allCases.last, .about)
    }
}
