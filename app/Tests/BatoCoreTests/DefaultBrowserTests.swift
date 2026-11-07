import Foundation
import XCTest
@testable import BatoCore

private final class Registrations: @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [String: URL]
    private(set) var assigned: [String] = []
    var failing: Set<String> = []

    init(handlers: [String: URL]) { self.handlers = handlers }

    func handler(_ scheme: String) -> URL? { lock.withLock { handlers[scheme] } }

    func assign(_ scheme: String, to app: URL) throws {
        try lock.withLock {
            if failing.contains(scheme) { throw CocoaError(.userCancelled) }
            assigned.append(scheme)
            handlers[scheme] = app
        }
    }
}

final class DefaultBrowserTests: XCTestCase {
    private let bato = URL(fileURLWithPath: "/Applications/Bato.app")
    private let other = URL(fileURLWithPath: "/Applications/Safari.app")

    private func browser(_ registrations: Registrations) -> DefaultBrowser {
        let app = bato
        return DefaultBrowser(appURL: app, handler: { registrations.handler($0) },
                              assign: { try registrations.assign($0, to: app) })
    }

    func testStatusNeedsBothWebSchemes() {
        XCTAssertEqual(browser(Registrations(handlers: ["http": bato, "https": bato])).status, .isDefault)
        XCTAssertEqual(browser(Registrations(handlers: ["http": bato, "https": other])).status, .notDefault)
        XCTAssertEqual(browser(Registrations(handlers: [:])).status, .notDefault)
    }

    func testPathComparisonIgnoresTrailingSlashAndDotSegments() {
        let registrations = Registrations(handlers: ["http": URL(fileURLWithPath: "/Applications/./Bato.app/"),
                                                     "https": URL(fileURLWithPath: "/Applications/Bato.app")])
        XCTAssertEqual(browser(registrations).status, .isDefault)
    }

    func testReadingStatusNeverRegisters() {
        let registrations = Registrations(handlers: ["http": other, "https": other])
        _ = browser(registrations).status
        XCTAssertEqual(registrations.assigned, [])
    }

    func testMakeDefaultRegistersOnlyWhatIsMissing() async throws {
        let registrations = Registrations(handlers: ["http": bato, "https": other])
        let browser = browser(registrations)
        try await browser.makeDefault()
        XCTAssertEqual(registrations.assigned, ["https"])
        XCTAssertEqual(browser.status, .isDefault)
        try await browser.makeDefault()
        XCTAssertEqual(registrations.assigned, ["https"])
    }

    func testMakeDefaultStopsAtTheFirstRefusal() async {
        let registrations = Registrations(handlers: [:])
        registrations.failing = ["http"]
        let browser = browser(registrations)
        do {
            try await browser.makeDefault()
            XCTFail("expected the refusal to propagate")
        } catch {}
        XCTAssertEqual(registrations.assigned, [])
        XCTAssertEqual(browser.status, .notDefault)
    }
}
