import Foundation
import XCTest
@testable import BatoCore

final class OnboardingTests: XCTestCase {
    func testFlowWalksForwardAndEndsAfterTheLastStep() {
        var flow = OnboardingFlow()
        XCTAssertEqual(flow.step, .welcome)
        XCTAssertFalse(flow.canGoBack)
        flow.advance()
        flow.advance()
        XCTAssertEqual(flow.step, .makeItYours)
        XCTAssertTrue(flow.canGoBack)
        flow.advance()
        XCTAssertEqual(flow.step, .done)
        XCTAssertFalse(flow.isEnded)
        flow.advance()
        XCTAssertTrue(flow.isEnded)
    }

    func testBackStopsAtWelcomeAndNeverLeavesDone() {
        var flow = OnboardingFlow()
        flow.goBack()
        XCTAssertEqual(flow.step, .welcome)
        flow.advance()
        flow.goBack()
        XCTAssertEqual(flow.step, .welcome)
        flow.advance()
        flow.advance()
        flow.advance()
        flow.goBack()
        XCTAssertEqual(flow.step, .done)
    }

    func testSkipEndsFromAnyStep() {
        var flow = OnboardingFlow()
        flow.advance()
        flow.skip()
        XCTAssertTrue(flow.isEnded)
    }

    func testOnlyAvailableOptionsCanBeChosen() {
        var choices = OnboardingChoices()
        XCTAssertFalse(choices.select(NewTabStyle.fullPage))
        XCTAssertEqual(choices.newTab, .popup)
        XCTAssertTrue(choices.select(NewTabStyle.popup))
    }

    func testEveryTabLayoutCanBeChosen() {
        var choices = OnboardingChoices()
        XCTAssertEqual(choices.tabLayout, .sidebar)
        for layout in TabLayout.allCases {
            choices.tabLayout = layout
            XCTAssertEqual(choices.tabLayout, layout)
        }
    }

    func testThemePresetsStartWithNoneAndAreValid() {
        let presets = OnboardingThemePreset.all
        XCTAssertEqual(presets.count, 9)
        XCTAssertEqual(presets[0].name, "None")
        XCTAssertNil(presets[0].theme)
        XCTAssertTrue(presets.dropFirst().allSatisfy { $0.theme?.isValid == true })
        XCTAssertEqual(Set(presets.map(\.name)).count, 9)
    }

    func testThemeSelectionRejectsOutOfRangeAndMapsToATheme() {
        var choices = OnboardingChoices()
        XCTAssertNil(choices.theme)
        XCTAssertFalse(choices.selectTheme(at: 9))
        XCTAssertTrue(choices.selectTheme(at: 2))
        XCTAssertEqual(choices.theme, OnboardingThemePreset.all[2].theme)
    }
}
