import Foundation
import Testing
@testable import BatoBlocking

struct FilterListUpdaterTests {
    private func makeUpdater(_ fetcher: FakeFetcher, directory: URL, now: @escaping @Sendable () -> Date = { Date() }) -> FilterListUpdater {
        FilterListUpdater(directory: directory, sources: [fakeSource], fetcher: fetcher, now: now)
    }

    private func activeList(_ directory: URL) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent("lists/fake.txt"))
    }

    @Test func validatorAcceptsWellFormedLists() {
        #expect(FilterListValidator.validate(listData(rules: 5), for: fakeSource) == .success(5))
    }

    @Test func validatorRejectsEmptyOversizedBinaryAndHeaderless() {
        #expect(FilterListValidator.validate(Data(), for: fakeSource) == .failure(.missingHeader))
        #expect(FilterListValidator.validate(listData(rules: 4), for: fakeSource) == .failure(.tooFewRules))
        #expect(FilterListValidator.validate(listData(rules: 2_000), for: fakeSource) == .failure(.tooLarge))
        #expect(FilterListValidator.validate(Data([0xFF, 0xFE, 0x00, 0x5B]), for: fakeSource) == .failure(.notText))
        #expect(FilterListValidator.validate(Data("<html>hi</html>".utf8), for: fakeSource) == .failure(.missingHeader))
        #expect(FilterListValidator.validate(listData(rules: 9, header: "[uBlock Origin]"), for: fakeSource) == .success(9))
    }

    @Test func defaultSourcesAreHttpsUpstreamLists() {
        #expect(FilterListSource.defaults.map(\.url.absoluteString) == [
            "https://easylist.to/easylist/easylist.txt", "https://easylist.to/easylist/easyprivacy.txt"])
    }

    @Test func installsValidDownloadAndRecordsStatus() async throws {
        let directory = temporaryDirectory()
        let fetcher = FakeFetcher()
        let body = listData(rules: 6)
        fetcher.enqueue(fakeSource.url, .success(.content(body, etag: "\"v1\"")))
        let updater = makeUpdater(fetcher, directory: directory)
        #expect(await updater.update() == ["fake": .updated(ruleCount: 6)])
        #expect(activeList(directory) == body)
        let status = try #require(await updater.status()["fake"])
        #expect(status.etag == "\"v1\"")
        #expect(status.ruleCount == 6)
        #expect(status.lastError == nil)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(FilterListUpdater.statusFileName).path))
    }

    @Test func rejectedDownloadKeepsLastGoodList() async throws {
        let directory = temporaryDirectory()
        let fetcher = FakeFetcher()
        let good = listData(rules: 6)
        fetcher.enqueue(fakeSource.url, .success(.content(good, etag: "a")))
        fetcher.enqueue(fakeSource.url, .success(.content(Data(), etag: "b")))
        fetcher.enqueue(fakeSource.url, .success(.content(listData(rules: 2_000), etag: "c")))
        fetcher.enqueue(fakeSource.url, .success(.content(Data("<html>".utf8), etag: "d")))
        let updater = makeUpdater(fetcher, directory: directory)
        await updater.update()
        #expect(await updater.update() == ["fake": .rejected(.missingHeader)])
        #expect(await updater.update() == ["fake": .rejected(.tooLarge)])
        #expect(await updater.update() == ["fake": .rejected(.missingHeader)])
        #expect(activeList(directory) == good)
        let status = try #require(await updater.status()["fake"])
        #expect(status.etag == "a")
        #expect(status.lastError == "rejected: missingHeader")
        #expect(status.ruleCount == 6)
    }

    @Test func networkFailureKeepsLastGoodListAndIsDiagnosable() async throws {
        let directory = temporaryDirectory()
        let fetcher = FakeFetcher()
        let good = listData(rules: 6)
        fetcher.enqueue(fakeSource.url, .success(.content(good, etag: nil)))
        let updater = makeUpdater(fetcher, directory: directory)
        await updater.update()
        let outcome = try #require(await updater.update()["fake"])
        guard case .failed = outcome else { Issue.record("expected failure, got \(outcome)"); return }
        #expect(activeList(directory) == good)
        #expect(try #require(await updater.status()["fake"]).lastError != nil)
    }

    @Test func notModifiedSendsEtagAndKeepsFile() async throws {
        let directory = temporaryDirectory()
        let fetcher = FakeFetcher()
        let good = listData(rules: 6)
        fetcher.enqueue(fakeSource.url, .success(.content(good, etag: "tag")))
        fetcher.enqueue(fakeSource.url, .success(.notModified))
        let updater = makeUpdater(fetcher, directory: directory)
        await updater.update()
        #expect(await updater.update() == ["fake": .unchanged])
        #expect(fetcher.requests.map(\.etag) == [nil, "tag"])
        #expect(activeList(directory) == good)
    }

    @Test func missingFileDropsStoredEtagSoANotModifiedCannotLeaveNoList() async throws {
        let directory = temporaryDirectory()
        let fetcher = FakeFetcher()
        fetcher.enqueue(fakeSource.url, .success(.content(listData(rules: 6), etag: "tag")))
        fetcher.enqueue(fakeSource.url, .success(.content(listData(rules: 7), etag: "tag2")))
        let updater = makeUpdater(fetcher, directory: directory)
        await updater.update()
        try FileManager.default.removeItem(at: directory.appendingPathComponent("lists/fake.txt"))
        await updater.update()
        #expect(fetcher.requests.map(\.etag) == [nil, nil])
        #expect(activeList(directory) != nil)
    }

    @Test func recentChecksAreSkippedUntilDue() async {
        let directory = temporaryDirectory()
        let fetcher = FakeFetcher()
        fetcher.enqueue(fakeSource.url, .success(.content(listData(rules: 6), etag: nil)))
        fetcher.enqueue(fakeSource.url, .success(.content(listData(rules: 8), etag: nil)))
        let clock = Clock(Date(timeIntervalSince1970: 1_000))
        let updater = makeUpdater(fetcher, directory: directory) { clock.now }
        await updater.update(maxAge: 3_600)
        clock.advance(60)
        #expect(await updater.update(maxAge: 3_600) == ["fake": .unchanged])
        #expect(fetcher.requests.count == 1)
        clock.advance(3_600)
        #expect(await updater.update(maxAge: 3_600) == ["fake": .updated(ruleCount: 8)])
    }

    @Test func statusSurvivesANewUpdaterInstance() async throws {
        let directory = temporaryDirectory()
        let fetcher = FakeFetcher()
        fetcher.enqueue(fakeSource.url, .success(.content(listData(rules: 6), etag: "tag")))
        fetcher.enqueue(fakeSource.url, .success(.notModified))
        await makeUpdater(fetcher, directory: directory).update()
        await makeUpdater(fetcher, directory: directory).update()
        #expect(fetcher.requests.map(\.etag) == [nil, "tag"])
    }
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) { current = start }
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}
