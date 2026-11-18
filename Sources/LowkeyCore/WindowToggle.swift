/// Visibility policy shared by single-site and wildcard toggle commands.
public enum WindowToggle: Equatable, Sendable {
    case hide, show

    public static func action(isVisible: Bool, isMiniaturized: Bool) -> WindowToggle {
        isVisible && !isMiniaturized ? .hide : .show
    }

    /// The wildcard touches only existing saved-site windows. Visible means not minimized.
    public static func groupAction(visibleWindows: [Bool]) -> WindowToggle {
        visibleWindows.contains(true) ? .hide : .show
    }
}
