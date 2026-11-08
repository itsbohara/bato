import BatoCore
import Foundation
import Testing
@testable import BatoPersistence

struct ClosedTabsStoreTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("closed-tabs-\(UUID().uuidString)")
    }

    private func tab(_ profileID: UUID, _ name: String) -> ClosedTab {
        ClosedTab(profileID: profileID, workspaceID: UUID(), title: name,
                  url: URL(string: "https://example.invalid/\(name)")!, index: 0)
    }

    @Test func missingFileLoadsEmpty() {
        #expect(ClosedTabsStore(directory: directory()).load().isEmpty)
    }

    @Test func stacksSurviveANewStoreInOrder() throws {
        let dir = directory()
        let profile = UUID()
        var stack = ClosedTabStack()
        stack.push(tab(profile, "a"))
        stack.push(tab(profile, "b"))
        try ClosedTabsStore(directory: dir).save([profile: stack])
        let loaded = ClosedTabsStore(directory: dir).load()
        #expect(loaded[profile]?.tabs.map(\.title) == ["a", "b"])
    }

    @Test func loadKeepsOnlyTheNewestTabsUpToCapacity() throws {
        let dir = directory()
        let profile = UUID()
        let tabs = (0..<(ClosedTabStack.capacity + 5)).map { tab(profile, "t\($0)") }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ClosedTabsStore(directory: dir)
        let document = #"{"version":1,"stacks":{"\#(profile.uuidString)":"#
            + String(decoding: try JSONEncoder().encode(tabs), as: UTF8.self) + "}}"
        try Data(document.utf8).write(to: store.fileURL)
        let loaded = try #require(store.load()[profile])
        #expect(loaded.tabs.count == ClosedTabStack.capacity)
        #expect(loaded.last?.title == "t\(ClosedTabStack.capacity + 4)")
    }

    @Test func tabsFiledUnderTheWrongProfileAreDropped() throws {
        let dir = directory()
        let profile = UUID()
        let store = ClosedTabsStore(directory: dir)
        try store.save([profile: ClosedTabStack(tabs: [tab(UUID(), "stray"), tab(profile, "own")])])
        #expect(store.load()[profile]?.tabs.map(\.title) == ["own"])
    }

    @Test func corruptFileIsSetAsideAndLoadsEmpty() throws {
        let dir = directory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ClosedTabsStore(directory: dir)
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(store.load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(FileManager.default.fileExists(atPath: store.fileURL.appendingPathExtension("corrupt").path))
    }
}
