import AppKit
import Testing
import LowkeyCore
import BobukUI
@testable import Lowkey

/// lowkey's theme on BobukKit's window shell and prompt panel. No visible windows or keypresses.
@MainActor @Suite(.serialized) struct LowkeyWindowTests {
    private func withMode<T>(_ mode: ThemeMode, _ body: () throws -> T) rethrows -> T {
        let saved = ThemeCenter.shared.appearance
        defer { ThemeCenter.shared.appearance = saved }
        ThemeCenter.shared.appearance.mode = mode
        return try body()
    }

    private func makeWindow() -> LowkeyWindow {
        _ = NSApplication.shared
        return LowkeyWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
                            trailing: [StripButton(glyph: .back, label: "Back"), StripButton(glyph: .start, label: "Start"),
                                       StripButton(glyph: .forward, label: "Forward")])
    }

    @Test func menuOwnsCommandWAndPaletteChromeUsesStrokeAndRed() {
        withMode(.light) {
            let window = makeWindow()
            defer { window.close() }
            #expect(!window.closesOnCommandW)
            #expect(!window.routesEditCommands)
            let tokens = ThemeCenter.shared.stripTokens(page: window.pageTheme)
            let style = window.chromeStyle
            #expect(style.panel == NSColor(tokens.panel))
            #expect(style.ink == NSColor(tokens.ink))
            #expect(style.muted == NSColor(tokens.muted))
            #expect(style.accent == NSColor(tokens.accent))
            #expect(style.separator == NSColor(tokens.stroke))
            #expect(style.destructiveHover == ChromeStyle.defaultDestructive)
            #expect(window.strip.appearance?.name == .aqua)
        }
    }

    @Test func tintedStripTakesThePageColorWithoutLineOrRed() {
        withMode(.tint) {
            let window = makeWindow()
            defer { window.close() }
            let tint = RGB(r: 0.1, g: 0.2, b: 0.5)
            window.tint = tint
            let style = window.chromeStyle
            #expect(style.panel == NSColor(tint))
            #expect(style.separator == style.panel)
            #expect(style.destructiveHover == nil)
            #expect(window.strip.appearance?.name == .darkAqua)
            // A mode change recolors open windows.
            ThemeCenter.shared.appearance.mode = .dark
            #expect(window.chromeStyle.separator == NSColor(ThemeCenter.shared.stripTokens(page: window.pageTheme).stroke))
            #expect(window.chromeStyle.destructiveHover != nil)
        }
    }

    @Test func settingsWindowIsFixedWithTerminateClose() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppController(store: Store(configURL: root.appendingPathComponent("config.json")))
        let controller = SettingsWindowController(app: app)
        defer { NSWindow.removeFrame(usingName: "LowkeySettings") }
        let window = try #require(controller.window as? LowkeyWindow)
        defer { window.close() }
        #expect(!window.styleMask.contains(.resizable))
        #expect(!window.collectionBehavior.contains(.fullScreenPrimary))
        #expect(!window.closesOnCommandW)
        #expect(window.closeButton.glyph == .terminate)
        #expect(window.closeButton.label == "Close · ⌘W")
        #expect(window.title == "lowkey Settings")
    }

    @Test func addressPanelIsAPrompt() {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppController(store: Store(configURL: root.appendingPathComponent("config.json")))
        let panel = AddressPanel(app: app)
        defer { panel.close() }
        #expect(panel.kind == .prompt)
        #expect(panel.level == .floating)
        #expect(panel.collectionBehavior == [.moveToActiveSpace, .fullScreenAuxiliary])
        #expect(panel.dismissesOnResignKey && panel.dismissesOnAppDeactivation && panel.dismissesOnCommandW)
        #expect(!panel.routesEditCommands)
        #expect(panel.canBecomeKey && !panel.canBecomeMain)
    }

    @Test func rendersPreviews() throws {
        guard let folder = ProcessInfo.processInfo.environment["BOBUKKIT_PREVIEW_DIR"] else { return }
        let output = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func render(_ window: LowkeyWindow, _ name: String) throws {
            let content = try #require(window.contentView)
            content.layoutSubtreeIfNeeded()
            let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name))
        }
        try withMode(.light) {
            let window = makeWindow()
            defer { window.close() }
            try render(window, "lowkey-window-light.png")
        }
        try withMode(.tint) {
            let window = makeWindow()
            defer { window.close() }
            window.tint = RGB(r: 0.1, g: 0.2, b: 0.5)
            window.accentBar.progress = 0.4
            try render(window, "lowkey-window-tint.png")
        }
    }
}
