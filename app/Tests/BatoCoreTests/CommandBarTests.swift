import Foundation
import XCTest
@testable import BatoCore

final class CommandBarTests: XCTestCase {
    func testAddressesHaveHTTPOnlyAndPreservePathQueryAndFragment() {
        for (text, expected) in [
            ("  example.invalid/path?q=1#section\n", "https://example.invalid/path?q=1#section"),
            ("localhost:18765/modal.html", "https://localhost:18765/modal.html"),
            ("http://127.0.0.1:18765/", "http://127.0.0.1:18765/"),
            ("[::1]:18765/path", "https://[::1]:18765/path"),
            ("https://example.invalid/", "https://example.invalid/")
        ] {
            XCTAssertEqual(CommandBarInput.resolve(text), .navigate(URL(string: expected)!))
        }
        XCTAssertEqual(CommandBarInput.resolve(" \n "), .empty)
    }

    func testTextSearchEncodesQueryAsOneValue() throws {
        let text = "café + tea & q=other #☕"
        guard case .search(let url) = CommandBarInput.resolve(text) else { return XCTFail("Expected search") }
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.host, "duckduckgo.com")
        XCTAssertEqual(parts.queryItems, [URLQueryItem(name: "q", value: text)])
        XCTAssertNil(parts.fragment)
        guard case .search = CommandBarInput.resolve("what is example.invalid") else { return XCTFail("Sentence must search") }
    }

    func testSearchPreservesLiteralPlusThroughFormDecoding() throws {
        let text = "café + tea & q=other #☕"
        for provider in CommandBarSearchProvider.allCases {
            guard case .search(let url) = CommandBarInput.resolve(text, provider: provider) else {
                return XCTFail("Expected search")
            }
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let query = try XCTUnwrap(components.percentEncodedQuery)
            XCTAssertEqual(query, "q=caf%C3%A9%20%2B%20tea%20%26%20q%3Dother%20%23%E2%98%95")
            // Reproduce application/x-www-form-urlencoded server semantics,
            // instead of URLComponents' RFC 3986-only queryItems roundtrip.
            let pairs = query.split(separator: "&")
            XCTAssertEqual(pairs.count, 1)
            let value = try XCTUnwrap(pairs.first?.split(separator: "=", maxSplits: 1).last)
            let decoded = String(value).replacingOccurrences(of: "+", with: " ").removingPercentEncoding
            XCTAssertEqual(decoded, text)
        }
    }

    func testProviderSelectionChangesOnlySearchDestination() throws {
        for provider in CommandBarSearchProvider.allCases {
            guard case .search(let url) = CommandBarInput.resolve("a & b", provider: provider) else {
                return XCTFail("Expected search")
            }
            let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(parts.host, provider.endpoint.host)
            XCTAssertEqual(parts.path, provider.endpoint.path)
            XCTAssertEqual(parts.queryItems, [URLQueryItem(name: "q", value: "a & b")])
            XCTAssertEqual(CommandBarInput.resolve("example.invalid", provider: provider),
                           .navigate(URL(string: "https://example.invalid")!))
            XCTAssertTrue(CommandBarResults.make(query: "a & b", state: .initial(), provider: provider)[0].title.contains(provider.title))
        }
    }

    func testUnsafeSchemesCredentialsAndMalformedAddressesAreRejected() {
        for text in ["javascript:alert(1)", "file:///tmp/example", "data:text/html,hello", "mailto:a@example.invalid",
                     "https://user:pass@example.invalid/", "user@example.invalid/path", "http:///missing", "https://",
                     "https://example.invalid:70000/", "https://example.invalid:abc/", "https://example.invalid/a b",
                     "https://example..invalid/", "https://example.invalid\\@other.invalid/", "hello\nworld"] {
            guard case .invalid = CommandBarInput.resolve(text) else { XCTFail("Must reject \(text)"); continue }
        }
    }

    func testResultsStayWithinProfileAndKeepStableIdentity() throws {
        var state = BrowserState.initial()
        let first = state.activeWorkspaceID
        let page = try state.addTab(url: URL(string: "https://example.invalid/")!, title: "Café notes")
        let second = try state.addWorkspace(name: "Research", profileID: state.currentWorkspace.profileID)
        try state.activateWorkspace(second)
        let foreignProfile = try state.addProfile(name: "Other")
        let foreign = try state.addWorkspace(name: "Foreign", profileID: foreignProfile)
        try state.activateWorkspace(foreign)
        _ = try state.addTab(url: URL(string: "https://foreign.invalid/")!, title: "Café secret")
        try state.activateWorkspace(second)
        let before = state
        let results = CommandBarResults.make(query: "cafe", state: state)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[1].id, "page:\(page.uuidString)")
        guard case .activate(let result) = results[1].action else { return XCTFail("Expected page activation") }
        XCTAssertEqual(result.workspaceID, first)
        XCTAssertEqual(result.entryID, page)
        XCTAssertEqual(CommandBarResults.make(query: "Café", state: state)[1].id, results[1].id)
        XCTAssertEqual(state, before)
    }

    func testCommandsAppearForEmptyAndMatchingQueries() {
        let state = BrowserState.initial()
        XCTAssertEqual(CommandBarResults.make(query: "", state: state).map(\.action),
                       CommandBarCommand.allCases.map(CommandBarAction.command))
        let matches = CommandBarResults.make(query: "sidebar", state: state)
        XCTAssertEqual(matches.last?.action, .command(.toggleSidebar))
        XCTAssertTrue(CommandBarResults.make(query: "javascript:alert(1)", state: state).isEmpty)
    }
}

final class CurrentPageNavigationTests: XCTestCase {
    private let page = URL(string: "https://example.invalid/page")!

    func testNavigatingBarOffersNoNewTabOrPeek() {
        let results = CommandBarResults.make(query: page.absoluteString, state: BrowserState.initial(), navigatingCurrentPage: true)
        XCTAssertEqual(results.first?.action, .navigateCurrent(page))
        for result in results {
            if case .open = result.action { XCTFail("Unexpected new-tab result") }
            if case .peek = result.action { XCTFail("Unexpected Peek result") }
        }
    }

    func testSearchesNavigateTheCurrentPageToo() {
        let results = CommandBarResults.make(query: "swift testing", state: BrowserState.initial(), navigatingCurrentPage: true)
        guard case .navigateCurrent(let url)? = results.first?.action else { return XCTFail("Expected a current-page search") }
        XCTAssertEqual(url.host, "duckduckgo.com")
    }

    func testDefaultBarStillOpensTabsAndPeek() {
        let results = CommandBarResults.make(query: page.absoluteString, state: BrowserState.initial())
        XCTAssertEqual(Array(results.map(\.action).prefix(2)), [.open(page), .peek(page)])
    }

    func testExactCommandNameOutranksWebSearch() {
        let state = BrowserState.initial()
        let results = CommandBarResults.make(query: "history", state: state)
        XCTAssertEqual(results.first?.action, .command(.openHistory))
        XCTAssertEqual(results.filter { $0.id == "command:openHistory" }.count, 1)
        XCTAssertEqual(results[1].id, "destination")
    }

    func testTypingMovesSelectionToTopRowButArrowChoiceSurvivesRefreshOfSameQuery() {
        let state = BrowserState.initial()
        let first = CommandBarResults.make(query: "h", state: state)
        let history = CommandBarResults.make(query: "history", state: state)
        XCTAssertEqual(CommandBarSelection.rowAfterRefresh(previousID: first.last?.id, previousQuery: "h", query: "history", results: history), 0)
        let kept = history[1].id
        XCTAssertEqual(CommandBarSelection.rowAfterRefresh(previousID: kept, previousQuery: "history", query: "history", results: history), 1)
        XCTAssertNil(CommandBarSelection.rowAfterRefresh(previousID: nil, previousQuery: "", query: "", results: []))
    }
}
