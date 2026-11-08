import XCTest
@testable import BatoBrowserUI

final class SidebarHoverCardTests: XCTestCase {
    func testShowsTitleAndHostWithoutWww() {
        let content = SidebarHoverCardContent(title: " Docs home ", url: URL(string: "https://www.example.com/a/b")!)
        XCTAssertEqual(content, SidebarHoverCardContent(title: "Docs home", url: URL(string: "https://example.com/z")!))
        XCTAssertEqual(content.host, "example.com")
    }

    func testEmptyTitleFallsBackToTheHost() {
        XCTAssertEqual(SidebarHoverCardContent(title: "", url: URL(string: "https://example.com/")!).title, "example.com")
    }

    func testUrlWithoutHostShowsTheAddress() {
        XCTAssertEqual(SidebarHoverCardContent(title: "Blank", url: URL(string: "about:blank")!).host, "about:blank")
    }
}
