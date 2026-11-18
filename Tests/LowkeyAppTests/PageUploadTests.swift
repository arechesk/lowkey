import Testing
import WebKit
@testable import Lowkey

@MainActor @Suite struct PageUploadTests {
    @Test func attachesBytesToUniqueInputWithoutSubmitting() async throws {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        let url = URL(string: "https://upload-test.invalid/")!
        view.loadSimulatedRequest(URLRequest(url: url), responseHTML: """
        <form onsubmit="event.preventDefault();document.title='submitted'"><input id=f type=file accept='.pdf' hidden></form>
        <script>f.onchange=()=>document.title='selected'</script>
        """)
        let deadline = ContinuousClock.now + .seconds(5)
        while view.isLoading && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(15)) }
        let data = Data([0, 255, 13])
        #expect(await PageUpload.attach(in: view, startURL: URL(string: "https://other.invalid")!, name: "a.pdf", bytes: data) == "wrong site origin")
        #expect(await PageUpload.attach(in: view, startURL: url, name: "a.png", bytes: data) == "file type not accepted")
        #expect(try await view.evaluateJavaScript("f.files.length") as? Int == 0)
        #expect(await PageUpload.attach(in: view, startURL: url, name: "a b.pdf", bytes: data) == "ok")
        #expect(try await view.evaluateJavaScript("[document.title,f.files[0].name,f.files[0].type]") as? [String] == ["selected", "a b.pdf", "application/pdf"])
        #expect(try await view.callAsyncJavaScript("return Array.from(new Uint8Array(await f.files[0].arrayBuffer()))", contentWorld: .page) as? [Int] == [0, 255, 13])
        _ = try await view.evaluateJavaScript("f.after(f.cloneNode());void 0")
        #expect(await PageUpload.attach(in: view, startURL: url, name: "a.pdf", bytes: data) == "multiple file inputs")
        _ = try await view.evaluateJavaScript("""
        document.body.innerHTML='<label>Avatar<input type=file></label><label for="doc">Документ</label><input id="doc" type=file>';
        void 0
        """)
        #expect(await PageUpload.attach(in: view, startURL: url, name: "b.pdf", bytes: data, field: "Документ") == "ok")
        #expect(try await view.evaluateJavaScript("[...document.querySelectorAll('input')].map(i=>i.files.length)") as? [Int] == [0, 1])
        #expect(await PageUpload.attach(in: view, startURL: url, name: "c.pdf", bytes: data, field: "Missing") == "field not found")
        _ = try await view.evaluateJavaScript("document.querySelector('input').setAttribute('aria-label','Документ')")
        #expect(await PageUpload.attach(in: view, startURL: url, name: "c.pdf", bytes: data, field: "Документ") == "ambiguous field")
    }
}
