import Foundation

public struct RGB: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// `#RRGGBB`, case-insensitive.
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("#") else { return nil }
        text.removeFirst()
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        r = Double((value >> 16) & 255) / 255
        g = Double((value >> 8) & 255) / 255
        b = Double(value & 255) / 255
    }

    public var hex: String {
        String(format: "#%02x%02x%02x", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    public func mixed(with other: RGB, _ amount: Double) -> RGB {
        RGB(r: r + (other.r - r) * amount, g: g + (other.g - g) * amount, b: b + (other.b - b) * amount)
    }

    public var luminance: Double {
        func channel(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    public func contrast(with other: RGB) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// Colors of Lowkey's own chrome. Web pages keep their own colors.
public struct ThemeTokens: Equatable, Sendable {
    public let panel: RGB
    public let accent: RGB
    public let ink: RGB
    public let muted: RGB
    public let line: RGB
    public let stroke: RGB
    public let hover: RGB
    public let field: RGB
    public let keyInk: RGB
    /// The accent strip is hard to see against the panel.
    public let lowAccentContrast: Bool
    /// The panel is a page color (Tint mode), so fixed colors such as the close red may vanish on it.
    public let isTinted: Bool

    static let darkInk = RGB(hex: "#222a2e")!
    static let lightInk = RGB(hex: "#eef1ec")!

    static func ink(on color: RGB) -> RGB {
        color.contrast(with: darkInk) >= color.contrast(with: lightInk) ? darkInk : lightInk
    }

    public init(colors: ThemeColors) {
        self.init(panel: RGB(hex: colors.panel) ?? RGB(hex: "#f7f8f5")!,
                  accent: RGB(hex: colors.accent) ?? RGB(hex: "#885500")!, isTinted: false)
    }

    /// A panel tinted with a page color: the accent comes from the palette, the rest from the tint.
    public init(tint: RGB, colors: ThemeColors) {
        self.init(panel: tint, accent: ThemeTokens(colors: colors).accent, isTinted: true)
    }

    private init(panel: RGB, accent: RGB, isTinted: Bool) {
        self.isTinted = isTinted
        let ink = Self.ink(on: panel)
        self.panel = panel
        self.accent = accent
        self.ink = ink
        muted = panel.mixed(with: ink, 0.78)
        line = panel.mixed(with: ink, 0.3)
        stroke = panel.mixed(with: ink, 0.15)
        hover = panel.mixed(with: ink, 0.07)
        field = panel.mixed(with: Self.ink(on: ink), 0.15)
        keyInk = Self.ink(on: accent)
        lowAccentContrast = panel.contrast(with: accent) < 3
    }

    /// Whether the panel reads as a dark surface (for the system controls drawn on it).
    public var isDark: Bool { ink == Self.lightInk }
}

public struct ThemePreset: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let light: (panel: String, accent: String)
    public let dark: (panel: String, accent: String)

    public func colors(dark isDark: Bool) -> ThemeColors {
        let pair = isDark ? dark : light
        return ThemeColors(preset: id, panel: pair.panel, accent: pair.accent)
    }

    public static let amber = ThemePreset(id: "amber", title: "Amber",
                                          light: ("#f7f8f5", "#885500"), dark: ("#222a2e", "#e7bb74"))

    /// Chrome adaptations of popular editor palettes, not full editor themes.
    public static let all: [ThemePreset] = [
        amber,
        ThemePreset(id: "sage", title: "Sage", light: ("#f1f4ee", "#42664e"), dark: ("#242d27", "#a4c69c")),
        ThemePreset(id: "ocean", title: "Ocean", light: ("#eef4f6", "#286887"), dark: ("#1d2b34", "#8ec5df")),
        ThemePreset(id: "clay", title: "Terracotta", light: ("#f8f1ec", "#9c4e32"), dark: ("#302724", "#e6a58a")),
        ThemePreset(id: "dracula", title: "Dracula", light: ("#f8f8f2", "#7544a6"), dark: ("#282a36", "#bd93f9")),
        ThemePreset(id: "nord", title: "Nord", light: ("#eceff4", "#5e81ac"), dark: ("#2e3440", "#88c0d0")),
        ThemePreset(id: "catppuccin", title: "Catppuccin", light: ("#eff1f5", "#8839ef"), dark: ("#1e1e2e", "#cba6f7")),
        ThemePreset(id: "gruvbox", title: "Gruvbox", light: ("#fbf1c7", "#af3a03"), dark: ("#282828", "#fe8019")),
        ThemePreset(id: "solarized", title: "Solarized", light: ("#fdf6e3", "#268bd2"), dark: ("#002b36", "#2aa198")),
        ThemePreset(id: "tokyo-night", title: "Tokyo Night", light: ("#e1e2e7", "#2e7de9"), dark: ("#1a1b26", "#7aa2f7")),
        ThemePreset(id: "one", title: "One Light / One Dark", light: ("#fafafa", "#4078f2"), dark: ("#282c34", "#61afef")),
        ThemePreset(id: "rose-pine", title: "Rosé Pine", light: ("#faf4ed", "#907aa9"), dark: ("#191724", "#c4a7e7")),
    ]

    public static func named(_ id: String) -> ThemePreset? { all.first { $0.id == id } }
}
