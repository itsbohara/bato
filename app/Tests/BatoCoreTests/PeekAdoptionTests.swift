import Foundation
import XCTest
@testable import BatoCore

/// Organization prerequisites only; these tests do not create or adopt engine pages.
final class PeekAdoptionTests: XCTestCase {
    private let originalURL = URL(string: "https://example.invalid/original")!
    private let latestURL = URL(string: "https://example.invalid/preview-latest")!

    func testSuppliedIdentityAndLatestDestinationBecomeSelectedTemporaryTab() throws {
        var state = BrowserState.initial()
        let existing = try state.addTab(url: originalURL, title: "Existing")
        try state.pinEntry(existing)
        let before = state
        let suppliedID = UUID()

        let added = try state.addTab(id: suppliedID, url: latestURL, title: "Latest preview title")

        XCTAssertEqual(added, suppliedID)
        XCTAssertEqual(state.currentWorkspace.activeEntryID, suppliedID)
        XCTAssertEqual(state.currentWorkspace.tabs, [PageEntry(id: suppliedID, title: "Latest preview title",
                                                              lastURL: latestURL, kind: .temporary)])
        XCTAssertNil(state.currentWorkspace.tabs.first?.savedURL)
        XCTAssertEqual(state.currentWorkspace.pins, before.currentWorkspace.pins)
        XCTAssertEqual(state.profiles, before.profiles)
        XCTAssertEqual(state.activeWorkspaceID, before.activeWorkspaceID)
        XCTAssertEqual(state.version, before.version)
        XCTAssertEqual(try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(state)), state)
    }

    func testDuplicateIdentityAnywhereRollsBackIncludingActiveTransientSplitIdentity() throws {
        var baseline = try splitState(pinned: false)
        let otherProfile = BrowserProfile(name: "Other", favorites: [
            PageEntry(title: "Other favorite", savedURL: originalURL, lastURL: originalURL, kind: .favorite)
        ])
        let otherWorkspace = Workspace(profileID: otherProfile.id, name: "Other workspace", tabs: [
            PageEntry(title: "Other tab", lastURL: originalURL, kind: .temporary)
        ])
        baseline.profiles.append(otherProfile)
        baseline.workspaces.append(otherWorkspace)
        baseline.profiles[0].favorites.append(
            PageEntry(title: "Favorite", savedURL: originalURL, lastURL: originalURL, kind: .favorite))
        try baseline.validate()
        var identities: [UUID] = []
        for profile in baseline.profiles {
            identities.append(profile.id)
            identities.append(contentsOf: profile.favorites.map(\.id))
        }
        for workspace in baseline.workspaces {
            identities.append(workspace.id)
            identities.append(contentsOf: workspace.pins.map(\.id))
            identities.append(contentsOf: workspace.tabs.map(\.id))
            identities.append(contentsOf: workspace.folders.map(\.id))
            identities.append(contentsOf: workspace.splits.map(\.id))
        }

        for identity in identities {
            var candidate = baseline
            XCTAssertThrowsError(try candidate.addTab(id: identity, url: latestURL, title: "Collision")) {
                XCTAssertEqual($0 as? BrowserStateError, .duplicateIdentity)
            }
            XCTAssertEqual(candidate, baseline)
        }
    }

    func testAdoptedSelectionHidesTransientSplitWithoutChangingExistingEntries() throws {
        var state = try splitState(pinned: false)
        let before = state
        let adoptedID = UUID()

        try state.addTab(id: adoptedID, url: latestURL, title: "Preview")

        XCTAssertNil(state.currentSplit)
        XCTAssertNil(state.currentWorkspace.activeSplitID)
        XCTAssertEqual(state.currentWorkspace.splits, before.currentWorkspace.splits)
        XCTAssertEqual(state.currentWorkspace.activeEntryID, adoptedID)
        XCTAssertEqual(state.currentWorkspace.pins, before.currentWorkspace.pins)
        XCTAssertEqual(state.currentWorkspace.folders, before.currentWorkspace.folders)
        XCTAssertEqual(Array(state.currentWorkspace.tabs.dropLast()), before.currentWorkspace.tabs)
        XCTAssertEqual(state.profiles, before.profiles)
    }

    func testAdoptedSelectionRetainsSavedPairMetadataAndExistingDestinations() throws {
        var state = try splitState(pinned: true)
        let before = state
        let adoptedID = UUID()

        try state.addTab(id: adoptedID, url: latestURL, title: "Preview")

        XCTAssertNil(state.currentSplit)
        XCTAssertNil(state.currentWorkspace.activeSplitID)
        XCTAssertEqual(state.currentWorkspace.splits, before.currentWorkspace.splits)
        XCTAssertEqual(state.currentWorkspace.activeEntryID, adoptedID)
        XCTAssertEqual(state.currentWorkspace.pins, before.currentWorkspace.pins)
        XCTAssertEqual(state.currentWorkspace.folders, before.currentWorkspace.folders)
        XCTAssertEqual(Array(state.currentWorkspace.tabs.dropLast()), before.currentWorkspace.tabs)
        XCTAssertEqual(state.profiles, before.profiles)
    }

    func testInvalidDestinationRollsBackWithoutChangingActiveSplit() throws {
        let baseline = try splitState(pinned: false)
        for destination in ["about:blank", "file:///tmp/preview", "https://user:password@example.invalid/"] {
            var candidate = baseline
            XCTAssertThrowsError(try candidate.addTab(id: UUID(), url: URL(string: destination)!, title: "Invalid")) {
                XCTAssertEqual($0 as? BrowserStateError, .invalidURL)
            }
            XCTAssertEqual(candidate, baseline)
        }
    }

    func testDefaultIdentityStillCreatesDistinctTabs() throws {
        var state = BrowserState.initial()
        let first = try state.addTab(url: originalURL, title: "First")
        let second = try state.addTab(url: latestURL, title: "Second")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(state.currentWorkspace.tabs.map(\.id), [first, second])
        XCTAssertEqual(state.currentWorkspace.activeEntryID, second)
    }

    private func splitState(pinned: Bool) throws -> BrowserState {
        var state = BrowserState.initial()
        let first = try state.addTab(url: originalURL, title: "First")
        try state.pinEntry(first)
        let second = try state.addTab(url: originalURL, title: "Second")
        try state.pinEntry(second)
        try state.recordNavigation(entryID: second, url: latestURL, title: "Navigated second")
        let folder = try state.createFolder(name: "Saved pages")
        try state.movePin(first, toFolder: folder)
        let pair = try state.createSplit(with: first)
        if pinned { try state.pinSplit(pair) }
        try state.validate()
        return state
    }
}
