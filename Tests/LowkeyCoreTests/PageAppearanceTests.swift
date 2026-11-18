import Foundation
import Testing
@testable import LowkeyCore

@Suite struct PageAppearanceTests {
    @Test func detectsCommonBackgrounds() {
        for hex in ["#282a36", "#2e3440", "#1e1e2e", "#002b36", "#000000"] {
            #expect(PageAppearance.isDark(background: RGB(hex: hex)!))
        }
        for hex in ["#ffffff", "#eff1f5", "#faf4ed", "#fdf6e3", "#eceff4"] {
            #expect(!PageAppearance.isDark(background: RGB(hex: hex)!))
        }
    }

    @Test func deadBandKeepsPreviousMode() {
        let gray = RGB(r: 0.47, g: 0.47, b: 0.47)
        #expect(PageAppearance.isDark(background: gray, previous: true))
        #expect(!PageAppearance.isDark(background: gray, previous: false))
        #expect(!PageAppearance.isDark(background: RGB(hex: "#ffffff")!, previous: true))
        #expect(PageAppearance.isDark(background: RGB(hex: "#222222")!, previous: false))
    }

    @Test func newConfigsFollowPagesWhileExplicitModesArePreserved() throws {
        #expect(AppearanceConfig().mode == .page)
        for mode in ["page", "system", "light", "dark"] {
            let data = Data("{\"appearance\":{\"mode\":\"\(mode)\"}}".utf8)
            let config = try JSONDecoder().decode(Config.self, from: data)
            #expect(config.appearance.mode.rawValue == mode)
        }
    }
}
