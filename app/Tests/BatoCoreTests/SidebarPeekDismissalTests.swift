import XCTest
@testable import BatoCore

final class SidebarPeekDismissalTests: XCTestCase {
    private func context(inside: Bool = false, focused: Bool = false, incidental: Bool = false,
                         interactive: Bool = true) -> SidebarPeekDismissal.Context {
        .init(pointerInside: inside, sidebarFocused: focused, focusIsIncidental: incidental, interactive: interactive)
    }

    private func dismisses(_ event: SidebarPeekDismissal.Event, _ context: SidebarPeekDismissal.Context) -> Bool {
        SidebarPeekDismissal.shouldDismiss(on: event, context)
    }

    func testPointerExitDismissesUnlessTheSidebarHoldsFocus() {
        XCTAssertTrue(dismisses(.pointerExited, context()))
        XCTAssertFalse(dismisses(.pointerExited, context(focused: true)))
    }

    func testPollDismissesAnOverlayThePointerNeverEntered() {
        XCTAssertTrue(dismisses(.pointerPoll, context(inside: false)))
    }

    func testPollKeepsTheOverlayWhileThePointerIsOverItOrTheSidebarIsFocused() {
        XCTAssertFalse(dismisses(.pointerPoll, context(inside: true)))
        XCTAssertFalse(dismisses(.pointerPoll, context(focused: true)))
    }

    func testFocusLeftOnTheControlAFocusRequestLandedOnDoesNotKeepTheOverlayUp() {
        let landed = context(focused: true, incidental: true)
        XCTAssertTrue(dismisses(.pointerPoll, landed))
        XCTAssertTrue(dismisses(.pointerExited, landed))
        XCTAssertFalse(dismisses(.pointerPoll, context(inside: true, focused: true, incidental: true)))
    }

    func testPageKeyAndPageClickDismissEvenWhileHovering() {
        XCTAssertTrue(dismisses(.pageKey, context(inside: true)))
        XCTAssertTrue(dismisses(.pageClicked, context(inside: true)))
    }

    func testSheetOrMenuKeepsTheOverlayUpWhateverHappens() {
        let busy = context(interactive: false)
        for event in [SidebarPeekDismissal.Event.pointerExited, .pointerPoll, .pageKey, .pageClicked, .windowResigned] {
            XCTAssertFalse(dismisses(event, busy), "\(event)")
        }
    }

    func testWindowResignDismissesRegardlessOfFocusOrPointer() {
        XCTAssertTrue(dismisses(.windowResigned, context(inside: true, focused: true)))
    }
}
