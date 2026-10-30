import Foundation
import Testing
import BatoCore
import BatoPersistence
@testable import BatoShell

@MainActor
struct ShellSessionTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test func staleSaveDoesNotPublishOrOverwriteExternalCommit() throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = ShellSession(directory: directory)
        #expect(session.addTab("https://example.com"))
        let before = try #require(session.state)
        let external = OrganizationStore<BrowserState>(directory: directory, validate: { try $0.validate() })
        var newer = try #require(try external.load())
        newer.workspaces[0].name = "External revision"
        try external.save(newer)

        #expect(!session.addTab("https://example.net"))
        #expect(session.state == before)
        #expect(session.errorMessage != nil)
        #expect(try external.load() == newer)
    }

    @Test func malformedStoreCannotBeReplacedByCommands() throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("organization.json")
        let original = Data("invalid synthetic document".utf8)
        try original.write(to: file)
        let session = ShellSession(directory: directory)
        #expect(session.state == nil)
        #expect(!session.addTab("https://example.com"))
        #expect(try Data(contentsOf: file) == original)
    }

    @Test func closingCommandBarPreservesSelectedEntry() throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = ShellSession(directory: directory)
        #expect(session.addTab("https://example.com"))
        let before = try #require(session.state)
        session.showsCommandBar = true
        session.closeSelection()
        #expect(!session.showsCommandBar)
        #expect(session.state == before)
    }
}
