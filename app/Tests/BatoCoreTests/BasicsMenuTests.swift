import Foundation
import XCTest
@testable import BatoCore

final class BasicsMenuTests: XCTestCase {
    private let url = URL(string: "https://example.com/a?b=1")!

    func testWorkspaceShortcutRowIsNotLabelledAsProfile() {
        let row = ShortcutCatalog.rows.first { $0.keys == "⌃1–9" }
        XCTAssertEqual(row?.title, "Switch workspace")
    }

    func testPlainURLFormatIsTheAddress() {
        XCTAssertEqual(LinkFormat.url.text(title: "Example", url: url), "https://example.com/a?b=1")
    }

    func testMarkdownFormatEscapesBracketsAndFallsBackToTheAddress() {
        XCTAssertEqual(LinkFormat.markdown.text(title: "A [b] c", url: url), "[A \\[b\\] c](https://example.com/a?b=1)")
        XCTAssertEqual(LinkFormat.markdown.text(title: "  ", url: url), "[https://example.com/a?b=1](https://example.com/a?b=1)")
    }

    func testSpaceEntriesFollowSwitcherOrderAndMarkTheActiveSpace() throws {
        var state = BrowserState.initial()
        let first = state.activeWorkspaceID
        let second = try state.addWorkspace(name: "Second", profileID: state.currentWorkspace.profileID)
        let entries = state.spaceMenuEntries
        XCTAssertEqual(entries.map(\.id), state.switcherWorkspaceIDs)
        XCTAssertEqual(entries.map(\.shortcut), [1, 2])
        XCTAssertEqual(entries.first { $0.isActive }?.id, first)
        XCTAssertEqual(entries.last?.id, second)
    }

    func testOnlyTheFirstNineSpacesGetShortcuts() throws {
        var state = BrowserState.initial()
        for index in 0..<10 { try state.addWorkspace(name: "W\(index)", profileID: state.currentWorkspace.profileID) }
        let shortcuts = state.spaceMenuEntries.map(\.shortcut)
        XCTAssertEqual(shortcuts.prefix(9).compactMap { $0 }, Array(1...9))
        XCTAssertNil(shortcuts[9])
    }

    func testChromiumMenuPolicyHidesOnlyUnusedFeatures() {
        XCTAssertTrue(ChromiumMenuPolicy.hidesMenu(titled: "Bookmarks"))
        XCTAssertTrue(ChromiumMenuPolicy.hidesMenu(titled: "Profiles"))
        XCTAssertFalse(ChromiumMenuPolicy.hidesMenu(titled: "History"))
        XCTAssertTrue(ChromiumMenuPolicy.hidesItem(titled: "Show Tabs Vertically"))
        XCTAssertFalse(ChromiumMenuPolicy.hidesItem(titled: "Zoom In"))
    }
}
