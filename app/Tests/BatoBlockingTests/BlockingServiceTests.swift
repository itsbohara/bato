import Foundation
import Testing
@testable import BatoBlocking

struct BlockingServiceTests {
    private func service(_ directory: URL = temporaryDirectory()) -> BlockingService {
        BlockingService(directory: directory, sources: [fakeSource], fetcher: FakeFetcher())
    }

    private let page = URL(string: "https://www.example.com/article")!

    @Test func profileDirectoryIsUnderStateDirectory() {
        let state = URL(fileURLWithPath: "/tmp/state")
        #expect(BlockingService.directory(stateDirectory: state).path == "/tmp/state/blocking/default")
        #expect(BlockingService.directory(stateDirectory: state, profileKey: "P1").path == "/tmp/state/blocking/P1")
    }

    @Test func blockingIsOnByDefault() {
        #expect(service().isBlocking(pageURL: page))
    }

    @Test func turningBlockingOffAddsExceptionForTheHostAndPersists() throws {
        let directory = temporaryDirectory()
        try service(directory).setBlocking(false, forPageURL: page)
        let reloaded = service(directory)
        #expect(reloaded.exceptions == ["www.example.com"])
        #expect(!reloaded.isBlocking(pageURL: page))
        #expect(!reloaded.isBlocking(pageURL: URL(string: "https://a.www.example.com/")!))
        #expect(reloaded.isBlocking(pageURL: URL(string: "https://example.com/")!))
        #expect(reloaded.isBlocking(pageURL: URL(string: "https://www.example.org/")!))
    }

    @Test func turningBlockingOnRemovesCoveringExceptionsIncludingParents() throws {
        let service = service()
        try service.setBlocking(false, forPageURL: URL(string: "https://example.com/")!)
        #expect(!service.isBlocking(pageURL: page))
        try service.setBlocking(true, forPageURL: page)
        #expect(service.isBlocking(pageURL: page))
        #expect(service.exceptions.isEmpty)
    }

    @Test func offForSubdomainOfExistingExceptionAddsNothing() throws {
        let service = service()
        try service.setBlocking(false, forPageURL: URL(string: "https://example.com/")!)
        try service.setBlocking(false, forPageURL: page)
        #expect(service.exceptions == ["example.com"])
    }

    @Test func removeExceptionAndGlobalSwitch() throws {
        let service = service()
        try service.setBlocking(false, forPageURL: page)
        try service.removeException(host: "www.example.com")
        #expect(service.isBlocking(pageURL: page))
        try service.setEnabled(false)
        #expect(!service.isBlocking(pageURL: page))
        #expect(!service.isBlocking(pageURL: URL(string: "about:blank")!))
    }

    @Test func pagesWithoutAHostCannotGetAnException() {
        #expect(throws: BlockingSettingsError.invalidHost) {
            try service().setBlocking(false, forPageURL: URL(string: "about:blank")!)
        }
    }

    @Test func updateNowFetchesThroughInjectedFetcherOnly() async throws {
        let directory = temporaryDirectory()
        let fetcher = FakeFetcher()
        fetcher.enqueue(fakeSource.url, .success(.content(listData(rules: 6), etag: nil)))
        let service = BlockingService(directory: directory, sources: [fakeSource], fetcher: fetcher)
        #expect(await service.updateListsNow() == ["fake": .updated(ruleCount: 6)])
        #expect(try await service.listStatus["fake"]?.ruleCount == 6)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("lists/fake.txt").path))
    }
}
