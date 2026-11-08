import XCTest
@testable import BatoBrowserUI

@MainActor
final class TabAudioTests: XCTestCase {
    private let center = TabAudioCenter()

    func testAudibleAndMutedTabsAreShownAndSilentOnesForgotten() {
        let entry = UUID()
        center.update(entryID: entry, audible: true, muted: false)
        XCTAssertEqual(center.states[entry], .init(audible: true, muted: false))
        center.update(entryID: entry, audible: false, muted: true)
        XCTAssertEqual(center.states[entry]?.shown, true)
        center.update(entryID: entry, audible: false, muted: false)
        XCTAssertNil(center.states[entry])
    }

    func testToggleAsksTheEngineForTheOppositeMutedState() {
        let entry = UUID()
        var requests: [Bool] = []
        center.setMuted = { _, muted in requests.append(muted); return true }
        center.update(entryID: entry, audible: true, muted: false)
        center.toggleMute(entryID: entry)
        center.update(entryID: entry, audible: false, muted: true)
        center.toggleMute(entryID: entry)
        XCTAssertEqual(requests, [true, false])
    }

    func testToggleIgnoresTabsWithoutAudio() {
        var asked = false
        center.setMuted = { _, _ in asked = true; return true }
        center.toggleMute(entryID: UUID())
        XCTAssertFalse(asked)
    }
}
