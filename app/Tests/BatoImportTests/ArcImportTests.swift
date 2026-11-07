import BatoCore
import Foundation
import XCTest
@testable import BatoImport

final class ArcImportTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("spikes/arc-import/fixtures/\(name).json"))
    }

    private func parseBasic() throws -> ArcStaging {
        try ArcSidebarParser.parse(fixture("basic"))
    }

    private func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func sidebar(items: [Any], spaces: [Any]) -> [String: Any] {
        ["sidebar": ["containers": [["spaces": spaces, "items": items]]]]
    }

    private func tab(_ id: String, _ url: String) -> [Any] {
        [id, ["id": id, "childrenIds": [String](), "data": ["tab": ["savedURL": url, "savedTitle": id]]]]
    }

    func testBothMapFormsParseIdentically() throws {
        let alternating = try ArcSidebarParser.parse(fixture("basic"))
        let objects = try ArcSidebarParser.parse(fixture("basic-objects"))
        XCTAssertEqual(alternating.profiles, objects.profiles)
        XCTAssertEqual(alternating.spaces, objects.spaces)
        XCTAssertEqual(alternating.warnings, objects.warnings)
    }

    func testObjectMapFormParsesInKeyOrder() throws {
        let item = ["P": ["id": "P", "childrenIds": ["t"], "data": ["itemContainer": [:]]],
                    "t": ["id": "t", "childrenIds": [String](), "data": ["tab": ["savedURL": "https://example.test/x"]]]]
        let spaces = ["B": ["title": "Second", "containerIDs": ["pinned", "P"]],
                      "A": ["title": "First", "containerIDs": ["pinned", "P"]]]
        let staging = try ArcSidebarParser.parse(json(
            ["sidebar": ["containers": [["spaces": spaces, "items": item]]]]))
        XCTAssertEqual(staging.spaces.map(\.title), ["First", "Second"])
    }

    func testProfilesSpacesAndFavorites() throws {
        let staging = try parseBasic()
        XCTAssertEqual(staging.profiles.map(\.name), ["Arc", "Arc - Profile 1"])
        XCTAssertEqual(staging.spaces.map(\.title), ["Work", "Space 2", "Side"])
        XCTAssertEqual(staging.spaces.map(\.profileKey), ["default", "default", "custom:Profile 1"])
        XCTAssertEqual(staging.spaces.map(\.colorHex), ["#FF8000", nil, nil])
        XCTAssertEqual(staging.profiles[0].favorites.map(\.title), ["Fav one", "Fav two"])
        XCTAssertEqual(staging.profiles[1].favorites.map(\.title), ["Fav custom"])
        XCTAssertEqual(staging.spaces[1].today.count, 2)
        XCTAssertEqual(staging.sourceDigest.count, 64)
    }

    func testFoldersAreHoistedAtMaxDepthAndKeepOrder() throws {
        let work = try parseBasic().spaces[0]
        guard case .folder(let reading) = work.pinned[1],
              case .folder(let level2) = reading.children[1],
              case .folder(let level3) = level2.children[0],
              case .folder(let level4) = level3.children[0] else { return XCTFail("folder chain missing") }
        XCTAssertEqual(reading.name, "Reading")
        XCTAssertEqual(level4.name, "L4")
        XCTAssertEqual(level4.children.map { if case .page(let page) = $0 { page.title } else { "folder" } },
                       ["Deep five", "Deep four"])
    }

    func testSplitsKeepTwoChildrenAndFlattenLargerOnes() throws {
        let work = try parseBasic().spaces[0]
        let splits = work.pinned.compactMap { node -> ArcSplit? in if case .split(let split) = node { split } else { nil } }
        XCTAssertEqual(splits.map { [$0.first.title, $0.second.title] }, [["Left", "Right"]])
        let titles = work.pinned.compactMap { node -> String? in if case .page(let page) = node { page.title } else { nil } }
        XCTAssertEqual(titles, ["Docs", "After folder", "A", "B", "C"])
    }

    func testOnlyHTTPURLsAreKept() throws {
        let staging = try parseBasic()
        let urls = staging.spaces.flatMap(\.today).compactMap { node -> String? in
            if case .page(let page) = node { page.url.absoluteString } else { nil }
        }
        XCTAssertEqual(urls, ["https://example.test/today/1", "https://example.test/today/2"])
        let rejected = staging.warnings.filter { $0.kind == .unsupportedURL }
        XCTAssertEqual(rejected.map(\.detail), ["arc", "file"])
    }

    func testWarningsAreTypedAndCountedOncePerCause() throws {
        let counts = try parseBasic().warningCounts
        XCTAssertEqual(counts, [
            .unsupportedURL: 2, .depthHoisted: 1, .splitFlattened: 1, .unknownItem: 1, .missingReference: 1,
            .truncatedName: 1, .nameDefaulted: 1, .droppedIcon: 1, .droppedTheme: 2,
            .duplicateFavorite: 1, .interleavingLost: 1,
        ])
        XCTAssertTrue(try parseBasic().warnings.allSatisfy { $0.detail.map { !$0.contains("example") } ?? true })
    }

    func testLongFolderNameIsTruncatedToBatoLimit() throws {
        let work = try parseBasic().spaces[0]
        guard case .folder(let folder) = work.pinned.last else { return XCTFail("folder missing") }
        XCTAssertEqual(folder.name.count, 80)
    }

    func testCyclesAndDanglingReferencesProduceWarningsNotFailures() throws {
        let cycle = try ArcSidebarParser.parse(fixture("cycle"))
        XCTAssertEqual(cycle.warningCounts, [.cycle: 1])
        let dangling = try ArcSidebarParser.parse(fixture("dangling-children"))
        XCTAssertEqual(dangling.warningCounts, [.missingReference: 2, .duplicateItem: 1])
        guard case .page = dangling.spaces[0].pinned.first else { return XCTFail("tab should survive") }
        XCTAssertEqual(dangling.spaces[0].pinned.count, 1)
    }

    func testBadInputThrowsTypedErrors() throws {
        XCTAssertThrowsError(try ArcSidebarParser.parse(fixture("malformed"))) {
            XCTAssertEqual($0 as? ArcImportError, .invalidJSON)
        }
        XCTAssertThrowsError(try ArcSidebarParser.parse(fixture("missing-keys"))) {
            XCTAssertEqual($0 as? ArcImportError, .missingSidebar)
        }
        XCTAssertThrowsError(try ArcSidebarParser.parse(Data(count: ArcSidebarParser.maxInputBytes + 1))) {
            XCTAssertEqual($0 as? ArcImportError, .tooLarge)
        }
    }

    func testExcessiveNestingIsBounded() throws {
        var items: [Any] = ["P", ["id": "P", "childrenIds": ["f0"], "data": ["itemContainer": [:]]]]
        let depth = ArcSidebarParser.maxNesting + 10
        for index in 0..<depth {
            items += ["f\(index)", ["id": "f\(index)", "childrenIds": ["f\(index + 1)"], "data": ["list": [:]]]]
        }
        let spaces: [Any] = ["S", ["id": "S", "title": "Deep", "containerIDs": ["pinned", "P"]]]
        let staging = try ArcSidebarParser.parse(json(sidebar(items: items, spaces: spaces)))
        XCTAssertEqual(staging.warningCounts[.excessiveNesting], 1)
    }

    func testPlanBuildsValidDraftWithoutTouchingExistingState() throws {
        let existing = BrowserState.initial()
        let plan = try ImportPlan.make(parseBasic(), into: existing)
        try plan.state.validate()
        XCTAssertEqual(plan.state.profiles.count, 3)
        XCTAssertEqual(plan.state.profiles[0], existing.profiles[0])
        XCTAssertEqual(plan.state.workspaces[0], existing.workspaces[0])
        XCTAssertEqual(plan.state.activeWorkspaceID, existing.activeWorkspaceID)
        XCTAssertEqual(plan.state.workspaces.dropFirst().map(\.name), ["Work", "Space 2", "Side"])
        XCTAssertEqual(plan.state.profiles.dropFirst().map(\.name), ["Arc", "Arc - Profile 1"])
        XCTAssertEqual(plan.state.profiles[1].favorites.map(\.kind), [.favorite, .favorite])
        let work = plan.state.workspaces[1]
        XCTAssertEqual(work.profileID, plan.state.profiles[1].id)
        XCTAssertEqual(work.color, "#FF8000")
        XCTAssertEqual(plan.state.workspaces[3].color, "#B47879")
        XCTAssertEqual(plan.state.workspaces[3].profileID, plan.state.profiles[2].id)
    }

    func testPlanMapsFoldersPinsAndSplits() throws {
        let work = try ImportPlan.make(parseBasic(), into: .initial()).state.workspaces[1]
        XCTAssertEqual(work.folders.map(\.name).prefix(4), ["Reading", "L2", "L3", "L4"])
        XCTAssertEqual(work.folders.map { work.depth(ofFolder: $0.id) }, [1, 2, 3, 4, 1, 1])
        XCTAssertTrue(work.folders.allSatisfy(\.isCollapsed))
        XCTAssertEqual(work.folders[0].pinIDs.count, 1)
        XCTAssertEqual(work.folders[3].pinIDs.compactMap { id in work.pins.first { $0.id == id }?.title }, ["Deep five", "Deep four"])
        XCTAssertEqual(work.pins.count, 11)
        XCTAssertTrue(work.pins.allSatisfy { $0.kind == .pinned && $0.savedURL == $0.lastURL })
        XCTAssertEqual(work.splits.count, 1)
        XCTAssertTrue(work.splits[0].isPinned)
        XCTAssertEqual(work.splits[0].dividerRatio, 0.5)
        XCTAssertTrue(work.tabs.isEmpty)
    }

    func testTodayTabsAreExcludedByDefaultAndOptional() throws {
        let staging = try parseBasic()
        let without = try ImportPlan.make(staging, into: .initial())
        XCTAssertEqual(without.summary.tabs, 0)
        let with = try ImportPlan.make(staging, options: ImportOptions(includeTodayTabs: true), into: .initial())
        XCTAssertEqual(with.summary.tabs, 2)
        let tabs = with.state.workspaces[2].tabs
        XCTAssertTrue(tabs.allSatisfy { $0.kind == .temporary && $0.savedURL == nil })
        try with.state.validate()
    }

    func testSummaryCountsMatchDraft() throws {
        let plan = try ImportPlan.make(parseBasic(), into: .initial())
        XCTAssertEqual(plan.summary.profiles, 2)
        XCTAssertEqual(plan.summary.workspaces, 3)
        XCTAssertEqual(plan.summary.favorites, 3)
        XCTAssertEqual(plan.summary.pins, 13)
        XCTAssertEqual(plan.summary.folders, 6)
        XCTAssertEqual(plan.summary.splits, 1)
        XCTAssertEqual(plan.summary.spaces[0].maxFolderDepth, 4)
        XCTAssertEqual(plan.summary.warningCounts, plan.warnings.reduce(into: [:]) { $0[$1.kind, default: 0] += 1 })
    }

    func testExcludedSpacesAreDroppedWithTheirProfilesAndWarnings() throws {
        let plan = try ImportPlan.make(parseBasic(), options: ImportOptions(excludedSpaceIDs: ["S3", "S1"]), into: .initial())
        XCTAssertEqual(plan.state.workspaces.dropFirst().map(\.name), ["Space 2"])
        XCTAssertEqual(plan.state.profiles.map(\.name), ["Personal", "Arc"])
        XCTAssertNil(plan.summary.warningCounts[.droppedTheme])
        XCTAssertEqual(plan.summary.warningCounts[.nameDefaulted], 1)
        XCTAssertThrowsError(try ImportPlan.make(parseBasic(), options: ImportOptions(excludedSpaceIDs: ["S1", "S2", "S3"]), into: .initial())) {
            XCTAssertEqual($0 as? ImportPlanError, .nothingToImport)
        }
    }

    func testIdentifiersAreDeterministicAndReimportIsDetected() throws {
        let staging = try parseBasic()
        let first = try ImportPlan.make(staging, into: .initial())
        let second = try ImportPlan.make(staging, into: .initial())
        XCTAssertEqual(first.state.workspaces.dropFirst().map(\.id), second.state.workspaces.dropFirst().map(\.id))
        XCTAssertThrowsError(try ImportPlan.make(staging, into: first.state)) {
            XCTAssertEqual($0 as? ImportPlanError, .alreadyImported)
        }
        let copy = try ImportPlan.make(staging, options: ImportOptions(idSalt: "copy"), into: first.state)
        try copy.state.validate()
        XCTAssertEqual(copy.state.workspaces.count, 7)
    }

    func testPlanRejectsInvalidExistingState() throws {
        var broken = BrowserState.initial()
        broken.workspaces[0].color = "red"
        XCTAssertThrowsError(try ImportPlan.make(parseBasic(), into: broken))
    }
}
