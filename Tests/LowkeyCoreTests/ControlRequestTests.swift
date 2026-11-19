import Foundation
import Testing
import LowkeyCore

@Suite struct ControlRequestTests {
    @Test(arguments: ["open", "hide", "toggle"]) func roundTrip(_ command: String) throws {
        let request = try #require(ControlRequest(["HA-1", command]))
        let decoded = try #require(ControlRequest(payload: request.payload))
        #expect(decoded.command == request.command)
        #expect(decoded.alias == "HA-1")
    }

    @Test func pdfRoundTrip() throws {
        let request = try #require(ControlRequest(["HA", "save-pdf", "/tmp/Full page.pdf"]))
        #expect(request.command.isPDFExport)
        #expect(ControlRequest(payload: request.payload)?.command == request.command)
        for args in [[], ["relative.pdf"], ["/tmp/page.txt"], ["/tmp/page.pdf", "extra"], ["/tmp/bad\0.pdf"]] {
            #expect(ControlRequest(["HA", "save-pdf"] + args) == nil)
        }
    }

    @Test func uploadRoundTrip() throws {
        let file = Data([0, 255, 10, 0])
        let request = try #require(ControlRequest(alias: "HA", filename: "Файл 1.pdf", bytes: file))
        #expect(ControlRequest(payload: request.payload)?.command == .upload(name: "Файл 1.pdf", bytes: file))
        #expect(ControlRequest(payload: Data("upload HA /tmp/private.pdf".utf8)) == nil)
        #expect(ControlRequest(alias: "HA", filename: "../test.pdf", bytes: file) == nil)
        #expect(ControlRequest(["HA", "click", "Обновить"])?.command == .click("Обновить"))
    }

    @Test(arguments: ["toggle", "toggle *", "open https://example.org", "reload HA", "open HA extra", "toggle HA\n"])
    func rejectsInvalidInput(_ text: String) {
        #expect(ControlRequest(payload: Data(text.utf8)) == nil)
    }
}
