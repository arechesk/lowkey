import AppKit
import LowkeyCore

extension NSColor {
    convenience init(_ rgb: RGB, alpha: CGFloat = 1) {
        self.init(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
    }

    var rgb: RGB? {
        guard let color = usingColorSpace(.sRGB) else { return nil }
        return RGB(r: Double(color.redComponent), g: Double(color.greenComponent), b: Double(color.blueComponent))
    }
}

/// Windows supply their own page classification so different pages can use different chrome modes.
@MainActor protocol PageThemeProviding: AnyObject {
    var pageIsDark: Bool? { get }
}

extension NSView {
    @MainActor var lowkeyTokens: ThemeTokens {
        ThemeCenter.shared.tokens(pageIsDark: (window as? PageThemeProviding)?.pageIsDark)
    }
}

/// Lowkey's chrome theme. Web pages keep the system appearance and their own colors.
@MainActor final class ThemeCenter {
    static let shared = ThemeCenter()
    static let didChange = Notification.Name("LowkeyThemeDidChange")

    private var systemObservation: NSKeyValueObservation?

    var appearance = AppearanceConfig() {
        didSet { if appearance != oldValue { notify() } }
    }

    private init() {
        // Lowkey never sets NSApp.appearance, so this follows System Settings.
        systemObservation = NSApp.observe(\.effectiveAppearance) { _, _ in
            DispatchQueue.main.async { ThemeCenter.shared.notify() }
        }
    }

    var systemIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    var isDark: Bool { isDark(pageIsDark: nil) }

    func isDark(pageIsDark: Bool?) -> Bool {
        switch appearance.mode {
        case .page: pageIsDark ?? systemIsDark
        case .system: systemIsDark
        case .light: false
        case .dark: true
        }
    }

    var tokens: ThemeTokens { tokens(pageIsDark: nil) }

    func tokens(pageIsDark: Bool?) -> ThemeTokens {
        ThemeTokens(colors: appearance.colors(dark: isDark(pageIsDark: pageIsDark)))
    }

    /// Appearance for views drawn on the themed panel (tooltips, text fields, menus).
    var chromeAppearance: NSAppearance? { chromeAppearance(pageIsDark: nil) }

    func chromeAppearance(pageIsDark: Bool?) -> NSAppearance? {
        NSAppearance(named: tokens(pageIsDark: pageIsDark).isDark ? .darkAqua : .aqua)
    }

    /// Appearance for the Settings window: the chosen mode, or the system one.
    var windowAppearance: NSAppearance? {
        appearance.mode == .system || appearance.mode == .page ? nil : NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
