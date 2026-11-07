import Foundation
import Testing
@testable import BatoBlocking

struct BlockingProfilesTests {
    private let page = URL(string: "https://www.example.com/article")!
    private let profileA = "11111111-1111-1111-1111-111111111111"
    private let profileB = "22222222-2222-2222-2222-222222222222"

    private func profiles(_ root: URL = temporaryDirectory()) -> BlockingProfiles {
        BlockingProfiles(rootDirectory: root, sources: [fakeSource], fetcher: FakeFetcher())
    }

    @Test func exceptionsAreIsolatedPerProfile() throws {
        let profiles = profiles()
        let a = try #require(profiles.service(forProfile: profileA))
        let b = try #require(profiles.service(forProfile: profileB))
        try a.setBlocking(false, forPageURL: page)
        #expect(!a.isBlocking(pageURL: page))
        #expect(b.isBlocking(pageURL: page))
        try b.setEnabled(false)
        #expect(a.settings.enabled)
        #expect(a.exceptions == ["www.example.com"])
        #expect(b.exceptions.isEmpty)
    }

    @Test func eachProfileWritesItsOwnSettingsFileUnderTheRoot() throws {
        let root = temporaryDirectory()
        let profiles = profiles(root)
        try #require(profiles.service(forProfile: profileA)).setBlocking(false, forPageURL: page)
        let fileA = root.appendingPathComponent(profileA).appendingPathComponent(BlockingSettingsStore.fileName)
        let fileB = root.appendingPathComponent(profileB).appendingPathComponent(BlockingSettingsStore.fileName)
        #expect(FileManager.default.fileExists(atPath: fileA.path))
        #expect(!FileManager.default.fileExists(atPath: fileB.path))
        let reopened = self.profiles(root)
        #expect(try #require(reopened.service(forProfile: profileA)).exceptions == ["www.example.com"])
    }

    @Test func serviceIsSharedPerKeyAndDirectoryMatchesTheHelper() throws {
        let state = URL(fileURLWithPath: "/tmp/state")
        let profiles = profiles(BlockingProfiles.rootDirectory(stateDirectory: state))
        let a = try #require(profiles.service(forProfile: profileA))
        #expect(a === profiles.service(forProfile: profileA))
        #expect(a !== profiles.service(forProfile: profileB))
        #expect(a.directory == BlockingService.directory(stateDirectory: state, profileKey: profileA))
    }

    @Test func countersAreOneObjectBecauseBrowserIdentifiersAreProcessWide() throws {
        let profiles = profiles()
        let a = try #require(profiles.service(forProfile: profileA))
        let b = try #require(profiles.service(forProfile: profileB))
        profiles.counters.recordBlocked(7)
        #expect(a.counters.count(for: 7) == 1)
        #expect(b.counters.count(for: 7) == 1)
        #expect(a.counters === profiles.counters)
    }

    @Test func unsafeKeysGetNoService() {
        let profiles = profiles()
        for key in ["", "..", "a/b", "../x", "lists", "has space", String(repeating: "a", count: 65)] {
            #expect(profiles.service(forProfile: key) == nil)
        }
        #expect(profiles.service(forProfile: "default") != nil)
    }

    @Test func listsAreDownloadedOnceIntoTheSharedDirectory() async throws {
        let root = temporaryDirectory()
        let fetcher = FakeFetcher()
        fetcher.enqueue(fakeSource.url, .success(.content(listData(rules: 10), etag: "e1")))
        let profiles = BlockingProfiles(rootDirectory: root, sources: [fakeSource], fetcher: fetcher)
        _ = profiles.service(forProfile: profileA)
        _ = profiles.service(forProfile: profileB)
        let outcomes = await profiles.updateListsNow()
        #expect(outcomes[fakeSource.id] == .updated(ruleCount: 10))
        #expect(fetcher.requests.count == 1)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("lists/fake.txt").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(profileA).appendingPathComponent("lists").path))
    }
}
