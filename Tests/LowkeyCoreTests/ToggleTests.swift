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

    @Test func onlyFrontmostVisibleWindowIsHidden() {
        for isVisible in [false, true] {
            for isMiniaturized in [false, true] {
                for isFrontmost in [false, true] {
                    let expected: WindowToggle = isVisible && !isMiniaturized && isFrontmost ? .hide : .show
                    #expect(WindowToggle.action(isVisible: isVisible, isMiniaturized: isMiniaturized,
                                                isFrontmost: isFrontmost) == expected)
                }
            }
        }
    }

    @Test func restoresOtherWindowsBehindTheAppThatWasInFront() {
        let moves = WindowToggle.backgroundRestoration(before: [10, 2, 1, 3], after: [1, 3, 2, 10],
                                                       owned: [1, 2, 3], target: 1)
        #expect(moves.map(\.window) == [3, 2])  // Reverse insertion preserves the original stack.
        #expect(moves.map(\.anchor) == [10, 10])
    }

    @Test func hidingLetsOnlyWindowsAlreadyInFrontTakeFocus() {
        #expect(WindowToggle.backgroundWindows(in: [1, 2, 10, 3, 11, 4], owned: [1, 2, 3, 4]) == [3, 4])
        #expect(WindowToggle.backgroundWindows(in: [1, 2], owned: [1, 2]).isEmpty)
    }

    @Test func leavesWindowsThatDidNotCrossAnExternalWindowAlone() {
        let moves = WindowToggle.backgroundRestoration(before: [2, 10, 3, 1, 4, 5], after: [1, 2, 10, 3, 5],
                                                       owned: [1, 2, 3, 4, 5], target: 1)
        #expect(moves.isEmpty)  // Includes window 4, which is no longer onscreen.
    }

    @Test func restoresSeparateGroupsAndSkipsVanishedAnchors() {
        let moves = WindowToggle.backgroundRestoration(before: [10, 2, 11, 3, 12, 4, 1],
                                                       after: [1, 4, 3, 10, 12, 2],
                                                       owned: [1, 2, 3, 4], target: 1)
        #expect(moves.map(\.window) == [3, 2, 4])
        #expect(moves.map(\.anchor) == [10, 10, 12])
    }

    @Test func wildcardHidesOnlyIfASavedWindowIsFrontmost() {
        #expect(WindowToggle.groupAction(frontmostWindows: [true, false]) == .hide)
        #expect(WindowToggle.groupAction(frontmostWindows: [false, false]) == .show)
        #expect(WindowToggle.groupAction(frontmostWindows: []) == .show)
    }
}
