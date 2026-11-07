import Foundation
import XCTest
@testable import BatoCore

final class BrowserStateTests: XCTestCase {
    private let saved = URL(string: "https://example.invalid/start")!
    private let navigated = URL(string: "https://example.invalid/next")!

    func testFoldersDecodeLegacyAndRoundTripWithoutLosingEntries() throws {
        var state = BrowserState.initial()
        let pin = try state.addTab(url: saved, title: "Saved")
        try state.pinEntry(pin)
        let legacy = try JSONEncoder().encode(state)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
        let workspaces = try XCTUnwrap(json["workspaces"] as? [[String: Any]])
        XCTAssertNil(workspaces[0]["folders"])
        XCTAssertEqual(try JSONDecoder().decode(BrowserState.self, from: legacy).currentWorkspace.folders, [])
        let entry = state.currentWorkspace.pins[0]
        let folder = try state.createFolder(name: "  Reading  ")
        try state.movePin(pin, toFolder: folder)
        try state.renameFolder(folder, name: "  Library  ")
        try state.setFolderCollapsed(folder, collapsed: true)
        let restored = try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(state))
        try restored.validate()
        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.currentWorkspace.folders[0].name, "Library")
        XCTAssertTrue(restored.currentWorkspace.folders[0].isCollapsed)
        XCTAssertEqual(restored.currentWorkspace.pins, [entry])
        XCTAssertEqual(restored.visibleEntries, [entry])
        XCTAssertEqual(restored.searchPages(matching: "Saved").map(\.entryID), [pin])
    }

    func testFolderValidationRejectsDanglingDuplicateAndForeignReferences() throws {
        var state = BrowserState.initial()
        let pin = try state.addTab(url: saved, title: "Pin")
        try state.pinEntry(pin)
        let folder = try state.createFolder(name: "Folder")
        try state.movePin(pin, toFolder: folder)
        for invalidFolders in [
            [PageFolder(name: "Bad", pinIDs: [UUID()])],
            [PageFolder(name: "Bad", pinIDs: [pin, pin])],
            [PageFolder(name: "One", pinIDs: [pin]), PageFolder(name: "Two", pinIDs: [pin])],
            [PageFolder(name: " ")], [PageFolder(name: String(repeating: "x", count: 81))],
            [PageFolder(name: "Line\nBreak")], [PageFolder(name: " Untrimmed")]
        ] {
            var invalid = state
            invalid.workspaces[0].folders = invalidFolders
            XCTAssertThrowsError(try invalid.validate())
        }
        var duplicate = state
        duplicate.workspaces[0].folders[0].id = pin
        XCTAssertThrowsError(try duplicate.validate()) { XCTAssertEqual($0 as? BrowserStateError, .duplicateIdentity) }
        let other = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        try state.activateWorkspace(other)
        let foreign = try state.addTab(url: saved, title: "Foreign")
        try state.pinEntry(foreign)
        state.workspaces[0].folders[0].pinIDs = [foreign]
        XCTAssertThrowsError(try state.validate()) { XCTAssertEqual($0 as? BrowserStateError, .invalidFolder) }
    }

    func testFolderEditsAndDissolvePreserveWholePinsSelectionAndWorkspace() throws {
        var state = BrowserState.initial()
        let first = try state.addTab(url: saved, title: "First")
        try state.pinEntry(first)
        let second = try state.addTab(url: saved, title: "Second")
        try state.pinEntry(second)
        try state.recordNavigation(entryID: second, url: navigated, title: "Navigated")
        let pins = state.currentWorkspace.pins
        let workspaceID = state.activeWorkspaceID
        let one = try state.createFolder(name: "One")
        let two = try state.createFolder(name: "Two")
        try state.movePin(first, toFolder: one)
        try state.movePin(second, toFolder: one)
        try state.movePin(first, toFolder: two)
        XCTAssertEqual(state.currentWorkspace.folders.map(\.pinIDs), [[second], [first]])
        try state.moveFolder(two, direction: .up)
        XCTAssertEqual(state.currentWorkspace.folders.map(\.id), [two, one])
        try state.movePin(first, toFolder: nil)
        XCTAssertNil(state.currentWorkspace.folder(containingPin: first))
        try state.dissolveFolder(one)
        XCTAssertEqual(state.currentWorkspace.pins, pins)
        XCTAssertEqual(state.currentWorkspace.activeEntryID, second)
        XCTAssertEqual(state.activeWorkspaceID, workspaceID)
    }

    func testEntryReorderStaysWithinFolderOrUnfiledGroup() throws {
        var state = BrowserState.initial()
        let ids = try (1...4).map { number in
            let id = try state.addTab(url: saved, title: "Pin \(number)")
            try state.pinEntry(id)
            return id
        }
        let folder = try state.createFolder(name: "Folder")
        try state.movePin(ids[1], toFolder: folder)
        try state.movePin(ids[3], toFolder: folder)
        XCTAssertFalse(state.canMoveEntry(ids[1], direction: .up))
        XCTAssertTrue(state.canMoveEntry(ids[1], direction: .down))
        try state.moveEntry(ids[1], direction: .down)
        XCTAssertEqual(state.currentWorkspace.folders[0].pinIDs, [ids[3], ids[1]])
        try state.moveEntry(ids[2], direction: .up)
        XCTAssertEqual(state.currentWorkspace.pins.map(\.id), [ids[2], ids[1], ids[0], ids[3]])
        XCTAssertEqual(state.currentWorkspace.folders[0].pinIDs, [ids[3], ids[1]])
        XCTAssertFalse(state.canMoveEntry(ids[2], direction: .up))
    }

    func testMovingConvertingAndClosingPinsCleanFolderReferences() throws {
        var state = BrowserState.initial()
        let ids = try (1...3).map { number in
            let id = try state.addTab(url: saved, title: "Pin \(number)")
            try state.pinEntry(id)
            return id
        }
        let folder = try state.createFolder(name: "Folder")
        for id in ids { try state.movePin(id, toFolder: folder) }
        let destination = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        let transferred = state.currentWorkspace.pins[0]
        try state.moveEntry(ids[0], toWorkspace: destination)
        XCTAssertEqual(state.workspaces[1].pins, [transferred])
        XCTAssertEqual(state.currentWorkspace.folders[0].pinIDs, [ids[1], ids[2]])
        try state.makeTemporary(ids[1])
        XCTAssertEqual(state.currentWorkspace.folders[0].pinIDs, [ids[2]])
        try state.closeEntry(ids[2]) // Unloading a saved entry retains its container.
        XCTAssertEqual(state.currentWorkspace.folders[0].pinIDs, [ids[2]])
        try state.favoriteEntry(ids[2])
        XCTAssertTrue(state.currentWorkspace.folders[0].pinIDs.isEmpty)
        try state.validate()
    }

    func testRejectedFolderCommandsAreAtomicAndCurrentWorkspaceScoped() throws {
        var state = BrowserState.initial()
        let folder = try state.createFolder(name: "Valid")
        let before = state
        XCTAssertThrowsError(try state.renameFolder(folder, name: " "))
        XCTAssertThrowsError(try state.createFolder(name: String(repeating: "x", count: 81)))
        XCTAssertThrowsError(try state.moveFolder(folder, direction: .up))
        XCTAssertThrowsError(try state.movePin(UUID(), toFolder: folder))
        XCTAssertEqual(state, before)
        let other = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        try state.activateWorkspace(other)
        let inactive = state
        XCTAssertThrowsError(try state.renameFolder(folder, name: "Changed"))
        XCTAssertThrowsError(try state.dissolveFolder(folder))
        XCTAssertEqual(state, inactive)
    }

    func testFirstLaunchIsEmptyAndValid() throws {
        let state = BrowserState.initial()
        try state.validate()
        XCTAssertEqual(state.profiles.count, 1)
        XCTAssertEqual(state.workspaces.count, 1)
        XCTAssertEqual(state.currentWorkspace.profileID, state.profiles[0].id)
        XCTAssertTrue(state.visibleEntries.isEmpty)
        XCTAssertNil(state.currentWorkspace.activeEntryID)
    }

    func testPageSearchPreservesOrganizationAndMatchesAllFieldsWithinCurrentProfile() throws {
        var state = BrowserState.initial()
        let first = state.activeWorkspaceID
        let profile = state.currentWorkspace.profileID
        let favorite = try state.addTab(url: URL(string: "https://favorite.invalid/")!, title: "Café Notes")
        try state.favoriteEntry(favorite)
        let pin = try state.addTab(url: URL(string: "https://saved-only.invalid/")!, title: "Pinned")
        try state.pinEntry(pin)
        try state.recordNavigation(entryID: pin, url: URL(string: "https://latest-only.invalid/")!, title: "Pinned")
        let tab = try state.addTab(url: saved, title: "First temporary")
        let second = try state.addWorkspace(name: "Résearch", profileID: profile)
        try state.activateWorkspace(second)
        let other = try state.addTab(url: navigated, title: "Second temporary")
        let foreignProfile = try state.addProfile(name: "Foreign")
        let foreign = try state.addWorkspace(name: "Foreign", profileID: foreignProfile)
        try state.activateWorkspace(foreign)
        let hidden = try state.addTab(url: saved, title: "Foreign secret")
        try state.favoriteEntry(hidden)
        try state.activateWorkspace(second)
        let before = state

        let all = state.searchPages(matching: "  \n ")
        XCTAssertEqual(all.map(\.id), [favorite, pin, tab, other])
        XCTAssertEqual(all.map(\.workspaceID), [second, first, first, second])
        XCTAssertEqual(all[0].workspaceName, "Résearch")
        XCTAssertEqual(all[0].entryID, favorite)
        XCTAssertEqual(all[0].entry, state.profiles[0].favorites[0])
        XCTAssertEqual(state.searchPages(matching: "  CAFE \n").map(\.id), [favorite])
        XCTAssertEqual(state.searchPages(matching: "SAVED-ONLY").map(\.id), [pin])
        XCTAssertEqual(state.searchPages(matching: "latest-only").map(\.id), [pin])
        XCTAssertEqual(state.searchPages(matching: "research").map(\.id), [favorite, other])
        XCTAssertTrue(state.searchPages(matching: "Foreign").isEmpty)
        XCTAssertEqual(state, before)
    }

    func testAtomicPageActivationRejectsStaleTargetsAndPreservesAllOtherState() throws {
        var state = BrowserState.initial()
        let source = state.activeWorkspaceID
        let current = try state.addTab(url: saved, title: "Source current")
        let favorite = try state.addTab(url: saved, title: "Shared")
        try state.favoriteEntry(favorite)
        try state.selectEntry(current)
        let destination = try state.addWorkspace(name: "Destination", profileID: state.currentWorkspace.profileID)
        try state.activateWorkspace(destination)
        let target = try state.addTab(url: navigated, title: "Target")
        let foreignProfile = try state.addProfile(name: "Foreign")
        let foreign = try state.addWorkspace(name: "Foreign", profileID: foreignProfile)
        try state.activateWorkspace(source)
        let before = state
        for (entry, workspace, expected) in [
            (target, UUID(), BrowserStateError.missingWorkspace),
            (target, source, .missingEntry), (UUID(), destination, .missingEntry),
            (target, foreign, .invalidSelection)
        ] {
            XCTAssertThrowsError(try state.activateEntry(entry, inWorkspace: workspace)) {
                XCTAssertEqual($0 as? BrowserStateError, expected)
            }
            XCTAssertEqual(state, before)
        }
        try state.activateEntry(target, inWorkspace: destination)
        var expected = before
        expected.activeWorkspaceID = destination
        expected.workspaces[1].activeEntryID = target
        XCTAssertEqual(state, expected)
        try state.activateEntry(favorite, inWorkspace: destination)
        expected.workspaces[1].activeEntryID = favorite
        XCTAssertEqual(state, expected)
        let decoded = try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(state))
        try decoded.validate()
        XCTAssertEqual(decoded, expected)
    }

    func testEntryTransferPreservesFullEntryAndBothWorkspaceSelections() throws {
        for kind in [EntryKind.pinned, .temporary] {
            for selected in [false, true] {
                var state = BrowserState.initial()
                let source = state.activeWorkspaceID
                let profile = state.currentWorkspace.profileID
                let moved = try state.addTab(url: saved, title: "Moved page")
                if kind == .pinned { try state.pinEntry(moved) }
                try state.recordNavigation(entryID: moved, url: navigated, title: "Latest title")
                let retained = try state.addTab(url: saved, title: "Retained source page")
                if selected { try state.selectEntry(moved) }
                let destination = try state.addWorkspace(name: "Destination", profileID: profile)
                try state.activateWorkspace(destination)
                let existing = try state.addTab(url: saved, title: "Destination selection")
                if kind == .pinned { try state.pinEntry(existing) }
                try state.activateWorkspace(source)
                let before = state
                let entry = try XCTUnwrap(state.visibleEntries.first(where: { $0.id == moved }))
                XCTAssertTrue(state.canMoveEntry(moved, toWorkspace: destination))
                try state.moveEntry(moved, toWorkspace: destination)
                var expected = before
                if kind == .pinned {
                    expected.workspaces[0].pins.removeAll { $0.id == moved }
                    expected.workspaces[1].pins.append(entry)
                } else {
                    expected.workspaces[0].tabs.removeAll { $0.id == moved }
                    expected.workspaces[1].tabs.append(entry)
                }
                expected.workspaces[0].activeEntryID = selected ? nil : retained
                XCTAssertEqual(state, expected)
                XCTAssertEqual(state.workspaces[1].activeEntryID, existing)
                let decoded = try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(state))
                try decoded.validate()
                XCTAssertEqual(decoded, expected)
                XCTAssertFalse(state.canMoveEntry(moved, toWorkspace: destination))
            }
        }
    }

    func testEntryTransferRejectsInvalidOwnershipAndDestinationsAtomically() throws {
        var state = BrowserState.initial()
        let source = state.activeWorkspaceID
        let pin = try state.addTab(url: saved, title: "Pin")
        try state.pinEntry(pin)
        let favorite = try state.addTab(url: saved, title: "Favorite")
        try state.favoriteEntry(favorite)
        let destination = try state.addWorkspace(name: "Destination", profileID: state.currentWorkspace.profileID)
        try state.activateWorkspace(destination)
        let invisible = try state.addTab(url: saved, title: "Destination-only tab")
        let otherProfile = try state.addProfile(name: "Other Profile")
        let isolated = try state.addWorkspace(name: "Isolated", profileID: otherProfile)
        try state.activateWorkspace(source)
        let before = state
        let cases: [(UUID, UUID, BrowserStateError)] = [
            (pin, source, .invalidSelection), (pin, isolated, .invalidSelection),
            (pin, UUID(), .missingWorkspace), (UUID(), destination, .missingEntry),
            (invisible, destination, .missingEntry), (favorite, destination, .invalidEntryOwnership)
        ]
        for (id, target, expectedError) in cases {
            XCTAssertFalse(state.canMoveEntry(id, toWorkspace: target))
            XCTAssertThrowsError(try state.moveEntry(id, toWorkspace: target)) { error in
                XCTAssertEqual(error as? BrowserStateError, expectedError)
            }
            XCTAssertEqual(state, before)
        }
    }

    func testWorkspaceOrderingPreservesFullOrganizationAcrossProfilesAndRoundTrips() throws {
        var state = BrowserState.initial()
        let first = state.activeWorkspaceID
        let profile = state.currentWorkspace.profileID
        let favorite = try state.addTab(url: saved, title: "Shared favorite")
        try state.favoriteEntry(favorite)
        let pin = try state.addTab(url: saved, title: "Saved page")
        try state.pinEntry(pin)
        try state.recordNavigation(entryID: pin, url: navigated, title: "Navigated pin")
        let second = try state.addWorkspace(name: "Research", profileID: profile)
        try state.activateWorkspace(second)
        try state.selectEntry(favorite)
        let isolatedProfile = try state.addProfile(name: "Isolated")
        let third = try state.addWorkspace(name: "Isolated", profileID: isolatedProfile)
        try state.activateWorkspace(third)
        _ = try state.addTab(url: navigated, title: "Isolated temporary")
        try state.activateWorkspace(second)
        let before = state

        XCTAssertTrue(state.canMoveWorkspace(first, direction: .down))
        try state.moveWorkspace(first, direction: .down)
        var expected = before
        expected.workspaces.swapAt(0, 1)
        XCTAssertEqual(state, expected)
        // Global order may cross Profile boundaries without rebinding either workspace.
        try state.moveWorkspace(third, direction: .up)
        expected.workspaces.swapAt(1, 2)
        XCTAssertEqual(state, expected)
        let restored = try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(state))
        try restored.validate()
        XCTAssertEqual(restored, expected)
        try state.moveWorkspace(third, direction: .down)
        try state.moveWorkspace(first, direction: .up)
        XCTAssertEqual(state, before)
    }

    func testWorkspaceOrderingRejectsMissingAndBoundaryMovesAtomically() throws {
        var state = BrowserState.initial()
        let first = state.activeWorkspaceID
        let initial = state
        for direction in [WorkspaceMoveDirection.up, .down] {
            XCTAssertFalse(state.canMoveWorkspace(first, direction: direction))
            XCTAssertThrowsError(try state.moveWorkspace(first, direction: direction)) { error in
                XCTAssertEqual(error as? BrowserStateError, .invalidSelection)
            }
            XCTAssertEqual(state, initial)
        }
        let last = try state.addWorkspace(name: "Last", profileID: state.currentWorkspace.profileID)
        let before = state
        for (id, direction) in [(first, WorkspaceMoveDirection.up), (last, .down)] {
            XCTAssertFalse(state.canMoveWorkspace(id, direction: direction))
            XCTAssertThrowsError(try state.moveWorkspace(id, direction: direction)) { error in
                XCTAssertEqual(error as? BrowserStateError, .invalidSelection)
            }
            XCTAssertEqual(state, before)
        }
        let missing = UUID()
        for direction in [WorkspaceMoveDirection.up, .down] {
            XCTAssertFalse(state.canMoveWorkspace(missing, direction: direction))
            XCTAssertThrowsError(try state.moveWorkspace(missing, direction: direction)) { error in
                XCTAssertEqual(error as? BrowserStateError, .missingWorkspace)
            }
            XCTAssertEqual(state, before)
        }
    }

    func testAdjacentOrderingChangesOnlyItsSectionAndRoundTrips() throws {
        for kind in [EntryKind.favorite, .pinned, .temporary] {
            var state = BrowserState.initial()
            var ids: [UUID] = []
            for title in ["First", "Second"] {
                let id = try state.addTab(url: saved, title: title)
                if kind == .favorite { try state.favoriteEntry(id) }
                if kind == .pinned { try state.pinEntry(id) }
                ids.append(id)
            }
            _ = try state.addTab(url: navigated, title: "Selected sibling")
            let before = state
            XCTAssertTrue(state.canMoveEntry(ids[0], direction: .down))
            try state.moveEntry(ids[0], direction: .down)
            var expected = before
            switch kind {
            case .favorite: expected.profiles[0].favorites.swapAt(0, 1)
            case .pinned: expected.workspaces[0].pins.swapAt(0, 1)
            case .temporary: expected.workspaces[0].tabs.swapAt(0, 1)
            }
            XCTAssertEqual(state, expected)
            let restored = try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(state))
            try restored.validate()
            XCTAssertEqual(restored, expected)
            try state.moveEntry(ids[0], direction: .up)
            XCTAssertEqual(state, before)
        }
    }

    func testSharedFavoriteOrderPreservesEveryWorkspaceSelection() throws {
        var state = BrowserState.initial()
        let first = try state.addTab(url: saved, title: "First")
        try state.favoriteEntry(first)
        let second = try state.addTab(url: navigated, title: "Second")
        try state.favoriteEntry(second)
        let owner = state.activeWorkspaceID
        let other = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        try state.activateWorkspace(other)
        try state.selectEntry(first)
        let before = state
        try state.moveEntry(second, direction: .up)
        var expected = before
        expected.profiles[0].favorites.swapAt(0, 1)
        XCTAssertEqual(state, expected)
        XCTAssertEqual(state.visibleEntries.map(\.id), [second, first])
        try state.activateWorkspace(owner)
        XCTAssertEqual(state.visibleEntries.map(\.id), [second, first])
        XCTAssertEqual(state.currentWorkspace.activeEntryID, second)
    }

    func testOrderingRejectsBoundariesMissingAndInvisibleEntriesAtomically() throws {
        var state = BrowserState.initial()
        let favorite = try state.addTab(url: saved, title: "Favorite")
        try state.favoriteEntry(favorite)
        let pin = try state.addTab(url: saved, title: "Pin")
        try state.pinEntry(pin)
        let tab = try state.addTab(url: navigated, title: "Tab")
        let before = state
        // Adjacent entries in other sections do not make a move legal.
        for id in [favorite, pin, tab] {
            for direction in [EntryMoveDirection.up, .down] {
                XCTAssertFalse(state.canMoveEntry(id, direction: direction))
                XCTAssertThrowsError(try state.moveEntry(id, direction: direction))
                XCTAssertEqual(state, before)
            }
        }
        let other = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        try state.activateWorkspace(other)
        let inactive = state
        for id in [pin, tab, UUID()] {
            XCTAssertFalse(state.canMoveEntry(id, direction: .up))
            XCTAssertThrowsError(try state.moveEntry(id, direction: .up))
            XCTAssertEqual(state, inactive)
        }
        let isolatedProfile = try state.addProfile(name: "Isolated")
        let isolated = try state.addWorkspace(name: "Isolated", profileID: isolatedProfile)
        try state.activateWorkspace(isolated)
        let isolatedState = state
        XCTAssertFalse(state.canMoveEntry(favorite, direction: .down))
        XCTAssertThrowsError(try state.moveEntry(favorite, direction: .down))
        XCTAssertEqual(state, isolatedState)
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
                XCTAssertEqual(converted, PageEntry(id: id, title: "Saved", lastURL: navigated, kind: .temporary))
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
        json["version"] = 3
        let future = try JSONDecoder().decode(BrowserState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try future.validate()) { error in
            XCTAssertEqual(error as? BrowserStateError, .unsupportedVersion(3))
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

extension BrowserStateTests {
    func testSplitLegacyRoundTripValidationAndSelection() throws {
        var state = BrowserState.initial()
        let left = try state.addTab(url: saved, title: "Left")
        let right = try state.addTab(url: navigated, title: "Right")
        let legacy = try JSONEncoder().encode(state)
        XCTAssertFalse(String(decoding: legacy, as: UTF8.self).contains("splits"))
        XCTAssertEqual(try JSONDecoder().decode(BrowserState.self, from: legacy).currentWorkspace.splits, [])
        try state.selectEntry(left)
        let id = try state.createSplit(with: right)
        XCTAssertEqual(state.currentSplit?.id, id)
        try state.selectEntry(right)
        XCTAssertEqual(state.currentSplit?.id, id)
        XCTAssertEqual(state.currentWorkspace.activeEntryID, right)
        let paired = state
        XCTAssertThrowsError(try state.createSplit(with: left))
        XCTAssertEqual(state, paired)
        for invalid in [Double.nan, Double.infinity, 0, 1] {
            XCTAssertThrowsError(try state.updateSplitRatio(id, ratio: invalid))
            XCTAssertEqual(state, paired)
        }
        try state.updateSplitRatio(id, ratio: 0.65)
        XCTAssertEqual(try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(state)), state)
        try state.pinSplit(id)
        let unrelated = try state.addTab(url: saved, title: "Other")
        XCTAssertNil(state.currentSplit)
        XCTAssertEqual(state.currentWorkspace.splits.count, 1)
        try state.activateSplit(id, focusedEntryID: left)
        XCTAssertEqual(state.currentWorkspace.activeEntryID, left)
        try state.selectEntry(unrelated)
        XCTAssertNil(state.currentSplit)
        try state.validate()
    }

    func testSplitRejectsFavoritesForeignMembersAndDuplicateReferences() throws {
        var state = BrowserState.initial()
        let favorite = try state.addTab(url: saved, title: "Favorite")
        try state.favoriteEntry(favorite)
        let left = try state.addTab(url: saved, title: "Left")
        XCTAssertFalse(state.canCreateSplit(with: favorite))
        XCTAssertThrowsError(try state.createSplit(with: favorite))
        let right = try state.addTab(url: navigated, title: "Right")
        let pair = try state.createSplit(with: left)
        var invalid = state
        invalid.workspaces[0].splits[0].rightEntryID = UUID()
        XCTAssertThrowsError(try invalid.validate())
        invalid = state
        invalid.workspaces[0].splits.append(PageSplit(leftEntryID: left, rightEntryID: right))
        XCTAssertThrowsError(try invalid.validate())
        invalid = state
        invalid.workspaces[0].splits[0].id = left
        XCTAssertThrowsError(try invalid.validate())
        XCTAssertEqual(state.currentSplit?.id, pair)
    }

    func testPinSplitPreservesSavedDestinationsAndSavedCloseKeepsPair() throws {
        var state = BrowserState.initial()
        let left = try state.addTab(url: saved, title: "Saved")
        try state.pinEntry(left)
        try state.recordNavigation(entryID: left, url: navigated, title: "Moved")
        let right = try state.addTab(url: navigated, title: "Temporary")
        let id = try state.createSplit(with: left)
        try state.pinSplit(id)
        XCTAssertEqual(state.currentWorkspace.tabs.count, 0)
        XCTAssertEqual(state.currentWorkspace.pins.first(where: { $0.id == left })?.savedURL, saved)
        XCTAssertEqual(state.currentWorkspace.pins.first(where: { $0.id == right })?.savedURL, navigated)
        XCTAssertTrue(try XCTUnwrap(state.currentSplit).isPinned)
        try state.closeEntry(right)
        XCTAssertNil(state.currentSplit)
        XCTAssertEqual(state.currentWorkspace.activeEntryID, left)
        XCTAssertEqual(state.currentWorkspace.splits.count, 1)
        try state.activateSplit(id)
        try state.dissolveSplit(id)
        XCTAssertEqual(state.currentWorkspace.pins.count, 2)
    }

    func testTemporaryCloseAndTransferRemoveSplitWithoutLosingSurvivor() throws {
        var state = BrowserState.initial()
        let left = try state.addTab(url: saved, title: "Left")
        let right = try state.addTab(url: navigated, title: "Right")
        _ = try state.createSplit(with: left)
        try state.closeEntry(right)
        XCTAssertTrue(state.currentWorkspace.splits.isEmpty)
        XCTAssertEqual(state.currentWorkspace.activeEntryID, left)
        let replacement = try state.addTab(url: navigated, title: "Replacement")
        _ = try state.createSplit(with: left)
        let destination = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        try state.moveEntry(replacement, toWorkspace: destination)
        XCTAssertTrue(state.currentWorkspace.splits.isEmpty)
        XCTAssertEqual(state.currentWorkspace.activeEntryID, left)
        XCTAssertEqual(state.workspaces.first(where: { $0.id == destination })?.tabs.first?.id, replacement)
    }
}

extension BrowserStateTests {
    func testUnpinnedPairIsDiscardedWhenLeavingAndSavedPairCanRestore() throws {
        var state = BrowserState.initial()
        let left = try state.addTab(url: saved, title: "Left")
        let right = try state.addTab(url: saved, title: "Right")
        _ = try state.createSplit(with: left)
        try state.deactivateSplit()
        XCTAssertTrue(state.currentWorkspace.splits.isEmpty)
        XCTAssertTrue(state.canCreateSplit(with: left))
        _ = try state.createSplit(with: left)
        _ = try state.addTab(url: saved, title: "Unrelated")
        XCTAssertTrue(state.currentWorkspace.splits.isEmpty)
        try state.selectEntry(right)
        let pair = try state.createSplit(with: left)
        try state.pinSplit(pair)
        try state.deactivateSplit()
        XCTAssertEqual(state.currentWorkspace.splits.count, 1)
        try state.activateSplit(pair)
        try state.updateSplitRatio(pair, ratio: 0.05)
        XCTAssertEqual(state.currentSplit?.dividerRatio, 0.05)
    }
}

extension BrowserStateTests {
    func testActivatingSavedPairDiscardsPreviousTransientPair() throws {
        var state = BrowserState.initial()
        let first = try state.addTab(url: saved, title: "One")
        let second = try state.addTab(url: saved, title: "Two")
        let savedPair = try state.createSplit(with: first)
        try state.pinSplit(savedPair)
        let third = try state.addTab(url: saved, title: "Three")
        _ = try state.addTab(url: saved, title: "Four")
        let transient = try state.createSplit(with: third)
        try state.activateSplit(savedPair, focusedEntryID: second)
        XCTAssertEqual(state.currentSplit?.id, savedPair)
        XCTAssertFalse(state.currentWorkspace.splits.contains { $0.id == transient })
        XCTAssertEqual(state.currentWorkspace.splits.count, 1)
    }
}

extension BrowserStateTests {
    private func pinned(_ state: inout BrowserState, _ count: Int) throws -> [UUID] {
        try (0..<count).map { index in
            let id = try state.addTab(url: saved, title: "Pin \(index)")
            try state.pinEntry(id)
            return id
        }
    }

    func testNestedFoldersKeepFlatDocumentsAtVersionOneAndUpgradeOnNesting() throws {
        var state = BrowserState.initial()
        let top = try state.createFolder(name: "Top")
        XCTAssertEqual(state.version, 1)
        XCTAssertNil(state.currentWorkspace.folder(top)?.parentID)
        let sub = try state.createFolder(name: "Sub", parentID: top)
        XCTAssertEqual(state.version, 2)
        let restored = try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.currentWorkspace.subfolders(of: top).map(\.id), [sub])
        XCTAssertEqual(restored.currentWorkspace.depth(ofFolder: sub), 2)
        var legacy = state
        legacy.version = 1
        XCTAssertThrowsError(try legacy.validate()) { XCTAssertEqual($0 as? BrowserStateError, .unsupportedVersion(1)) }
    }

    func testFolderDepthLimitAppliesToCreationAndMoves() throws {
        var state = BrowserState.initial()
        var parent: UUID?
        var chain: [UUID] = []
        for level in 1...BrowserState.maxFolderDepth {
            parent = try state.createFolder(name: "L\(level)", parentID: parent)
            chain.append(parent!)
        }
        XCTAssertThrowsError(try state.createFolder(name: "Too deep", parentID: chain.last))
        let loose = try state.createFolder(name: "Loose")
        let looseChild = try state.createFolder(name: "Loose child", parentID: loose)
        XCTAssertFalse(state.canMoveFolder(loose, toParent: chain[BrowserState.maxFolderDepth - 2]))
        XCTAssertThrowsError(try state.moveFolder(loose, toParent: chain.last))
        XCTAssertTrue(state.canMoveFolder(looseChild, toParent: chain[BrowserState.maxFolderDepth - 2]))
        XCTAssertEqual(state.currentWorkspace.folder(looseChild)?.parentID, loose)
        var tooDeep = state
        tooDeep.workspaces[0].folders[0].parentID = chain.last
        XCTAssertThrowsError(try tooDeep.validate())
    }

    func testFolderMovesRejectCyclesAndDanglingParentsAtomically() throws {
        var state = BrowserState.initial()
        let a = try state.createFolder(name: "A")
        let b = try state.createFolder(name: "B", parentID: a)
        let c = try state.createFolder(name: "C", parentID: b)
        let before = state
        XCTAssertThrowsError(try state.moveFolder(a, toParent: a))
        XCTAssertThrowsError(try state.moveFolder(a, toParent: c))
        XCTAssertThrowsError(try state.moveFolder(b, toParent: c))
        XCTAssertThrowsError(try state.moveFolder(a, toParent: UUID()))
        XCTAssertThrowsError(try state.moveFolder(c, toParent: UUID()))
        XCTAssertFalse(state.canMoveFolder(a, toParent: nil))
        XCTAssertEqual(state, before)
        var cyclic = state
        cyclic.workspaces[0].folders[0].parentID = c
        XCTAssertThrowsError(try cyclic.validate()) { XCTAssertEqual($0 as? BrowserStateError, .invalidFolder) }
        var dangling = state
        dangling.workspaces[0].folders[1].parentID = UUID()
        XCTAssertThrowsError(try dangling.validate()) { XCTAssertEqual($0 as? BrowserStateError, .invalidFolder) }
        var selfParent = state
        selfParent.workspaces[0].folders[0].parentID = a
        XCTAssertThrowsError(try selfParent.validate())
    }

    func testMovingFoldersReparentsAppendsAndExpandsDestination() throws {
        var state = BrowserState.initial()
        let a = try state.createFolder(name: "A")
        let b = try state.createFolder(name: "B")
        let c = try state.createFolder(name: "C", parentID: a)
        try state.setFolderCollapsed(b, collapsed: true)
        try state.moveFolder(a, toParent: b)
        XCTAssertEqual(state.currentWorkspace.subfolders(of: b).map(\.id), [a])
        XCTAssertEqual(state.currentWorkspace.subfolders(of: a).map(\.id), [c])
        XCTAssertEqual(state.currentWorkspace.folder(b)?.isCollapsed, false)
        XCTAssertEqual(state.currentWorkspace.depth(ofFolder: c), 3)
        try state.moveFolder(c, toParent: nil)
        XCTAssertEqual(state.currentWorkspace.subfolders(of: nil).map(\.id), [b, c])
        XCTAssertFalse(state.canMoveFolder(c, toParent: nil))
    }

    func testFolderOrderingMovesAmongSiblingsOnly() throws {
        var state = BrowserState.initial()
        let a = try state.createFolder(name: "A")
        let a1 = try state.createFolder(name: "A1", parentID: a)
        let b = try state.createFolder(name: "B")
        let a2 = try state.createFolder(name: "A2", parentID: a)
        XCTAssertTrue(state.canMoveFolder(a, direction: .down))
        XCTAssertFalse(state.canMoveFolder(a, direction: .up))
        XCTAssertFalse(state.canMoveFolder(b, direction: .down))
        try state.moveFolder(a, direction: .down)
        XCTAssertEqual(state.currentWorkspace.subfolders(of: nil).map(\.id), [b, a])
        XCTAssertEqual(state.currentWorkspace.subfolders(of: a).map(\.id), [a1, a2])
        try state.moveFolder(a2, direction: .up)
        XCTAssertEqual(state.currentWorkspace.subfolders(of: a).map(\.id), [a2, a1])
        XCTAssertThrowsError(try state.moveFolder(a1, direction: .down))
    }

    func testDissolveMovesChildrenUpOneLevelPreservingOrder() throws {
        var state = BrowserState.initial()
        let pins = try pinned(&state, 3)
        let before = try state.createFolder(name: "Before")
        let middle = try state.createFolder(name: "Middle")
        let after = try state.createFolder(name: "After")
        let one = try state.createFolder(name: "One", parentID: middle)
        let two = try state.createFolder(name: "Two", parentID: middle)
        let deep = try state.createFolder(name: "Deep", parentID: one)
        try state.movePin(pins[0], toFolder: middle)
        try state.movePin(pins[1], toFolder: middle)
        try state.dissolveFolder(middle)
        XCTAssertEqual(state.currentWorkspace.subfolders(of: nil).map(\.id), [before, one, two, after])
        XCTAssertEqual(state.currentWorkspace.subfolders(of: one).map(\.id), [deep])
        XCTAssertNil(state.currentWorkspace.folder(containingPin: pins[0]))
        XCTAssertEqual(state.currentWorkspace.pins.map(\.id), pins)

        let outer = try state.createFolder(name: "Outer")
        let inner = try state.createFolder(name: "Inner", parentID: outer)
        let leaf = try state.createFolder(name: "Leaf", parentID: inner)
        try state.movePin(pins[2], toFolder: outer)
        try state.movePin(pins[0], toFolder: inner)
        try state.movePin(pins[1], toFolder: inner)
        try state.dissolveFolder(inner)
        XCTAssertEqual(state.currentWorkspace.folder(outer)?.pinIDs, [pins[2], pins[0], pins[1]])
        XCTAssertEqual(state.currentWorkspace.subfolders(of: outer).map(\.id), [leaf])
        XCTAssertNil(state.currentWorkspace.folder(inner))
    }

    func testPinOperationsKeepNestedFolderReferencesConsistent() throws {
        var state = BrowserState.initial()
        let pins = try pinned(&state, 3)
        let outer = try state.createFolder(name: "Outer")
        let inner = try state.createFolder(name: "Inner", parentID: outer)
        try state.movePin(pins[0], toFolder: outer)
        try state.movePin(pins[1], toFolder: inner)
        try state.movePin(pins[2], toFolder: inner)
        XCTAssertEqual(state.currentWorkspace.pinCount(inFolder: outer), 3)
        try state.movePin(pins[1], toFolder: outer)
        XCTAssertEqual(state.currentWorkspace.folder(inner)?.pinIDs, [pins[2]])
        XCTAssertEqual(state.currentWorkspace.folder(outer)?.pinIDs, [pins[0], pins[1]])
        try state.makeTemporary(pins[2])
        XCTAssertEqual(state.currentWorkspace.folder(inner)?.pinIDs, [])
        try state.favoriteEntry(pins[0])
        XCTAssertEqual(state.currentWorkspace.folder(outer)?.pinIDs, [pins[1]])
        let other = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        try state.moveEntry(pins[1], toWorkspace: other)
        XCTAssertEqual(state.currentWorkspace.folder(outer)?.pinIDs, [])
        try state.validate()
        XCTAssertThrowsError(try state.moveFolder(outer, toParent: inner))
    }

    func testNestedFoldersStayScopedToTheirWorkspace() throws {
        var state = BrowserState.initial()
        let parent = try state.createFolder(name: "Parent")
        let other = try state.addWorkspace(name: "Other", profileID: state.currentWorkspace.profileID)
        try state.activateWorkspace(other)
        XCTAssertThrowsError(try state.createFolder(name: "Foreign", parentID: parent)) {
            XCTAssertEqual($0 as? BrowserStateError, .missingFolder)
        }
        var forged = state
        forged.workspaces[1].folders = [PageFolder(name: "Forged", parentID: parent)]
        forged.version = 2
        XCTAssertThrowsError(try forged.validate()) { XCTAssertEqual($0 as? BrowserStateError, .invalidFolder) }
    }

    func testFolderOutlineListsDepthFirstWithDepths() throws {
        var state = BrowserState.initial()
        let a = try state.createFolder(name: "A")
        let b = try state.createFolder(name: "B")
        let a1 = try state.createFolder(name: "A1", parentID: a)
        let a1x = try state.createFolder(name: "A1x", parentID: a1)
        let a2 = try state.createFolder(name: "A2", parentID: a)
        let outline = state.currentWorkspace.folderOutline()
        XCTAssertEqual(outline.map(\.folder.id), [a, a1, a1x, a2, b])
        XCTAssertEqual(outline.map(\.depth), [1, 2, 3, 2, 1])
    }

    func testNavigationRetitlesTemporaryTabsButSavedEntriesKeepTheirTitle() throws {
        var state = BrowserState.initial()
        let favorite = try state.addTab(url: saved, title: "Saved favorite")
        try state.favoriteEntry(favorite)
        let pin = try state.addTab(url: saved, title: "Saved pin")
        try state.pinEntry(pin)
        let tab = try state.addTab(url: saved, title: "Opening title")
        for id in [favorite, pin, tab] {
            try state.recordNavigation(entryID: id, url: navigated, title: "Page title")
        }
        let titles = Dictionary(uniqueKeysWithValues: state.visibleEntries.map { ($0.id, $0.title) })
        XCTAssertEqual(titles[favorite], "Saved favorite")
        XCTAssertEqual(titles[pin], "Saved pin")
        XCTAssertEqual(titles[tab], "Page title")
        XCTAssertEqual(state.visibleEntries.first { $0.id == pin }?.lastURL, navigated)
        XCTAssertEqual(state.visibleEntries.first { $0.id == pin }?.savedURL, saved)
    }

    func testPinnedTemporaryTabKeepsTheTitleItHadWhenPinned() throws {
        var state = BrowserState.initial()
        let tab = try state.addTab(url: saved, title: "Title at pinning")
        try state.recordNavigation(entryID: tab, url: navigated, title: "Title at pinning")
        try state.pinEntry(tab)
        try state.recordNavigation(entryID: tab, url: saved, title: "Later page title")
        XCTAssertEqual(state.visibleEntries.first { $0.id == tab }?.title, "Title at pinning")
    }
}
