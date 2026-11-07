import Foundation
import Testing
@testable import BatoBlocking

struct BlockingSettingsTests {
    @Test func defaultsAreEnabledWithoutExceptions() {
        let settings = BlockingSettings()
        #expect(settings.enabled)
        #expect(settings.exceptions.isEmpty)
    }

    @Test func hostNormalizationAcceptsOnlyPlainAsciiHosts() {
        #expect(BlockingSettings.normalizedHost(" Example.COM. ") == "example.com")
        #expect(BlockingSettings.normalizedHost("localhost") == "localhost")
        for bad in ["", ".", "a..b", ".a.b", "a b", "https://a.b", "a.b/path", "a.b:80", "bücher.de", "*.a.b", "[::1]"] {
            #expect(BlockingSettings.normalizedHost(bad) == nil, "\(bad)")
        }
    }

    @Test func exceptionCoversSubdomainsOnLabelBoundariesOnly() throws {
        var settings = BlockingSettings()
        try settings.addException("example.com")
        #expect(settings.exception(covering: "example.com") == "example.com")
        #expect(settings.exception(covering: "www.example.com") == "example.com")
        #expect(settings.exception(covering: "a.b.example.com") == "example.com")
        #expect(settings.exception(covering: "notexample.com") == nil)
        #expect(settings.exception(covering: "example.com.evil.test") == nil)
        #expect(!settings.blocks(pageHost: "www.example.com"))
        #expect(settings.blocks(pageHost: "other.org"))
    }

    @Test func subdomainExceptionDoesNotCoverParentOrSiblings() throws {
        var settings = BlockingSettings()
        try settings.addException("shop.example.com")
        #expect(settings.blocks(pageHost: "example.com"))
        #expect(settings.blocks(pageHost: "www.example.com"))
        #expect(!settings.blocks(pageHost: "shop.example.com"))
    }

    @Test func globalSwitchOffBlocksNothing() {
        var settings = BlockingSettings()
        settings.enabled = false
        #expect(!settings.blocks(pageHost: "example.com"))
    }

    @Test func addIsIdempotentSortedAndRejectsInvalid() throws {
        var settings = BlockingSettings()
        try settings.addException("b.com")
        try settings.addException("A.com")
        try settings.addException("b.com")
        #expect(settings.exceptions == ["a.com", "b.com"])
        #expect(throws: BlockingSettingsError.invalidHost) { try settings.addException("bad host") }
        settings.removeException("A.COM")
        settings.removeException("missing.com")
        #expect(settings.exceptions == ["b.com"])
    }

    @Test func pageHostComesOnlyFromHttpUrls() {
        #expect(BlockingSettings.host(of: URL(string: "https://WWW.Example.com/x")!) == "www.example.com")
        #expect(BlockingSettings.host(of: URL(string: "about:blank")!) == nil)
        #expect(BlockingSettings.host(of: URL(string: "file:///tmp/a")!) == nil)
    }

    @Test func decodingRejectsUnsupportedVersionAndInvalidHosts() {
        let decoder = JSONDecoder()
        #expect(throws: (any Error).self) {
            try decoder.decode(BlockingSettings.self, from: Data(#"{"version":2,"enabled":true,"exceptions":[]}"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try decoder.decode(BlockingSettings.self, from: Data(#"{"version":1,"enabled":true,"exceptions":["a b"]}"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try decoder.decode(BlockingSettings.self, from: Data(#"{"version":1,"exceptions":[]}"#.utf8))
        }
    }
}
