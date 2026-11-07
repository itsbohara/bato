import Foundation
import Testing
@testable import BatoBlocking

struct UBlockListsTests {
    private func fixture() -> (root: URL, fetcher: FakeFetcher) { (temporaryDirectory(), FakeFetcher()) }

    private func profiles(_ root: URL, _ fetcher: FakeFetcher) -> BlockingProfiles {
        BlockingProfiles(rootDirectory: root, sources: [fakeSource], fetcher: fetcher)
    }

    private func uBlockData(rules: Int) -> Data { listData(rules: rules, header: "! Title: uBlock filters") }

    private func serveAll(_ fetcher: FakeFetcher, rules: Int = 20_000) {
        fetcher.enqueue(fakeSource.url, .success(.content(listData(rules: 10), etag: nil)))
        for source in FilterListSource.uBlockOrigin {
            fetcher.enqueue(source.url, .success(.content(uBlockData(rules: rules), etag: "\"v1\"")))
        }
    }

    private func listFile(_ root: URL, _ source: FilterListSource) -> URL {
        root.appendingPathComponent("lists").appendingPathComponent("\(source.id).txt")
    }

    @Test func offerIsDueUntilAnsweredAndNothingDownloadsBeforeConsent() async {
        let (root, fetcher) = fixture()
        let profiles = profiles(root, fetcher)
        #expect(profiles.shouldOfferUBlockLists)
        #expect(profiles.uBlockChoice == .undecided)
        await profiles.updateListsNow()
        #expect(!fetcher.requests.map(\.url).contains { url in FilterListSource.uBlockOrigin.contains { $0.url == url } })
    }

    @Test func decliningIsRememberedAcrossRelaunchesAndDownloadsNothing() async throws {
        let (root, fetcher) = fixture()
        try profiles(root, fetcher).declineUBlockLists()
        let reopened = profiles(root, fetcher)
        #expect(!reopened.shouldOfferUBlockLists)
        #expect(reopened.uBlockChoice == .declined)
        await reopened.updateListsNow()
        #expect(!fetcher.requests.map(\.url).contains { url in FilterListSource.uBlockOrigin.contains { $0.url == url } })
    }

    @Test func acceptingDownloadsEveryUBlockListAndSurvivesRelaunch() async throws {
        let (root, fetcher) = fixture()
        serveAll(fetcher)
        let outcomes = try await profiles(root, fetcher).enableUBlockLists()
        #expect(Set(outcomes.keys) == Set(FilterListSource.uBlockOrigin.map(\.id)))
        #expect(outcomes.values.allSatisfy { $0 == .updated(ruleCount: 20_000) })
        for source in FilterListSource.uBlockOrigin {
            #expect(FileManager.default.fileExists(atPath: listFile(root, source).path))
        }
        let reopened = profiles(root, fetcher)
        #expect(reopened.uBlockChoice == .enabled)
        #expect(!reopened.shouldOfferUBlockLists)
        let status = await reopened.listStatus
        #expect(status["ublock-filters"]?.ruleCount == 20_000)
    }

    @Test func enabledChoiceKeepsUpdatingTheListsOnLaterLaunches() async throws {
        let (root, fetcher) = fixture()
        serveAll(fetcher)
        try await profiles(root, fetcher).enableUBlockLists()
        let before = fetcher.requests.count
        let reopened = profiles(root, fetcher)
        await reopened.updateListsNow()
        let requested = fetcher.requests.dropFirst(before).map(\.url)
        #expect(FilterListSource.uBlockOrigin.allSatisfy { source in requested.contains(source.url) })
    }

    @Test func failedDownloadStaysEnabledAndReportsTheFailure() async throws {
        let (root, fetcher) = fixture()
        let outcomes = try await profiles(root, fetcher).enableUBlockLists()
        #expect(outcomes.count == 4)
        #expect(outcomes.values.allSatisfy { if case .failed = $0 { true } else { false } })
        #expect(profiles(root, fetcher).uBlockChoice == .enabled)
        #expect(!FileManager.default.fileExists(atPath: listFile(root, .uBlockFilters).path))
    }

    @Test func removingDeletesTheDownloadsAndDoesNotReOffer() async throws {
        let (root, fetcher) = fixture()
        serveAll(fetcher)
        let profiles = profiles(root, fetcher)
        try await profiles.enableUBlockLists()
        try await profiles.disableUBlockLists()
        for source in FilterListSource.uBlockOrigin {
            #expect(!FileManager.default.fileExists(atPath: listFile(root, source).path))
        }
        #expect(profiles.uBlockChoice == .declined)
        #expect(!profiles.shouldOfferUBlockLists)
        #expect(await profiles.listStatus["ublock-filters"] == nil)
        let reAdded = fixture()
        serveAll(reAdded.fetcher)
        try await self.profiles(root, reAdded.fetcher).enableUBlockLists()
        #expect(FileManager.default.fileExists(atPath: listFile(root, .uBlockFilters).path))
    }

    @Test func uBlockListsNeedNoHeaderButStillNeedRulesAndEasyListsStillNeedTheHeader() {
        #expect(FilterListValidator.validate(uBlockData(rules: 20_000), for: .uBlockFilters) == .success(20_000))
        #expect(FilterListValidator.validate(uBlockData(rules: 5), for: .uBlockFilters) == .failure(.tooFewRules))
        #expect(FilterListValidator.validate(uBlockData(rules: 30_000), for: .easyList) == .failure(.missingHeader))
        #expect(FilterListSource.uBlockOrigin.allSatisfy { $0.url.scheme == "https" && !$0.requiresHeader })
    }
}
