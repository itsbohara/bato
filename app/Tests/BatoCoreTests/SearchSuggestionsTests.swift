import Foundation
import XCTest
@testable import BatoCore

final class SearchSuggestionsTests: XCTestCase {
    func testParsesOpenSearchShape() {
        let data = Data(#"["hello",["hello world","Hello World","hello kitty"," "],{"google:suggestsubtypes":[]}]"#.utf8)
        XCTAssertEqual(SearchSuggestions.parse(data), ["hello world", "hello kitty"])
    }

    func testParsesDuckDuckGoPhrases() {
        let data = Data(#"[{"phrase":"hello"},{"phrase":"hello world"},{"other":1}]"#.utf8)
        XCTAssertEqual(SearchSuggestions.parse(data), ["hello", "hello world"])
    }

    func testMalformedOrUnexpectedPayloadsGiveNothing() {
        for text in ["", "not json", "{}", "[]", #"["q"]"#, #"["q",{"a":1}]"#, "[1,2]"] {
            XCTAssertEqual(SearchSuggestions.parse(Data(text.utf8)), [], text)
        }
    }

    func testEndpointsPerProvider() throws {
        let expected: [CommandBarSearchProvider: String] = [
            .duckDuckGo: "https://duckduckgo.com/ac/?q=a%20%2B%20b",
            .google: "https://suggestqueries.google.com/complete/search?client=firefox&q=a%20%2B%20b",
            .brave: "https://search.brave.com/api/suggest?q=a%20%2B%20b",
            .bing: "https://api.bing.com/osjson.aspx?query=a%20%2B%20b"
        ]
        for provider in CommandBarSearchProvider.allCases {
            XCTAssertEqual(SearchSuggestions.endpoint(for: " a + b ", provider: provider)?.absoluteString, expected[provider])
        }
    }

    func testAddressesEmptyAndLongInputAreNeverSent() {
        for text in ["", "  ", "example.com/path", "https://example.com", "localhost:3000", "ftp://x",
                     String(repeating: "a", count: SearchSuggestions.maxQueryLength + 1)] {
            XCTAssertNil(SearchSuggestions.endpoint(for: text, provider: .duckDuckGo), text)
        }
    }

    // MARK: Row assembly

    private func state(tabs: [String]) -> BrowserState {
        var state = BrowserState.initial()
        for (index, title) in tabs.enumerated() {
            state.workspaces[0].tabs.append(PageEntry(title: title, lastURL: URL(string: "https://example.test/\(index)")!, kind: .temporary))
        }
        return state
    }

    func testQueryRowsAreSearchThenTabsThenSuggestions() {
        let rows = CommandBarResults.make(query: "hello", state: state(tabs: ["hello docs"]), suggestions: ["hello world", "hello kitty"])
        XCTAssertEqual(rows.map(\.title), ["Search DuckDuckGo for “hello”", "hello docs", "hello world", "hello kitty"])
        XCTAssertEqual(rows.map(\.isSearch), [true, false, true, true])
        guard case .open(let url) = rows[2].action else { return XCTFail("Suggestion should open a search") }
        XCTAssertEqual(url.absoluteString, "https://duckduckgo.com/?q=hello%20world")
    }

    func testSuggestionEqualToTheQueryIsDropped() {
        let rows = CommandBarResults.make(query: "Hello", state: .initial(), suggestions: ["hello", "hello again"])
        XCTAssertEqual(rows.filter { $0.subtitle == CommandBarResult.suggestionSubtitle }.map(\.title), ["hello again"])
    }

    func testSuggestionsNavigateTheCurrentPageWhenAsked() {
        let rows = CommandBarResults.make(query: "hi", state: .initial(), navigatingCurrentPage: true, suggestions: ["hi there"])
        guard case .navigateCurrent = rows[1].action else { return XCTFail("Expected navigateCurrent") }
    }

    func testQueryRowsAreCappedAndTabsKeepRoomForSuggestions() {
        let many = (0..<10).map { "match \($0)" }
        let rows = CommandBarResults.make(query: "match", state: state(tabs: many), suggestions: (0..<6).map { "match s\($0)" })
        XCTAssertEqual(rows.count, CommandBarResults.queryRowLimit)
        XCTAssertEqual(rows.filter { $0.subtitle == CommandBarResult.suggestionSubtitle }.count, 3)
    }

    func testWithoutSuggestionsRowsAreJustSearchAndTabs() {
        let offline = CommandBarResults.make(query: "hello", state: state(tabs: ["hello docs"]))
        XCTAssertEqual(offline.map(\.title), ["Search DuckDuckGo for “hello”", "hello docs"])
    }

    func testEmptyQueryIsNotCapped() {
        let rows = CommandBarResults.make(query: "", state: state(tabs: (0..<12).map { "tab \($0)" }))
        XCTAssertGreaterThan(rows.count, CommandBarResults.queryRowLimit)
    }
}

@MainActor
final class SearchSuggestionFetcherTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        func add(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
        var all: [URL] { lock.lock(); defer { lock.unlock() }; return urls }
    }

    private nonisolated static func payload(_ words: [String]) -> Data {
        Data(("[\"q\",[" + words.map { "\"\($0)\"" }.joined(separator: ",") + "]]").utf8)
    }

    func testOnlyTheLastQueryInABurstIsFetchedAndDelivered() async throws {
        let recorder = Recorder()
        let fetcher = SearchSuggestionFetcher(delay: .milliseconds(60)) { url in
            recorder.add(url)
            return Self.payload(["final"])
        }
        let delivered = expectation(description: "delivered")
        var results: [(String, [String])] = []
        for query in ["h", "he", "hel"] {
            fetcher.request(query: query, provider: .duckDuckGo) { q, found in
                results.append((q, found))
                delivered.fulfill()
            }
        }
        await fulfillment(of: [delivered], timeout: 2)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(recorder.all.count, 1)
        XCTAssertEqual(recorder.all.first?.query, "q=hel")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.0, "hel")
    }

    func testCancelledRequestNeverDeliversEvenWhenTheFetchFinishes() async throws {
        let fetcher = SearchSuggestionFetcher(delay: .milliseconds(10)) { _ in
            try await Task.sleep(for: .milliseconds(100))
            return Self.payload(["late"])
        }
        var count = 0
        fetcher.request(query: "hello", provider: .google) { _, _ in count += 1 }
        try await Task.sleep(for: .milliseconds(50))
        fetcher.cancel()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(count, 0)
    }

    func testSlowOlderResponseIsDroppedWhenANewerQueryArrives() async throws {
        let fetcher = SearchSuggestionFetcher(delay: .milliseconds(5)) { url in
            if url.query?.contains("old") == true {
                try await Task.sleep(for: .milliseconds(150))
                return Self.payload(["old result"])
            }
            return Self.payload(["new result"])
        }
        var delivered: [String] = []
        let done = expectation(description: "new delivered")
        fetcher.request(query: "old", provider: .duckDuckGo) { _, found in delivered += found }
        try await Task.sleep(for: .milliseconds(40))
        fetcher.request(query: "new", provider: .duckDuckGo) { _, found in delivered += found; done.fulfill() }
        await fulfillment(of: [done], timeout: 2)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(delivered, ["new result"])
    }

    func testFailureAndAddressInputDeliverNothing() async throws {
        struct Offline: Error {}
        let fetcher = SearchSuggestionFetcher(delay: .milliseconds(5)) { _ in throw Offline() }
        var count = 0
        fetcher.request(query: "hello", provider: .duckDuckGo) { _, _ in count += 1 }
        fetcher.request(query: "example.com", provider: .duckDuckGo) { _, _ in count += 1 }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(count, 0)
    }
}
