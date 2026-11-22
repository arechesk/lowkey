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

    @Test func newConfigsTintWhileExplicitModesArePreserved() throws {
        #expect(AppearanceConfig().mode == .tint)
        for mode in ["tint", "system", "light", "dark"] {
            let data = Data("{\"appearance\":{\"mode\":\"\(mode)\"}}".utf8)
            let config = try JSONDecoder().decode(Config.self, from: data)
            #expect(config.appearance.mode.rawValue == mode)
        }
    }

    @Test func missingModeDecodesToTint() throws {
        for json in [#"{}"#, #"{"appearance":{}}"#, ##"{"version":2,"appearance":{"light":{"preset":"amber","panel":"#f7f8f5","accent":"#885500"}}}"##] {
            #expect(try JSONDecoder().decode(Config.self, from: Data(json.utf8)).appearance.mode == .tint)
        }
        #expect(try JSONDecoder().decode(AppearanceConfig.self, from: Data("{}".utf8)).mode == .tint)
    }

    @Test func savedPageModeMovesToTintOnce() throws {
        func mode(_ json: String) throws -> ThemeMode {
            try JSONDecoder().decode(Config.self, from: Data(json.utf8)).appearance.mode
        }
        #expect(try mode(#"{"appearance":{"mode":"page"}}"#) == .tint)
        #expect(try mode(#"{"version":1,"appearance":{"mode":"page"}}"#) == .tint)
        #expect(try mode(#"{"version":2,"appearance":{"mode":"page"}}"#) == .page)
        for kept in ["system", "light", "dark"] {
            for version in ["", #""version":1,"#, #""version":2,"#] {
                #expect(try mode("{\(version)\"appearance\":{\"mode\":\"\(kept)\"}}").rawValue == kept)
            }
        }
    }

    @Test func encodedConfigHasVersion2AndKeepsPage() throws {
        let data = try JSONEncoder().encode(Config(appearance: AppearanceConfig(mode: .page)))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["version"] as? Int == 2)
        #expect(try JSONDecoder().decode(Config.self, from: data).appearance.mode == .page)
    }

    @Test func tintRoundTripsThroughFile() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "lowkey-config-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let config = Config(appearance: AppearanceConfig(mode: .tint))
        try config.save(to: url)
        #expect(try Config.load(from: url) == config)
        #expect(try Config.load(from: url).appearance.mode == .tint)
    }

    @Test func tintPrefersThemeColorThenBackgroundThenPrevious() {
        let theme = RGB(hex: "#336699")!, background = RGB(hex: "#ffffff")!, previous = RGB(hex: "#111111")!
        let usable = { (rgb: RGB) in PageColor(rgb: rgb, alpha: 1) }
        #expect(PageAppearance.tint(themeColor: usable(theme), background: usable(background), previous: previous) == theme)
        #expect(PageAppearance.tint(themeColor: nil, background: usable(background), previous: previous) == background)
        #expect(PageAppearance.tint(themeColor: PageColor(rgb: theme, alpha: 0.89), background: usable(background),
                                    previous: previous) == background)
        #expect(PageAppearance.tint(themeColor: PageColor(rgb: theme, alpha: 0.9), background: usable(background),
                                    previous: nil) == theme)
        #expect(PageAppearance.tint(themeColor: PageColor(rgb: theme, alpha: 0.5), background: PageColor(rgb: background, alpha: 0),
                                    previous: previous) == previous)
        #expect(PageAppearance.tint(themeColor: nil, background: nil, previous: previous) == previous)
        #expect(PageAppearance.tint(themeColor: nil, background: nil, previous: nil) == nil)
        #expect(PageAppearance.tint(themeColor: PageColor(rgb: theme, alpha: 0.2), background: nil, previous: nil) == nil)
    }

    @Test func tintedTokensTakeInkFromTintAndAccentFromPalette() {
        let palette = ThemePreset.amber.colors(dark: false)
        let accent = ThemeTokens(colors: palette).accent
        let light = RGB(hex: "#ffd700")!, dark = RGB(hex: "#1a237e")!
        let onLight = ThemeTokens(tint: light, colors: palette)
        #expect(onLight.panel == light)
        #expect(onLight.ink == ThemeTokens.darkInk)
        #expect(onLight.accent == accent)
        #expect(onLight.muted == light.mixed(with: ThemeTokens.darkInk, 0.72))
        let onDark = ThemeTokens(tint: dark, colors: palette)
        #expect(onDark.panel == dark)
        #expect(onDark.ink == ThemeTokens.lightInk)
        #expect(onDark.accent == accent)
        #expect(onDark.hover == dark.mixed(with: ThemeTokens.lightInk, 0.07))
        #expect(onLight.isTinted && onDark.isTinted)
        #expect(!ThemeTokens(colors: palette).isTinted)
    }
}
