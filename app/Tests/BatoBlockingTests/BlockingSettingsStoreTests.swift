import Foundation
import Testing
@testable import BatoBlocking

struct BlockingSettingsStoreTests {
    @Test func missingFileYieldsDefaultsWithoutCreatingOne() {
        let directory = temporaryDirectory()
        let store = BlockingSettingsStore(directory: directory)
        #expect(store.current() == BlockingSettings())
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test func reloadPicksUpAFileReplacedOnDisk() throws {
        let directory = temporaryDirectory()
        let store = BlockingSettingsStore(directory: directory)
        try store.update { $0.enabled = false }
        let restored = try JSONEncoder().encode(BlockingSettings())
        try restored.write(to: store.fileURL)
        #expect(!store.current().enabled)
        store.reload()
        #expect(store.current().enabled)
    }

    @Test func updatesPersistAcrossStoreInstances() throws {
        let directory = temporaryDirectory().appendingPathComponent("nested")
        let store = BlockingSettingsStore(directory: directory)
        try store.update { try $0.addException("example.com") }
        try store.update { $0.enabled = false }
        let reloaded = BlockingSettingsStore(directory: directory).current()
        #expect(reloaded.exceptions == ["example.com"])
        #expect(!reloaded.enabled)
    }

    @Test func fileHasTheDocumentedShapeAndLeavesNoTemporaryFiles() throws {
        let directory = temporaryDirectory()
        let store = BlockingSettingsStore(directory: directory)
        try store.update { try $0.addException("example.com") }
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any]
        #expect(json?["version"] as? Int == 1)
        #expect(json?["enabled"] as? Bool == true)
        #expect(json?["exceptions"] as? [String] == ["example.com"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [BlockingSettingsStore.fileName])
    }

    @Test func failedChangeKeepsMemoryAndDiskUnchanged() throws {
        let directory = temporaryDirectory()
        let store = BlockingSettingsStore(directory: directory)
        try store.update { try $0.addException("keep.com") }
        #expect(throws: BlockingSettingsError.invalidHost) {
            try store.update { settings in
                settings.enabled = false
                try settings.addException("bad host")
            }
        }
        #expect(store.current().enabled)
        #expect(BlockingSettingsStore(directory: directory).current().exceptions == ["keep.com"])
    }

    @Test func corruptFileIsSetAsideAndDefaultsUsed() throws {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent(BlockingSettingsStore.fileName)
        try Data("{not json".utf8).write(to: url)
        let store = BlockingSettingsStore(directory: directory)
        #expect(store.current() == BlockingSettings())
        #expect(store.recoveredFromCorruption)
        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func saveFailureIsReportedAndKeepsPreviousState() throws {
        let directory = temporaryDirectory()
        let blocker = directory.appendingPathComponent("file")
        try Data().write(to: blocker)
        let store = BlockingSettingsStore(directory: blocker)
        #expect(throws: BlockingSettingsStore.StoreError.saveFailed) { try store.update { $0.enabled = false } }
        #expect(store.current().enabled)
    }
}
