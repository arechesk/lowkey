import Testing
import WebKit
import LowkeyCore
@testable import Lowkey

@MainActor @Suite struct PageControlsTests {
    @Test func formCommands() async throws {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 480, height: 300), configuration: config)
        let url = URL(string: "https://demo.invalid")!
        view.loadSimulatedRequest(URLRequest(url: url), responseHTML: """
        <input aria-label="Comment" id="t" value="private-content"><label>Period<select id="s"><option>One</option><option>Two</option></select></label>
        <button disabled>Send</button><input type="password" value="another-secret">
        """)
        let deadline = ContinuousClock.now + .seconds(5)
        while view.isLoading && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        func run(_ cmd: PageCommand, _ args: [String] = []) async -> String { await PageControls.run(cmd,args: args,view: view,site: url) }
        #expect(await run(.wait) == "ok")
        #expect(await run(.wait, ["Send"]) == "pending")
        let raw = await run(.inspect, ["--json"])
        #expect(raw.hasPrefix("output:"))
        let rows = try #require(JSONSerialization.jsonObject(with: Data(raw.dropFirst(7).utf8)) as? [[String: Any]])
        #expect(rows.count == 3 && !raw.contains("secret") && !raw.contains("private-content"))
        #expect(await run(.fill, ["Comment", "a ' quote"]) == "ok")
        #expect(await run(.select, ["Period", "Two"]) == "ok")
        #expect(try await view.evaluateJavaScript("[t.value,s.value]") as? [String] == ["a ' quote", "Two"])
        #expect(await run(.select, ["Period", "Three"]) == "option not found")
        _ = try await view.evaluateJavaScript("document.querySelector('button').disabled=false;t.after(t.cloneNode())")
        #expect(await run(.wait, ["Send"]) == "ok")
        #expect(await run(.fill, ["Comment", "other"]) == "ambiguous label")
        #expect(await PageControls.run(.inspect, args: [], view: view, site: URL(string: "https://another.invalid")!) == "wrong site origin")
    }
}
