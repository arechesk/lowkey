import AppKit
import LowkeyCore

/// A tiny icon button for the window strip. Draws a `Glyph`, reports the click modifiers.
@MainActor final class GlyphButton: NSView {
    var glyph: Glyph { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { needsDisplay = true } }
    var onPress: ((NSEvent.ModifierFlags) -> Void)?
    var label: String { didSet { toolTip = label } }

    private var hovering = false
    private var pressed = false
    private var trackingArea: NSTrackingArea?

    init(glyph: Glyph, label: String) {
        self.glyph = glyph
        self.label = label
        super.init(frame: .zero)
        toolTip = label
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside != pressed { pressed = inside; needsDisplay = true }
    }

    override func mouseUp(with event: NSEvent) {
        let fire = pressed && isEnabled && bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        needsDisplay = true
        if fire { onPress?(event.modifierFlags) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let tokens = lowkeyTokens
        if isEnabled && (hovering || pressed) {
            NSColor(tokens.ink, alpha: pressed ? 0.16 : 0.08).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 0), xRadius: 3, yRadius: 3).fill()
        }
        let color: NSColor
        if !isEnabled { color = NSColor(tokens.muted, alpha: 0.35) }
        else if hovering && (glyph == .close || glyph == .terminate) { color = NSColor(srgbRed: 0.71, green: 0.33, blue: 0.25, alpha: 1) }
        else { color = NSColor(hovering ? tokens.ink : tokens.muted) }
        let side = min(bounds.height - 2, 14.4)
        glyph.draw(in: NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side),
                   color: color, background: NSColor(tokens.panel))
    }

    // Accessibility: a plain button.
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { label }
    override func isAccessibilityEnabled() -> Bool { isEnabled }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onPress?([])
        return true
    }
}

/// The accent line at the top of every Lowkey window. While a page loads it shows progress.
@MainActor final class AccentBar: NSView {
    var progress: Double? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor(lowkeyTokens.accent)
        guard let progress else {
            accent.setFill()
            bounds.fill()
            return
        }
        accent.withAlphaComponent(0.3).setFill()
        bounds.fill()
        accent.setFill()
        NSRect(x: 0, y: 0, width: bounds.width * max(0.05, min(1, progress)), height: bounds.height).fill()
    }
}

/// The thin control strip: close on the left, back/start/forward on the right.
/// Dragging the strip moves the window; double-click zooms it.
@MainActor final class ChromeStrip: NSView {
    static let height: CGFloat = 20.02

    let closeButton = GlyphButton(glyph: .close, label: "Close")
    private(set) var trailing: [GlyphButton] = []
    private let stack = NSStackView()

    init(trailing: [GlyphButton]) {
        self.trailing = trailing
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)
        addSubview(stack)
        for button in trailing {
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 26).isActive = true
            button.heightAnchor.constraint(equalToConstant: Self.height).isActive = true
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 26),
            closeButton.heightAnchor.constraint(equalToConstant: Self.height),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.zoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let tokens = lowkeyTokens
        NSColor(tokens.panel).setFill()
        bounds.fill()
    }

}

/// A titled, resizable window with the system title bar hidden and Lowkey's strip in its place.
/// Keeps native rounded corners, shadow, resizing and full screen.
@MainActor class ChromeWindow: NSWindow, PageThemeProviding {
    static let pageThemeDidChange = Notification.Name("LowkeyPageThemeDidChange")
    var pageIsDark: Bool? {
        didSet {
            guard pageIsDark != oldValue else { return }
            applyTheme()
            NotificationCenter.default.post(name: Self.pageThemeDidChange, object: self)
        }
    }

    let accentBar = AccentBar()
    let strip: ChromeStrip
    /// Place the window's content here.
    let body = NSView()
    private let separator = NSBox()
    private var themeObserver: NSObjectProtocol?

    init(contentRect: NSRect, trailing: [GlyphButton]) {
        strip = ChromeStrip(trailing: trailing)
        super.init(contentRect: contentRect,
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = false
        tabbingMode = .disallowed
        collectionBehavior.insert(.fullScreenPrimary)
        isReleasedWhenClosed = false
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(kind)?.isHidden = true
        }

        let root = NSView()
        accentBar.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .custom
        separator.borderWidth = 0
        separator.translatesAutoresizingMaskIntoConstraints = false
        body.translatesAutoresizingMaskIntoConstraints = false
        for view in [body, accentBar, strip, separator] { root.addSubview(view) }
        NSLayoutConstraint.activate([
            accentBar.topAnchor.constraint(equalTo: root.topAnchor),
            accentBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            accentBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            accentBar.heightAnchor.constraint(equalToConstant: 2),
            strip.topAnchor.constraint(equalTo: accentBar.bottomAnchor),
            strip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separator.topAnchor.constraint(equalTo: strip.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            body.topAnchor.constraint(equalTo: separator.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        contentView = root
        hideTitlebarContainer()
        applyTheme()
        themeObserver = NotificationCenter.default.addObserver(forName: ThemeCenter.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyTheme() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(fullScreenChanged),
                                               name: NSWindow.didExitFullScreenNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(fullScreenChanged),
                                               name: NSWindow.didEnterFullScreenNotification, object: self)
    }

    deinit {
        if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// The transparent title bar still catches clicks; hide it so the strip and the page get them.
    private func hideTitlebarContainer() {
        guard let frameView = contentView?.superview else { return }
        for view in frameView.subviews where String(describing: type(of: view)).contains("NSTitlebarContainerView") {
            view.isHidden = true
        }
    }

    @objc private func fullScreenChanged() { hideTitlebarContainer() }

    func applyTheme() {
        let center = ThemeCenter.shared
        let tokens = center.tokens(pageIsDark: pageIsDark)
        strip.appearance = center.chromeAppearance(pageIsDark: pageIsDark)
        separator.fillColor = NSColor(tokens.stroke)
        backgroundColor = NSColor(tokens.panel)
        for view in [accentBar, strip, strip.closeButton] as [NSView] { view.needsDisplay = true }
        strip.trailing.forEach { $0.needsDisplay = true }
        strip.subviews.forEach { $0.needsDisplay = true }
        strip.subviews.flatMap(\.subviews).forEach { $0.needsDisplay = true }
        // Popup origin bars are chrome too; leave the WKWebView's appearance alone.
        for origin in body.subviews.compactMap({ $0 as? OriginBar }) {
            origin.needsDisplay = true
            origin.subviews.forEach { $0.needsDisplay = true }
        }
    }
}
