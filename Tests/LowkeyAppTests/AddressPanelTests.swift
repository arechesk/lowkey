import AppKit
import SwiftUI
import Testing
import LowkeyCore
import BobukUI
@testable import Lowkey

@Suite(.serialized) @MainActor
struct AddressPanelTests {
    @Test func sharedRowsKeepColumnsAlignedAndNavigationReturnsToTypedInput() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(configURL: root.appendingPathComponent("config.json"))
        let sites = [Site(alias: "HA", title: "Home Control", startURL: "https://home.example.test"),
                     Site(alias: "NOTES", title: "Project Notes", startURL: "https://notes.example.test")]
        #expect(store.update(Config(sites: sites)).isEmpty)
        store.record("https://example.com/demo")
        let app = AppController(store: store)
        let panel = AddressPanel(app: app)
        defer { panel.close() }
        let key = NSApp.keyWindow
        panel.configure(target: nil, newWindow: false, prefill: nil, message: nil)
        #expect(NSApp.keyWindow === key)
        #expect(!panel.isVisible)
        guard let content = panel.contentView else { Issue.record("Missing content"); return }
        func rows(_ view: NSView) -> [NSHostingView<SuggestionRow>] {
            if let row = view as? NSHostingView<SuggestionRow> { return [row] }
            return view.subviews.flatMap { rows($0) }
        }
        func fields(_ view: NSView) -> [NSTextField] {
            (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { fields($0) }
        }
        let initial = rows(content)
        #expect(initial.map { $0.rootView.suggestion } == sites.map(Suggestion.site))
        #expect(initial.allSatisfy { !$0.rootView.selected })
        #expect(Set(initial.map { $0.rootView.badgeWidth }).count == 1)
        #expect(initial.allSatisfy { abs($0.frame.height - PickerMetrics.rowHeight) < 0.01 })
        #expect(Set(initial.map { $0.frame.width }).count == 1)
        #expect(abs(panel.frame.width - AddressPanel.width) < 0.01)
        let editable = fields(content).first { $0.isEditable }
        let field = try #require(editable)
        let editor = NSTextView()
        #expect(panel.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        #expect(rows(content).map { $0.rootView.selected } == [true, false])
        #expect(panel.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:))))
        #expect(rows(content).allSatisfy { !$0.rootView.selected })
        #expect(app.allBrowsers.isEmpty)

        if let folder = ProcessInfo.processInfo.environment["BOBUKKIT_PREVIEW_DIR"] {
            let output = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: output.appendingPathComponent("lowkey-address.png"))
        }

        func query(_ text: String) {
            field.stringValue = text
            panel.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        }
        query("demo")
        #expect(rows(content).map { $0.rootView.suggestion } == [.history("https://example.com/demo")])
        query("")
        #expect(rows(content).map { $0.rootView.suggestion } == sites.map(Suggestion.site))
        query("demo")
        let history = try #require(rows(content).first { if case .history = $0.rootView.suggestion { return true }; return false })
        history.rootView.onRemove()
        #expect(rows(content).isEmpty)
        #expect(store.history.entries.isEmpty)
        #expect(store.config.sites == sites)
    }
}
