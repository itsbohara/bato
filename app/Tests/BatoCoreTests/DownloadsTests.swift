import Testing
@testable import BatoCore

@MainActor
final class FakeDownloadsEngine: DownloadsEngine {
    var onEvent: ((DownloadEvent) -> Void)?
    var snapshotRequests = 0
    var performed: [(DownloadAction, String, String)] = []
    var accepts = true

    func requestSnapshot() { snapshotRequests += 1 }
    func perform(_ action: DownloadAction, id: String, profileKey: String) -> Bool {
        performed.append((action, id, profileKey))
        return accepts
    }
}

private func item(_ id: String, profile: String = "a", received: Int64 = 0, total: Int64 = 100,
                  state: DownloadState = .inProgress) -> DownloadItem {
    DownloadItem(id: id, profileKey: profile, filename: "\(id).zip", receivedBytes: received, totalBytes: total, state: state)
}

@Suite struct DownloadsModelTests {
    @Test func newestFirstAndUpsertReplaces() {
        var model = DownloadsModel()
        model.apply(.upsert(item("1")))
        model.apply(.upsert(item("2")))
        model.apply(.upsert(item("1", received: 50)))
        #expect(model.items(for: "a").map(\.id) == ["2", "1"])
        #expect(model.items(for: "a")[1].receivedBytes == 50)
    }

    @Test func profilesAreIsolated() {
        var model = DownloadsModel()
        model.apply(.upsert(item("1", profile: "a")))
        model.apply(.upsert(item("1", profile: "b", state: .completed)))
        #expect(model.items(for: "a").first?.state == .inProgress)
        #expect(model.items(for: "b").first?.state == .completed)
        model.apply(.removed(profileKey: "a", id: "1"))
        #expect(model.items(for: "a").isEmpty)
        #expect(model.items(for: "b").count == 1)
    }

    @Test func unseenFinishOnTransitionUntilSeen() {
        var model = DownloadsModel()
        model.apply(.upsert(item("1")))
        #expect(!model.hasUnseenFinish(for: "a"))
        model.apply(.upsert(item("1", received: 100, state: .completed)))
        #expect(model.hasUnseenFinish(for: "a"))
        model.markSeen("a")
        #expect(!model.hasUnseenFinish(for: "a"))
    }

    @Test func snapshotOfFinishedItemCountsAsUnseen() {
        var model = DownloadsModel()
        model.apply(.upsert(item("1", state: .failed)))
        #expect(model.hasUnseenFinish(for: "a"))
    }

    @Test func aggregateFractionIgnoresFinishedAndUnsized() {
        var model = DownloadsModel()
        model.apply(.upsert(item("1", received: 50, total: 100)))
        model.apply(.upsert(item("2", received: 0, total: 300)))
        model.apply(.upsert(item("3", received: 10, total: -1)))
        model.apply(.upsert(item("4", received: 100, total: 100, state: .completed)))
        #expect(model.aggregateFraction(for: "a") == 0.125)
        #expect(model.aggregateFraction(for: "none") == nil)
    }

    @Test func clearFinishedKeepsActive() {
        var model = DownloadsModel()
        model.apply(.upsert(item("1")))
        model.apply(.upsert(item("2", state: .completed)))
        model.apply(.upsert(item("3", state: .cancelled)))
        model.clearFinished(for: "a")
        #expect(model.items(for: "a").map(\.id) == ["1"])
        #expect(!model.hasUnseenFinish(for: "a"))
    }

    @Test func fractionClampsAndHandlesUnknownTotal() {
        #expect(item("1", received: 150, total: 100).fraction == 1)
        #expect(item("1", received: 5, total: -1).fraction == nil)
    }

    @Test func statusText() {
        #expect(DownloadFormat.status(item("1", state: .cancelled)) == "Cancelled")
        #expect(DownloadFormat.status(item("1", state: .failed)) == "Failed")
        #expect(DownloadFormat.status(DownloadItem(id: "x", profileKey: "a", filename: "f", totalBytes: 2_000_000,
                                                   state: .completed, fileExists: false)) == "File moved or deleted")
        #expect(DownloadFormat.status(item("1", received: 1_000_000, total: 2_000_000)).hasPrefix("1 MB of 2 MB"))
    }
}

@MainActor
@Suite struct DownloadsControllerTests {
    @Test func attachesAndRequestsSnapshot() {
        let engine = FakeDownloadsEngine()
        _ = DownloadsController(engine: engine)
        #expect(engine.snapshotRequests == 1)
        #expect(engine.onEvent != nil)
    }

    @Test func eventsUpdateModelAndNotify() {
        let engine = FakeDownloadsEngine()
        let controller = DownloadsController(engine: engine)
        var changes = 0
        controller.onChange = { changes += 1 }
        engine.onEvent?(.upsert(item("1")))
        #expect(controller.model.items(for: "a").count == 1)
        #expect(changes == 1)
    }

    @Test func actionsGoToEngineWithoutChangingModel() {
        let engine = FakeDownloadsEngine()
        let controller = DownloadsController(engine: engine)
        let download = item("1")
        engine.onEvent?(.upsert(download))
        #expect(controller.perform(.cancel, on: download))
        #expect(engine.performed.count == 1 && engine.performed[0].0 == .cancel && engine.performed[0].2 == "a")
        #expect(controller.model.items(for: "a").first?.state == .inProgress)
        engine.accepts = false
        #expect(!controller.perform(.pause, on: download))
    }
}
