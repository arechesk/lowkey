import Foundation
import Testing
@testable import LowkeyCore

private let ha = Site(alias: "HA", title: "Home Assistant", startURL: "https://homeassistant.local",
                      extraOrigins: ["*.nabu.casa", "http://ha.lan:8123"])

@Suite struct DeepLinkTests {
    @Test func parsesSiteCommands() throws {
        #expect(try DeepLink.parse(URL(string: "lowkey://HA/open")!).get() == .site(alias: "HA", command: .open))
        #expect(try DeepLink.parse(URL(string: "lowkey://ha/Reload")!).get() == .site(alias: "ha", command: .reload))
        #expect(try DeepLink.parse(URL(string: "lowkey://HA")!).get() == .site(alias: "HA", command: .open))
        #expect(try DeepLink.parse(URL(string: "lowkey://HA/")!).get() == .site(alias: "HA", command: .open))
        #expect(try DeepLink.parse(URL(string: "LOWKEY://my_site/close")!).get() == .site(alias: "my_site", command: .close))
    }

    @Test func emptyAliasShowsPrompt() throws {
        #expect(try DeepLink.parse(URL(string: "lowkey://")!).get() == .prompt)
    }

    @Test func rejectsUnknownCommandsAndSchemes() {
        #expect(DeepLink.parse(URL(string: "lowkey://HA/eval")!) == .failure(.unknownCommand("eval")))
        #expect(DeepLink.parse(URL(string: "lowkey://HA/open/extra")!) == .failure(.unknownCommand("open/extra")))
        #expect(DeepLink.parse(URL(string: "https://HA/open")!) == .failure(.notLowkey))
    }
}

@Suite struct AddressTests {
    @Test func aliasWinsCaseInsensitively() {
        #expect(AddressResolver.resolve("ha", sites: [ha]) == .site(ha))
    }

    @Test func bareHostsGetHTTPS() {
        #expect(AddressResolver.resolve("google.com", sites: [ha]) == .url(URL(string: "https://google.com")!))
        #expect(AddressResolver.resolve("nas.local:5000/x", sites: []) == .url(URL(string: "https://nas.local:5000/x")!))
    }

    @Test func loopbackGetsHTTP() {
        #expect(AddressResolver.resolve("localhost:3000", sites: []) == .url(URL(string: "http://localhost:3000")!))
        #expect(AddressResolver.resolve("127.0.0.1:8080", sites: []) == .url(URL(string: "http://127.0.0.1:8080")!))
    }

    @Test func keepsExplicitWebSchemes() {
        #expect(AddressResolver.resolve("http://ha.lan:8123", sites: []) == .url(URL(string: "http://ha.lan:8123")!))
    }

    @Test func rejectsWordsAndOtherSchemes() {
        #expect(AddressResolver.resolve("unknown", sites: [ha]) == .invalid)
        #expect(AddressResolver.resolve("two words.com", sites: []) == .invalid)
        #expect(AddressResolver.resolve("file:///etc/passwd", sites: []) == .invalid)
        #expect(AddressResolver.resolve("javascript://x.com", sites: []) == .invalid)
        #expect(AddressResolver.resolve("   ", sites: []) == .invalid)
    }
}

@Suite struct HistoryTests {
    @Test func recordsNewestFirstWithoutDuplicates() {
        var history = InputHistory()
        history.record("a.com")
        history.record("b.com")
        history.record("A.com")
        #expect(history.entries == ["A.com", "b.com"])
    }

    @Test func keepsLastThousand() {
        var history = InputHistory()
        for i in 0..<1005 { history.record("site\(i).com") }
        #expect(history.entries.count == 1000)
        #expect(history.entries.first == "site1004.com")
        #expect(history.entries.last == "site5.com")
    }

    @Test func removedEntryReturnsWhenSubmitted() {
        var history = InputHistory(entries: ["a.com", "b.com"])
        history.remove("A.COM")
        #expect(history.entries == ["b.com"])
        history.record("a.com")
        #expect(history.entries == ["a.com", "b.com"])
    }

    @Test func roundTripsThroughFile() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "lowkey-history-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try InputHistory(entries: ["x.com", "y.com"]).save(to: url)
        #expect(InputHistory.load(from: url).entries == ["x.com", "y.com"])
    }
}

@Suite struct SuggestionTests {
    let grafana = Site(alias: "GRAF", title: "Grafana", startURL: "https://grafana.lan:3000")

    @Test func sitesComeFirstThenHistory() {
        let history = InputHistory(entries: ["https://github.com", "https://graphql.org", "HA"])
        let result = Suggestions.make(query: "gr", sites: [ha, grafana], history: history)
        #expect(result == [.site(grafana), .history("https://graphql.org")])
    }

    @Test func emptyQueryListsEverything() {
        let history = InputHistory(entries: ["https://github.com"])
        #expect(Suggestions.make(query: "", sites: [ha], history: history) == [.site(ha), .history("https://github.com")])
    }

    @Test func historyPrefixBeatsContains() {
        let history = InputHistory(entries: ["https://maps.google.com", "https://google.com"])
        let result = Suggestions.make(query: "goo", sites: [], history: history)
        #expect(result == [.history("https://google.com"), .history("https://maps.google.com")])
    }
}

@Suite struct LinkPolicyTests {
    @Test func originsNormalizeDefaultPorts() {
        #expect(Origin(URL(string: "https://A.com")!) == Origin(URL(string: "https://a.com:443/x")!))
        #expect(Origin(URL(string: "https://a.com")!) != Origin(URL(string: "http://a.com")!))
    }

    @Test func siteOriginsAndPatterns() {
        #expect(LinkPolicy.isPartOfSite(URL(string: "https://homeassistant.local/lovelace")!, site: ha))
        #expect(!LinkPolicy.isPartOfSite(URL(string: "https://sub.homeassistant.local/")!, site: ha))
        #expect(LinkPolicy.isPartOfSite(URL(string: "https://abc.ui.nabu.casa/")!, site: ha))
        #expect(LinkPolicy.isPartOfSite(URL(string: "https://nabu.casa/")!, site: ha) == false)
        #expect(LinkPolicy.isPartOfSite(URL(string: "http://ha.lan:8123/")!, site: ha))
        #expect(!LinkPolicy.isPartOfSite(URL(string: "https://ha.lan:8123/")!, site: ha))
    }

    @Test func externalLinksFollowSitePolicy() {
        let external = URL(string: "https://example.com")!
        #expect(LinkPolicy.decide(linkTo: external, site: ha) == .openExternally)
        var inside = ha
        inside.externalLinks = .lowkey
        #expect(LinkPolicy.decide(linkTo: external, site: inside) == .stay)
        #expect(LinkPolicy.decide(linkTo: external, site: nil) == .stay)
        #expect(LinkPolicy.decide(linkTo: URL(string: "https://homeassistant.local/x")!, site: ha) == .stay)
    }

    @Test func signInPagesStay() {
        #expect(LinkPolicy.decide(linkTo: URL(string: "https://accounts.google.com/o/oauth2/auth")!, site: ha) == .stay)
        #expect(AuthProviders.isSignIn(URL(string: "https://github.com/login/oauth/authorize")!))
        #expect(!AuthProviders.isSignIn(URL(string: "https://github.com/bobuk")!))
        #expect(AuthProviders.isSignIn(URL(string: "https://dev-x.eu.auth0.com/authorize")!))
    }

    @Test func otherSchemesLeaveEvenInOrdinaryWindows() {
        #expect(LinkPolicy.decide(linkTo: URL(string: "mailto:a@b.c")!, site: nil) == .openExternally)
        #expect(LinkPolicy.decide(linkTo: URL(string: "about:blank")!, site: ha) == .stay)
    }

    @Test func rejectsBadPatterns() {
        #expect(OriginPattern("ftp://x.com") == nil)
        #expect(OriginPattern("a.*.com") == nil)
        #expect(OriginPattern("") == nil)
    }
}

@Suite struct ConfigTests {
    @Test func validatesAliasesAndURLs() {
        #expect(Site.isValidAlias("HA"))
        #expect(Site.isValidAlias("my-site_2"))
        #expect(!Site.isValidAlias("-x"))
        #expect(!Site.isValidAlias("a.b"))
        #expect(!Site.isValidAlias("сайт"))
        let config = Config(sites: [ha, Site(alias: "ha", startURL: "ftp://x"), Site(alias: "bad alias", startURL: "x.com")])
        #expect(config.problems().count == 3)
    }

    @Test func toleratesMissingFields() throws {
        let json = #"{"sites":[{"alias":"HA","startURL":"https://homeassistant.local"}]}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.site(alias: "ha")?.externalLinks == .defaultBrowser)
        #expect(config.appearance.mode == .page)
    }

    @Test func roundTripsThroughFile() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "lowkey-config-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let config = Config(sites: [ha], appearance: AppearanceConfig(mode: .dark))
        try config.save(to: url)
        #expect(try Config.load(from: url) == config)
    }

    @Test func invalidThemeColorsFallBack() throws {
        let json = ##"{"appearance":{"mode":"light","light":{"preset":"x","panel":"red","accent":"#000000"}}}"##
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.appearance.light == ThemePreset.amber.colors(dark: false))
    }
}

@Suite struct ThemeTests {
    @Test func inkFollowsPanelBrightness() {
        #expect(!ThemeTokens(colors: ThemePreset.amber.colors(dark: false)).isDark)
        #expect(ThemeTokens(colors: ThemePreset.amber.colors(dark: true)).isDark)
    }

    @Test func presetsAreValidHex() {
        for preset in ThemePreset.all {
            for dark in [false, true] {
                let colors = preset.colors(dark: dark)
                #expect(RGB(hex: colors.panel) != nil && RGB(hex: colors.accent) != nil, "\(preset.id)")
            }
        }
        #expect(Set(ThemePreset.all.map(\.id)).count == ThemePreset.all.count)
    }

    @Test func flagsLowContrastAccent() {
        #expect(ThemeTokens(colors: ThemeColors(preset: "custom", panel: "#222222", accent: "#2a2a2a")).lowAccentContrast)
        #expect(RGB(hex: "#885500")?.hex == "#885500")
    }
}
