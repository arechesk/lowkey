import Foundation

/// Light/dark classification for a page's background, not its `prefers-color-scheme` preference.
/// A small dead band prevents switching repeatedly when the page animates through mid-gray.
public enum PageAppearance {
    public static func isDark(background: RGB, previous: Bool? = nil) -> Bool {
        switch previous {
        case true: background.luminance < 0.22
        case false: background.luminance < 0.15
        case nil: background.luminance < 0.18
        }
    }
}
