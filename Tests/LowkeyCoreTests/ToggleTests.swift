import Foundation
import Testing
@testable import LowkeyCore

@Suite struct ToggleTests {
    @Test func parsesAliasAndWildcardToggle() throws {
        #expect(try DeepLink.parse(URL(string: "lowkey://HA/toggle")!).get() == .site(alias: "HA", command: .toggle))
        #expect(try DeepLink.parse(URL(string: "lowkey://*/toggle")!).get() == .site(alias: "*", command: .toggle))
        #expect(try DeepLink.parse(URL(string: "lowkey://ha/TOGGLE")!).get() == .site(alias: "ha", command: .toggle))
        #expect(DeepLink.parse(URL(string: "lowkey://HA/toggle/extra")!) == .failure(.unknownCommand("toggle/extra")))
    }

    @Test func hiddenAndMinimizedWindowsAreShown() {
        #expect(WindowToggle.action(isVisible: false, isMiniaturized: false) == .show)
        #expect(WindowToggle.action(isVisible: true, isMiniaturized: true) == .show)
        #expect(WindowToggle.action(isVisible: true, isMiniaturized: false) == .hide)
    }

    @Test func wildcardHidesIfAnySavedWindowIsVisible() {
        #expect(WindowToggle.groupAction(visibleWindows: [true, false]) == .hide)
        #expect(WindowToggle.groupAction(visibleWindows: [true, true]) == .hide)
        #expect(WindowToggle.groupAction(visibleWindows: [false, false]) == .show)
        #expect(WindowToggle.groupAction(visibleWindows: []) == .show)
    }
}
