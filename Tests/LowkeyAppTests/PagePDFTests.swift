import Testing
import WebKit
import PDFKit
import LowkeyCore
@testable import Lowkey

@MainActor @Suite(.serialized) struct PagePDFTests {
    @Test func printsEntireDocumentAndPrintStyles() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 480, height: 300), configuration: configuration)
        let origin = URL(string: "https://pdf-demo.invalid")!
        view.loadSimulatedRequest(URLRequest(url: origin), responseHTML: """
        <style>@media print { .screen { display: none } } section { height: 1800px }</style>
        <div class="screen">SCREENONLY</div><section>FIRSTMARKER</section><p>LASTMARKER</p>
        """)
        let deadline = ContinuousClock.now + .seconds(5)
        while view.isLoading && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("whole page.pdf")
        #expect(await PageControls.run(.savePDF, args: [destination.path], view: view, site: origin) == "ok")
        let document = try #require(PDFDocument(url: destination))
        #expect(document.pageCount > 1)
        let text = try #require(document.string)
        #expect(text.contains("FIRSTMARKER"))
        #expect(text.contains("LASTMARKER"))
        #expect(!text.contains("SCREENONLY"))
        let original = try Data(contentsOf: destination)
        let retry = await PageControls.run(.savePDF, args: [destination.path], view: view, site: origin)
        #expect(retry.hasPrefix("PDF export failed:"))
        #expect(try Data(contentsOf: destination) == original)
        #expect(await PageControls.run(.savePDF, args: [destination.path], view: view, site: URL(string: "https://other.invalid")!) == "wrong site origin")
    }
}
