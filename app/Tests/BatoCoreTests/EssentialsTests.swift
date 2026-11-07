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

    func testSiteSettingsSubtreeIsAcceptedButNothingElseUnderSettings() {
        for accepted in ["chrome://settings/content", "chrome://settings/content/all", "chrome://settings/content/notifications",
                         "chrome://settings/content/siteDetails?site=http%3A%2F%2F127.0.0.1%3A18765",
                         "chrome://settings/content/siteDetails?site=https%3A%2F%2Fexample.test"] {
            XCTAssertTrue(BrowserEssential.accepts(URL(string: accepted)!), accepted)
            XCTAssertEqual(BrowserEssential.matching(URL(string: accepted)!), .sitePermissions, accepted)
        }
        XCTAssertEqual(BrowserEssential.matching(URL(string: "chrome://settings/")!), .chromiumSettings)
        for rejected in ["chrome://settings/privacy", "chrome://settings/content/../passwords", "chrome://settings/content/a.b",
                         "chrome://settings/content?site=http%3A%2F%2Fa.test", "chrome://settings/content/siteDetails?site=javascript%3Aalert(1)",
                         "chrome://settings/content/siteDetails?site=http%3A%2F%2Fa.test%2Fpath",
                         "chrome://settings/content/siteDetails?site=http%3A%2F%2Fa.test&x=1", "chrome://settings/content#location",
                         "chrome://history/content", "chrome://downloads/content/all"] {
            XCTAssertFalse(BrowserEssential.accepts(URL(string: rejected)!), rejected)
        }
    }

    func testSiteSettingsURLTargetsThePageOriginOrTheList() {
        XCTAssertEqual(BrowserEssential.siteSettingsURL(for: URL(string: "http://127.0.0.1:18765/permissions.html?x=1")!).absoluteString,
                       "chrome://settings/content/siteDetails?site=http%3A%2F%2F127.0.0.1%3A18765")
        XCTAssertEqual(BrowserEssential.siteSettingsURL(for: URL(string: "https://example.test/a")!).absoluteString,
                       "chrome://settings/content/siteDetails?site=https%3A%2F%2Fexample.test")
        for page in [nil, URL(string: "chrome://history/"), URL(string: "file:///tmp/a.html")] {
            XCTAssertEqual(BrowserEssential.siteSettingsURL(for: page), BrowserEssential.sitePermissions.url)
        }
        XCTAssertTrue(BrowserEssential.accepts(BrowserEssential.siteSettingsURL(for: URL(string: "http://localhost:8080/")!)))
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
