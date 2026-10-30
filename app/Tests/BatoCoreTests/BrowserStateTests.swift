import Foundation
import XCTest
@testable import BatoCore

final class BrowserStateTests: XCTestCase {
    private let saved = URL(string: "https://example.invalid/start")!
    private let navigated = URL(string: "https://example.invalid/next")!

    func testFirstLaunchIsEmptyAndValid() throws {
        let state = BrowserState.initial()
        try state.validate()
        XCTAssertEqual(state.profiles.count, 1)
        XCTAssertEqual(state.workspaces.count, 1)
        XCTAssertEqual(state.currentWorkspace.profileID, state.profiles[0].id)
        XCTAssertTrue(state.visibleEntries.isEmpty)
        XCTAssertNil(state.currentWorkspace.activeEntryID)
    }

    func testSavedURLSurvivesNavigationAndCloseWithoutDeletingPin() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: saved, title: "Start")
        try state.pinEntry(id)
        try state.recordNavigation(entryID: id, url: navigated, title: "Next")
        XCTAssertEqual(state.visibleEntries[0].savedURL, saved)
        XCTAssertEqual(state.visibleEntries[0].lastURL, navigated)
        try state.closeEntry(id)
        XCTAssertEqual(state.currentWorkspace.pins.map(\.id), [id])
        XCTAssertEqual(state.visibleEntries[0].lastURL, saved)
        XCTAssertNil(state.currentWorkspace.activeEntryID)
        try state.selectEntry(id)
        XCTAssertEqual(state.currentWorkspace.activeEntryID, id)
    }

    func testClosingTemporaryTabRemovesOnlyThatEntryAndRetainsOrder() throws {
        var state = BrowserState.initial()
        let first = try state.addTab(url: saved, title: "First")
        let middle = try state.addTab(url: saved, title: "Middle")
        let last = try state.addTab(url: saved, title: "Last")
        try state.closeEntry(middle)
        XCTAssertEqual(state.currentWorkspace.tabs.map(\.id), [first, last])
        XCTAssertEqual(state.currentWorkspace.activeEntryID, last)
        try state.closeEntry(last)
        XCTAssertNil(state.currentWorkspace.activeEntryID)
    }

    func testFavoritesShareProfileButPinsAndTemporaryTabsStayInWorkspace() throws {
        var state = BrowserState.initial()
        let firstWorkspace = state.activeWorkspaceID
        let favorite = try state.addTab(url: saved, title: "Favorite")
        try state.favoriteEntry(favorite)
        let pin = try state.addTab(url: saved, title: "Pin")
        try state.pinEntry(pin)
        let temporary = try state.addTab(url: saved, title: "Temporary")
        let shared = try state.addWorkspace(name: "Work", profileID: state.currentWorkspace.profileID)
        try state.activateWorkspace(shared)
        XCTAssertEqual(state.visibleEntries.map(\.id), [favorite])
        try state.selectEntry(favorite)
        let separateProfile = try state.addProfile(name: "Separate")
        let isolated = try state.addWorkspace(name: "Isolated", profileID: separateProfile)
        try state.activateWorkspace(isolated)
        XCTAssertTrue(state.visibleEntries.isEmpty)
        let before = state
        XCTAssertThrowsError(try state.selectEntry(favorite))
        XCTAssertEqual(state, before)
        try state.activateWorkspace(firstWorkspace)
        XCTAssertEqual(state.visibleEntries.map(\.id), [favorite, pin, temporary])
    }

    func testConvertingSharedFavoriteToPinClearsOtherWorkspaceSelection() throws {
        var state = BrowserState.initial()
        let firstWorkspace = state.activeWorkspaceID
        let id = try state.addTab(url: saved, title: "Shared")
        try state.favoriteEntry(id)
        let other = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        try state.activateWorkspace(other)
        try state.selectEntry(id)
        try state.pinEntry(id)
        XCTAssertTrue(state.profiles[0].favorites.isEmpty)
        XCTAssertEqual(state.currentWorkspace.pins.map(\.id), [id])
        XCTAssertEqual(state.currentWorkspace.activeEntryID, id)
        try state.activateWorkspace(firstWorkspace)
        XCTAssertNil(state.currentWorkspace.activeEntryID)
        XCTAssertTrue(state.visibleEntries.isEmpty)
        try state.validate()
    }

    func testBackgroundNavigationDoesNotSwitchWorkspaceOrSelection() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: saved, title: "Background")
        let originalWorkspace = state.activeWorkspaceID
        let other = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        try state.activateWorkspace(other)
        try state.recordNavigation(entryID: id, url: navigated, title: "Updated")
        XCTAssertEqual(state.activeWorkspaceID, other)
        XCTAssertNil(state.currentWorkspace.activeEntryID)
        try state.activateWorkspace(originalWorkspace)
        XCTAssertEqual(state.currentWorkspace.tabs[0].lastURL, navigated)
        XCTAssertNil(state.currentWorkspace.tabs[0].savedURL)
    }

    func testRoundTripRetainsStableIDsOrderingAndSessionDestination() throws {
        var state = BrowserState.initial()
        let first = try state.addTab(url: saved, title: "First")
        let second = try state.addTab(url: navigated, title: "Second")
        try state.pinEntry(first)
        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(BrowserState.self, from: data)
        try restored.validate()
        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.visibleEntries.map(\.id), [first, second])
        XCTAssertEqual(restored.currentWorkspace.tabs[0].lastURL, navigated)
    }

    func testDecodedUnsupportedVersionAndDanglingSelectionAreRejected() throws {
        let state = BrowserState.initial()
        let data = try JSONEncoder().encode(state)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["version"] = 2
        let future = try JSONDecoder().decode(BrowserState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try future.validate()) { error in
            XCTAssertEqual(error as? BrowserStateError, .unsupportedVersion(2))
        }
        var invalid = state
        invalid.workspaces[0].activeEntryID = UUID()
        XCTAssertThrowsError(try invalid.validate()) { error in
            XCTAssertEqual(error as? BrowserStateError, .invalidSelection)
        }
    }

    func testValidationRejectsDuplicateIdentityWrongOwnershipAndMissingSavedURL() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: saved, title: "Tab")
        var duplicate = state
        duplicate.workspaces[0].tabs.append(state.currentWorkspace.tabs[0])
        XCTAssertThrowsError(try duplicate.validate()) { error in
            XCTAssertEqual(error as? BrowserStateError, .duplicateIdentity)
        }
        var wrongKind = state
        wrongKind.workspaces[0].tabs[0].kind = .favorite
        XCTAssertThrowsError(try wrongKind.validate()) { error in
            XCTAssertEqual(error as? BrowserStateError, .invalidEntryOwnership)
        }
        try state.pinEntry(id)
        state.workspaces[0].pins[0].savedURL = nil
        XCTAssertThrowsError(try state.validate()) { error in
            XCTAssertEqual(error as? BrowserStateError, .invalidSavedURL)
        }
    }

    func testRejectedCommandsLeaveOriginalStateUntouched() throws {
        var state = BrowserState.initial()
        let before = state
        XCTAssertThrowsError(try state.addTab(url: URL(string: "file:///private/test")!, title: "Invalid"))
        XCTAssertEqual(state, before)
        XCTAssertThrowsError(try state.addWorkspace(name: "Work", profileID: UUID()))
        XCTAssertEqual(state, before)
        XCTAssertThrowsError(try state.addProfile(name: " \n "))
        XCTAssertEqual(state, before)
        XCTAssertThrowsError(try state.activateWorkspace(UUID()))
        XCTAssertEqual(state, before)
        XCTAssertThrowsError(try state.recordNavigation(entryID: UUID(), url: saved, title: "Missing"))
        XCTAssertEqual(state, before)
    }

    func testEmbeddedCredentialsAreRejectedOnValidationAndNavigationWithoutMutation() throws {
        var state = BrowserState.initial()
        let id = try state.addTab(url: saved, title: "Page")
        try state.pinEntry(id)
        let before = state
        let credentialURLs = [
            URL(string: "https://synthetic-user@example.invalid/")!,
            URL(string: "https://synthetic-user:synthetic-password@example.invalid/")!,
            URL(string: "https://:synthetic-password@example.invalid/")!,
        ]
        for url in credentialURLs {
            XCTAssertThrowsError(try state.recordNavigation(entryID: id, url: url, title: "Rejected")) { error in
                XCTAssertEqual(error as? BrowserStateError, .invalidURL)
            }
            XCTAssertEqual(state, before)
            XCTAssertThrowsError(try state.addTab(url: url, title: "Rejected"))
            XCTAssertEqual(state, before)

            var invalidSessionURL = before
            invalidSessionURL.workspaces[0].pins[0].lastURL = url
            XCTAssertThrowsError(try invalidSessionURL.validate())

            var invalidSavedURL = before
            invalidSavedURL.workspaces[0].pins[0].savedURL = url
            XCTAssertThrowsError(try invalidSavedURL.validate())
        }
    }
}
