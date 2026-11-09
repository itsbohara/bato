import XCTest
@testable import BatoCore

final class SplitDropZonesTests: XCTestCase {
    private let card = CGRect(x: 276, y: 8, width: 1186, height: 884)

    func testZonesSitAtOppositeEdgesCentredVertically() throws {
        let left = try XCTUnwrap(SplitDropZones.frame(of: .left, in: card, expanded: false))
        let right = try XCTUnwrap(SplitDropZones.frame(of: .right, in: card, expanded: false))
        XCTAssertEqual(left.minX, card.minX + SplitDropZones.edgeInset)
        XCTAssertEqual(right.maxX, card.maxX - SplitDropZones.edgeInset)
        XCTAssertEqual(left.midY, card.midY)
        XCTAssertEqual(right.size, SplitDropZones.armedSize)
    }

    func testExpandedZonesAreLargerAndStayInsideTheCard() throws {
        let armed = try XCTUnwrap(SplitDropZones.frame(of: .left, in: card, expanded: false))
        let expanded = try XCTUnwrap(SplitDropZones.frame(of: .left, in: card, expanded: true))
        XCTAssertEqual(expanded.size, SplitDropZones.expandedSize)
        XCTAssertGreaterThan(expanded.width, armed.width)
        XCTAssertTrue(card.contains(expanded))
    }

    func testNarrowCardKeepsPageBetweenZones() throws {
        let narrow = CGRect(x: 0, y: 0, width: 500, height: 400)
        let left = try XCTUnwrap(SplitDropZones.frame(of: .left, in: narrow, expanded: true))
        let right = try XCTUnwrap(SplitDropZones.frame(of: .right, in: narrow, expanded: true))
        XCTAssertLessThan(left.maxX, right.minX)
        XCTAssertLessThanOrEqual(left.height, narrow.height)
    }

    func testOnlyLeftAndRightAreOffered() {
        XCTAssertNil(SplitDropZones.frame(of: .top, in: card, expanded: true))
        XCTAssertNil(SplitDropZones.frame(of: .bottom, in: card, expanded: true))
    }

    func testHitTestPicksZoneUnderPointer() throws {
        let left = try XCTUnwrap(SplitDropZones.frame(of: .left, in: card, expanded: true))
        let right = try XCTUnwrap(SplitDropZones.frame(of: .right, in: card, expanded: true))
        XCTAssertEqual(SplitDropZones.side(at: CGPoint(x: left.midX, y: left.midY), in: card, expanded: true), .left)
        XCTAssertEqual(SplitDropZones.side(at: CGPoint(x: right.midX, y: right.midY), in: card, expanded: true), .right)
    }

    func testPageCentreAndEdgeGapAreNotTargets() {
        XCTAssertNil(SplitDropZones.side(at: CGPoint(x: card.midX, y: card.midY), in: card, expanded: true))
        XCTAssertNil(SplitDropZones.side(at: CGPoint(x: card.minX + 2, y: card.midY), in: card, expanded: true))
    }

    func testArmedZoneDoesNotCoverTheExpandedArea() throws {
        let expanded = try XCTUnwrap(SplitDropZones.frame(of: .left, in: card, expanded: true))
        let point = CGPoint(x: expanded.maxX - 4, y: expanded.maxY - 4)
        XCTAssertEqual(SplitDropZones.side(at: point, in: card, expanded: true), .left)
        XCTAssertNil(SplitDropZones.side(at: point, in: card, expanded: false))
    }
}
