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

    func testWorkspaceCustomizationPreservesOrganizationAndRoundTrips() throws {
        var state = BrowserState.initial()
        let workspaceID = state.activeWorkspaceID
        let favorite = try state.addTab(url: saved, title: "Favorite")
        try state.favoriteEntry(favorite)
        let pin = try state.addTab(url: saved, title: "Pin")
        try state.pinEntry(pin)
        _ = try state.addTab(url: navigated, title: "Temporary")
        _ = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        let before = state

        try state.updateWorkspace(workspaceID, name: "  Research \n", color: "#a1b2c3")
        var expected = before
        expected.workspaces[0].name = "Research"
        expected.workspaces[0].color = "#A1B2C3"
        XCTAssertEqual(state, expected)
        let restored = try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(state))
        try restored.validate()
        XCTAssertEqual(restored, expected)
    }

    func testInvalidWorkspaceCustomizationIsAtomic() throws {
        var state = BrowserState.initial()
        let id = state.activeWorkspaceID
        let before = state
        XCTAssertThrowsError(try state.updateWorkspace(id, name: " \n ", color: "#123456")) { error in
            XCTAssertEqual(error as? BrowserStateError, .emptyName)
        }
        XCTAssertEqual(state, before)
        for color in ["123456", "#123", "#12345G", "#12345678", " #123456"] {
            XCTAssertThrowsError(try state.updateWorkspace(id, name: "Changed", color: color)) { error in
                XCTAssertEqual(error as? BrowserStateError, .invalidColor)
            }
            XCTAssertEqual(state, before)
        }
        XCTAssertThrowsError(try state.updateWorkspace(UUID(), name: "Changed", color: "#123456")) { error in
            XCTAssertEqual(error as? BrowserStateError, .missingWorkspace)
        }
        XCTAssertEqual(state, before)
    }

    func testEditingInactiveWorkspaceDoesNotActivateIt() throws {
        var state = BrowserState.initial()
        let other = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        let before = state
        try state.updateWorkspace(other, name: "Work", color: "#000000")
        var expected = before
        expected.workspaces[1].name = "Work"
        expected.workspaces[1].color = "#000000"
        XCTAssertEqual(state, expected)
    }

    func testSavedConversionPreservesIdentityDestinationOrderAndCurrentSelection() throws {
        for kind in [EntryKind.pinned, .favorite] {
            for selected in [false, true] {
                var state = BrowserState.initial()
                let id = try state.addTab(url: saved, title: "Saved")
                if kind == .pinned { try state.pinEntry(id) } else { try state.favoriteEntry(id) }
                try state.recordNavigation(entryID: id, url: navigated, title: "Current title")
                let sibling = try state.addTab(url: saved, title: "Sibling")
                if selected { try state.selectEntry(id) }
                let before = state
                try state.makeTemporary(id)
                XCTAssertTrue(state.profiles[0].favorites.isEmpty)
                XCTAssertTrue(state.currentWorkspace.pins.isEmpty)
                XCTAssertEqual(state.currentWorkspace.tabs.map(\.id), [sibling, id])
                let converted = try XCTUnwrap(state.currentWorkspace.tabs.last)
                XCTAssertEqual(converted, PageEntry(id: id, title: "Current title", lastURL: navigated, kind: .temporary))
                XCTAssertEqual(state.activeWorkspaceID, before.activeWorkspaceID)
                XCTAssertEqual(state.currentWorkspace.activeEntryID, before.currentWorkspace.activeEntryID)
                XCTAssertEqual(state.currentWorkspace.profileID, before.currentWorkspace.profileID)
                let restored = try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(state))
                try restored.validate()
                XCTAssertEqual(restored, state)
            }
        }
    }

    func testRemovedSharedFavoriteBecomesLocalAndOnlyInvalidSelectionsAreCleared() throws {
        var state = BrowserState.initial()
        let owner = state.activeWorkspaceID
        let id = try state.addTab(url: saved, title: "Shared")
        try state.favoriteEntry(id)
        let retained = try state.addTab(url: saved, title: "Retained favorite")
        try state.favoriteEntry(retained)
        try state.selectEntry(id)
        let destination = try state.addWorkspace(name: "Destination", profileID: state.currentWorkspace.profileID)
        try state.activateWorkspace(destination)
        let selected = try state.addTab(url: navigated, title: "Current")
        let unrelated = try state.addWorkspace(name: "Unrelated", profileID: state.currentWorkspace.profileID)
        try state.activateWorkspace(unrelated)
        let unrelatedSelection = try state.addTab(url: saved, title: "Other")
        try state.activateWorkspace(destination)
        let before = state
        try state.makeTemporary(id)
        XCTAssertEqual(state.profiles[0].favorites.map(\.id), [retained])
        XCTAssertEqual(state.currentWorkspace.tabs.map(\.id), [selected, id])
        XCTAssertEqual(state.currentWorkspace.activeEntryID, selected)
        XCTAssertEqual(state.workspaces.first(where: { $0.id == owner })?.activeEntryID, nil)
        XCTAssertEqual(state.workspaces.first(where: { $0.id == unrelated })?.activeEntryID, unrelatedSelection)
        XCTAssertEqual(state.workspaces.map(\.id), before.workspaces.map(\.id))
        XCTAssertEqual(state.workspaces.map(\.profileID), before.workspaces.map(\.profileID))
        try state.activateWorkspace(owner)
        XCTAssertFalse(state.visibleEntries.contains(where: { $0.id == id }))
        try state.validate()
    }

    func testSavedConversionRejectsTemporaryMissingAndInvisibleEntriesAtomically() throws {
        var state = BrowserState.initial()
        let temporary = try state.addTab(url: saved, title: "Temporary")
        let pin = try state.addTab(url: saved, title: "Pin")
        try state.pinEntry(pin)
        let before = state
        XCTAssertThrowsError(try state.makeTemporary(temporary)) { error in
            XCTAssertEqual(error as? BrowserStateError, .invalidEntryOwnership)
        }
        XCTAssertEqual(state, before)
        XCTAssertThrowsError(try state.makeTemporary(UUID()))
        XCTAssertEqual(state, before)
        let other = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        try state.activateWorkspace(other)
        let inactive = state
        XCTAssertThrowsError(try state.makeTemporary(pin)) { error in
            XCTAssertEqual(error as? BrowserStateError, .missingEntry)
        }
        XCTAssertEqual(state, inactive)
    }

    func testExplicitSavedURLUpdateChangesOnlyDestinationForPinsAndFavorites() throws {
        for kind in [EntryKind.pinned, .favorite] {
            var state = BrowserState.initial()
            let id = try state.addTab(url: saved, title: "Saved")
            if kind == .pinned { try state.pinEntry(id) } else { try state.favoriteEntry(id) }
            _ = try state.addTab(url: saved, title: "Sibling")
            try state.recordNavigation(entryID: id, url: navigated, title: "Next")
            let before = state
            XCTAssertEqual(before.visibleEntries.first(where: { $0.id == id })?.savedURL, saved)
            try state.updateSavedURL(id)
            var expected = before
            if kind == .pinned {
                expected.workspaces[0].pins[0].savedURL = navigated
            } else {
                expected.profiles[0].favorites[0].savedURL = navigated
            }
            XCTAssertEqual(state, expected)
            let restored = try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(state))
            XCTAssertEqual(restored, expected)
            try state.closeEntry(id)
            XCTAssertEqual(state.visibleEntries.first(where: { $0.id == id })?.lastURL, navigated)
        }
    }

    func testSavedURLUpdateRejectsTemporaryMissingAndInvisibleEntriesAtomically() throws {
        var state = BrowserState.initial()
        let temporary = try state.addTab(url: saved, title: "Temporary")
        let pin = try state.addTab(url: saved, title: "Pin")
        try state.pinEntry(pin)
        let before = state
        XCTAssertThrowsError(try state.updateSavedURL(temporary)) { error in
            XCTAssertEqual(error as? BrowserStateError, .invalidSavedURL)
        }
        XCTAssertEqual(state, before)
        XCTAssertThrowsError(try state.updateSavedURL(UUID()))
        XCTAssertEqual(state, before)
        let other = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        try state.activateWorkspace(other)
        let inactive = state
        XCTAssertThrowsError(try state.updateSavedURL(pin)) { error in
            XCTAssertEqual(error as? BrowserStateError, .missingEntry)
        }
        XCTAssertEqual(state, inactive)
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
