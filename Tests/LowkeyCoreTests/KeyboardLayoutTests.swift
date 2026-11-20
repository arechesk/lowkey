import Foundation
import Testing
@testable import LowkeyCore

@Suite struct KeyboardLayoutTests {
    private let ha = Site(alias: "HA", title: "Home Assistant", startURL: "https://homeassistant.local")

    // BobukCore's KeyboardLayoutSwap tests cover the variants themselves; these cover lowkey's use.
    @Test func opensAnExactAliasInAnotherLayout() {
        #expect(AddressResolver.resolve("рф", sites: [ha]) == .site(ha))
        #expect(AddressResolver.resolve("  РФ  ", sites: [ha]) == .site(ha))
    }

    @Test func searchesAliasesTitlesAndHistory() {
        let telegram = Site(alias: "TG", title: "Телеграм", startURL: "https://web.telegram.org")
        let history = InputHistory(entries: ["https://google.com", "https://github.com"])
        #expect(Suggestions.make(query: "рф", sites: [ha], history: history) == [.site(ha)])
        #expect(Suggestions.make(query: "пщщпду", sites: [], history: history) == [.history("https://google.com")])
        #expect(Suggestions.make(query: "ntktuhfv", sites: [telegram], history: history) == [.site(telegram)])
        #expect(Suggestions.make(query: "пше", sites: [], history: history) == [.history("https://github.com")])
    }

    @Test func directSpellingRanksBeforeLayoutAlternativesAndNeverDuplicates() {
        let latin = Site(alias: "A", title: "Figma", startURL: "https://a.example")
        let cyrillic = Site(alias: "B", title: "Альфа", startURL: "https://b.example")
        let result = Suggestions.make(query: "а", sites: [latin, cyrillic], history: InputHistory())
        #expect(result.first == .site(cyrillic))
        #expect(result.count == 2)
        let history = InputHistory(entries: ["https://aa.example"])
        #expect(Suggestions.make(query: "a", sites: [], history: history).count == 1)
    }

    @Test func validURLsAndPathCaseAreNotRewritten() {
        let address = "https://пример.рф/CaseSensitive?Q=Тест"
        #expect(AddressResolver.resolve(address, sites: [ha]) == .url(URL(string: address)!))
        #expect(AddressResolver.resolve("https://google.com/CaseSensitive", sites: []) == .url(URL(string: "https://google.com/CaseSensitive")!))
    }
}
