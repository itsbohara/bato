import Foundation
import XCTest
@testable import BatoCore

final class EssentialsTests: XCTestCase {
    func testEssentialsAreExactChromiumPagesOnly() {
        for essential in BrowserEssential.allCases {
            XCTAssertTrue(BrowserEssential.accepts(essential.url))
            XCTAssertEqual(BrowserEssential.matching(essential.url), essential)
        }
        XCTAssertTrue(BrowserEssential.accepts(URL(string: "chrome://history")!))
        for rejected in ["chrome://flags/", "chrome://history/?q=a", "chrome://history/#x", "chrome://history/search",
                         "chrome://user@history/", "chrome-untrusted://history/", "about:blank", "javascript:alert(1)",
                         "file:///etc/passwd", "https://history/"] {
            XCTAssertFalse(BrowserEssential.accepts(URL(string: rejected)!), rejected)
            XCTAssertNil(BrowserEssential.matching(URL(string: rejected)!), rejected)
        }
    }

    func testStateSavesEssentialTabsButStillRefusesOtherSchemes() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: BrowserEssential.history.url, title: "History")
        XCTAssertEqual(state.openEssentialEntry(.history)?.id, id)
        XCTAssertNil(state.openEssentialEntry(.downloads))
        XCTAssertThrowsError(try state.addTab(url: URL(string: "chrome://flags/")!, title: "Flags")) {
            XCTAssertEqual($0 as? BrowserStateError, .invalidURL)
        }
        try state.validate()
    }

    func testEssentialLookupIsLimitedToTheCurrentWorkspaceProfile() throws {
        var state = BrowserState.initial()
        let first = state.activeWorkspaceID
        try state.addTab(url: BrowserEssential.downloads.url, title: "Downloads")
        let profile = try state.addProfile(name: "Second")
        let second = try state.addWorkspace(name: "Second space", profileID: profile)
        try state.activateWorkspace(second)
        XCTAssertNil(state.openEssentialEntry(.downloads))
        try state.activateWorkspace(first)
        XCTAssertNotNil(state.openEssentialEntry(.downloads))
    }

    func testRoundTripsThroughCodable() throws {
        var state = BrowserState.initial()
        try state.addTab(url: BrowserEssential.chromiumSettings.url, title: "Browser Settings")
        let decoded = try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state)
    }
}

final class FaviconFallbackTests: XCTestCase {
    func testIPHostUsesTitleLetterAndHueVariesByURL() {
        let a = FaviconFallback.spec(title: "Alpha", url: URL(string: "http://127.0.0.1:18765/a")!)
        let b = FaviconFallback.spec(title: "Beta", url: URL(string: "http://127.0.0.1:18765/b")!)
        XCTAssertEqual(a.letter, "A")
        XCTAssertEqual(b.letter, "B")
        XCTAssertNotEqual(a.hue, b.hue)
    }

    func testNamedHostUsesHostLetter() {
        XCTAssertEqual(FaviconFallback.spec(title: "Docs", url: URL(string: "https://www.example.test/docs")!).letter, "E")
    }
}
