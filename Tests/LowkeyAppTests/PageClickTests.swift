import Testing
import WebKit
@testable import Lowkey

@MainActor @Suite struct PageClickTests {
    @Test func onlyClicksOneMatchingControlOnTheSavedOrigin() async throws {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), configuration: config)
        let site = URL(string: "https://click-test.invalid/")!
        let html = """
        <meta charset="utf-8"><body onclick="document.body.dataset.hit=event.target.id">
        <button id="refresh">Обновить  список</button><a href="#next" id="go">Go</a>
        <button hidden>Go</button><button>Double</button><a href="#two">Double</a>
        <button disabled>Disabled</button><a href="javascript:void(0)">Script</a>
        """
        view.loadSimulatedRequest(URLRequest(url: site), responseHTML: html)
        let deadline = ContinuousClock.now + .seconds(5)
        while view.isLoading && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(15)) }
        #expect(await PageClick.perform(in: view, startURL: site, label: "Обновить список") == "ok")
        #expect(try await view.evaluateJavaScript("document.body.dataset.hit") as? String == "refresh")
        #expect(await PageClick.perform(in: view, startURL: site, label: "Go") == "ok")
        #expect(await PageClick.perform(in: view, startURL: site, label: "Double") == "ambiguous label")
        #expect(await PageClick.perform(in: view, startURL: site, label: "Missing") == "label not found")
        #expect(await PageClick.perform(in: view, startURL: site, label: "Disabled") == "control disabled")
        #expect(await PageClick.perform(in: view, startURL: site, label: "Script") == "unsupported link")
        #expect(await PageClick.perform(in: view, startURL: URL(string: "https://other.invalid")!, label: "Обновить список") == "wrong site origin")
        #expect(try await view.evaluateJavaScript("document.body.dataset.hit") as? String == "go")
    }
}
