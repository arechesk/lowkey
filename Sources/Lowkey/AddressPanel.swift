import AppKit
import LowkeyCore

/// The ⌘L prompt: an alias or an address, with suggestions from saved sites and input history.
@MainActor final class AddressPanel: NSPanel, NSTextFieldDelegate, PageThemeProviding {
    private unowned let app: AppController
    private weak var target: WebWindowController?
    private var newWindow = false
    private var inCurrentProfile = false
    private var suggestions: [Suggestion] = []
    /// nil until the user picks a row with the arrow keys or the mouse.
    private var selected: Int?

    private let background = PanelBackground()
    private let accent = AccentBar()
    private let infoRow = NSStackView()
    private let infoGlyph = GlyphView(glyph: .lock)
    private let infoLabel = NSTextField(labelWithString: "")
    private let arrow = NSTextField(labelWithString: "→")
    private let field = NSTextField()
    private let list = NSStackView()
    private let footer = NSTextField(labelWithString: "")
    private let infoSeparator = Separator()
    private let listSeparator = Separator()
    private let footerSeparator = Separator()
    private var themeObserver: NSObjectProtocol?
    private var pageThemeObserver: NSObjectProtocol?
    var pageIsDark: Bool? { target?.chrome.pageIsDark }
    private var themeTokens: ThemeTokens { ThemeCenter.shared.tokens(pageIsDark: pageIsDark) }

    static let width: CGFloat = 560

    init(app: AppController) {
        self.app = app
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 120),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        build()
        themeObserver = NotificationCenter.default.addObserver(forName: ThemeCenter.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyTheme() }
        }
        pageThemeObserver = NotificationCenter.default.addObserver(forName: ChromeWindow.pageThemeDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyTheme() }
        }
        // Switching to another app dismisses the prompt.
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.orderOut(nil) }
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func build() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        infoGlyph.translatesAutoresizingMaskIntoConstraints = false
        infoGlyph.widthAnchor.constraint(equalToConstant: 10).isActive = true
        infoGlyph.heightAnchor.constraint(equalToConstant: 10).isActive = true
        infoLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        infoLabel.lineBreakMode = .byTruncatingMiddle
        infoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        infoRow.orientation = .horizontal
        infoRow.spacing = 7
        infoRow.edgeInsets = NSEdgeInsets(top: 9, left: 16, bottom: 9, right: 16)
        infoRow.addArrangedSubview(infoGlyph)
        infoRow.addArrangedSubview(infoLabel)

        arrow.font = .systemFont(ofSize: 17)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 18)
        field.placeholderString = "Alias or address"
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.setAccessibilityLabel("Alias or address")
        let input = NSStackView(views: [arrow, field])
        input.orientation = .horizontal
        input.spacing = 10
        input.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

        list.orientation = .vertical
        list.spacing = 0
        list.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)

        footer.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        let footerRow = NSStackView(views: [footer])
        footerRow.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 9, right: 16)

        for view in [accent, infoRow, infoSeparator, input, listSeparator, list, footerSeparator, footerRow] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        accent.heightAnchor.constraint(equalToConstant: 2).isActive = true

        background.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            background.widthAnchor.constraint(equalToConstant: Self.width),
        ])
        contentView = background
    }

    // MARK: Showing

    func show(target: WebWindowController?, newWindow: Bool, prefill: String?, message: String?,
              inCurrentProfile: Bool = false) {
        self.target = target
        self.newWindow = newWindow
        self.inCurrentProfile = inCurrentProfile
        field.placeholderString = inCurrentProfile ? "Address in this profile" : "Alias or address"
        field.setAccessibilityLabel(inCurrentProfile ? "Address in this profile" : "Alias or address")
        field.stringValue = prefill ?? ""
        selected = nil
        setInfo(message: message)
        applyTheme()
        refresh()
        position()
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    private func setInfo(message: String?) {
        if let message {
            infoGlyph.isHidden = true
            infoLabel.stringValue = message
            infoLabel.font = .systemFont(ofSize: 11.5)
            infoLabel.textColor = NSColor(srgbRed: 0.75, green: 0.33, blue: 0.25, alpha: 1)
            infoRow.isHidden = false
        } else if let url = target?.webView.url, url.scheme != "about" {
            infoGlyph.isHidden = url.scheme != "https"
            infoLabel.stringValue = url.absoluteString
            infoLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
            infoLabel.textColor = NSColor(themeTokens.muted)
            infoRow.isHidden = false
        } else {
            infoRow.isHidden = true
        }
        infoSeparator.isHidden = infoRow.isHidden
    }

    private func position() {
        layoutIfNeededForSize()
        let size = frame.size
        if let parent = target?.window, parent.isVisible, !parent.isMiniaturized {
            let top = parent.frame.maxY - 56
            setFrameOrigin(NSPoint(x: parent.frame.midX - size.width / 2, y: top - size.height))
        } else if let screen = NSScreen.main {
            let area = screen.visibleFrame
            setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.maxY - area.height * 0.28 - size.height))
        }
    }

    /// Fits the window to its content, keeping the top edge in place.
    private func layoutIfNeededForSize() {
        background.layoutSubtreeIfNeeded()
        let size = background.fittingSize
        let top = frame.maxY
        setFrame(NSRect(x: frame.minX, y: top - size.height, width: Self.width, height: size.height), display: true)
        invalidateShadow()
    }

    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }

    override func cancelOperation(_ sender: Any?) { orderOut(nil) }


    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        if flags == .command, key == "w" {
            orderOut(nil)
            return true
        }
        // ⌘C with nothing selected copies the current page address.
        if flags == .command, key == "c", let editor = field.currentEditor(), editor.selectedRange.length == 0,
           let url = target?.webView.url, url.scheme != "about" {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            setInfo(message: nil)
            infoLabel.stringValue = "Copied: \(url.absoluteString)"
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: Suggestions

    private func refresh() {
        suggestions = Suggestions.make(query: field.stringValue, sites: app.store.config.sites, history: app.store.history)
        if let index = selected, index >= suggestions.count { selected = suggestions.isEmpty ? nil : suggestions.count - 1 }
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, suggestion) in suggestions.enumerated() {
            let row = SuggestionRow(suggestion: suggestion, selected: index == selected, tokens: themeTokens)
            row.onChoose = { [weak self] in self?.submit(text: suggestion.text) }
            row.onRemove = { [weak self] in
                self?.app.store.removeHistory(suggestion.text)
                self?.refresh()
            }
            list.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: list.widthAnchor, constant: -12).isActive = true
        }
        list.isHidden = suggestions.isEmpty
        listSeparator.isHidden = suggestions.isEmpty
        let browser = self.target as? BrowserWindowController
        let target = newWindow || browser?.kind != .ordinary ? "new window" : "this window"
        if inCurrentProfile {
            footer.stringValue = "↩ open in this profile   ↑↓ choose   ⌘C copy URL   esc close"
        } else {
            footer.stringValue = "↩ open (address: \(target))   ⌘↩ new window   ↑↓ choose   ⌘C copy URL   esc close"
        }
        footer.textColor = NSColor(themeTokens.muted)
        if isVisible { layoutIfNeededForSize() }
    }

    func controlTextDidChange(_ obj: Notification) {
        selected = nil
        setInfo(message: nil)
        refresh()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            guard !suggestions.isEmpty else { return true }
            selected = selected.map { min($0 + 1, suggestions.count - 1) } ?? 0
            refresh()
            return true
        case #selector(NSResponder.moveUp(_:)):
            guard let index = selected else { return true }
            selected = index == 0 ? nil : index - 1
            refresh()
            return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            if let index = selected, suggestions.indices.contains(index) {
                submit(text: suggestions[index].text)
            } else {
                submitTyped()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            orderOut(nil)
            return true
        default:
            return false
        }
    }

    /// Typed text that is neither an alias nor an address falls back to the first suggestion.
    private func submitTyped() {
        let text = field.stringValue
        if case .invalid = AddressResolver.resolve(text, sites: app.store.config.sites), let first = suggestions.first {
            submit(text: first.text)
        } else {
            submit(text: text)
        }
    }

    private func submit(text: String) {
        let commandHeld = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
        let target = self.target
        if let error = app.submit(text, target: target, newWindow: newWindow || commandHeld,
                                  inCurrentProfile: inCurrentProfile) {
            setInfo(message: error)
            layoutIfNeededForSize()
            NSSound.beep()
            return
        }
        orderOut(nil)
    }

    // MARK: Theme

    private func applyTheme() {
        let tokens = themeTokens
        appearance = ThemeCenter.shared.chromeAppearance(pageIsDark: pageIsDark)
        background.needsDisplay = true
        accent.needsDisplay = true
        arrow.textColor = NSColor(tokens.accent)
        field.textColor = NSColor(tokens.ink)
        footer.textColor = NSColor(tokens.muted)
        for separator in [infoSeparator, listSeparator, footerSeparator] { separator.needsDisplay = true }
        infoGlyph.needsDisplay = true
        if isVisible { refresh() }
    }
}

/// Rounded panel with a thin border, drawn in the theme colors.
@MainActor private final class PanelBackground: NSView {
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let tokens = lowkeyTokens
        NSColor(tokens.panel).setFill()
        bounds.fill()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        NSColor(tokens.line).setStroke()
        border.lineWidth = 1
        border.stroke()
    }
}

@MainActor private final class Separator: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 1) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(lowkeyTokens.stroke).setFill()
        bounds.fill()
    }
}

/// One suggestion: an amber alias key for saved sites, or a history entry with a remove cross.
@MainActor private final class SuggestionRow: NSView {
    var onChoose: (() -> Void)?
    var onRemove: (() -> Void)?
    private let isSelected: Bool
    private let isHistory: Bool
    private var hovering = false
    private let removeButton = GlyphButton(glyph: .close, label: "Remove from history")
    private var trackingArea: NSTrackingArea?

    init(suggestion: Suggestion, selected: Bool, tokens: ThemeTokens) {
        isSelected = selected
        if case .history = suggestion { isHistory = true } else { isHistory = false }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true

        let badge = NSTextField(labelWithString: "")
        badge.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 4
        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 12.5)
        title.textColor = NSColor(tokens.ink)
        title.lineBreakMode = .byTruncatingMiddle
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let detail = NSTextField(labelWithString: "")
        detail.font = .systemFont(ofSize: 10.5)
        detail.textColor = NSColor(tokens.muted)
        detail.lineBreakMode = .byTruncatingMiddle
        detail.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)

        switch suggestion {
        case .site(let site):
            badge.stringValue = site.alias.uppercased()
            badge.textColor = NSColor(tokens.keyInk)
            badge.layer?.backgroundColor = NSColor(tokens.accent).cgColor
            title.stringValue = site.displayTitle
            detail.stringValue = site.url?.host() ?? site.startURL
            removeButton.isHidden = true
            setAccessibilityLabel("Site \(site.alias), \(site.displayTitle)")
        case .history(let text):
            badge.stringValue = "↺"
            badge.textColor = NSColor(tokens.muted)
            badge.layer?.backgroundColor = NSColor(tokens.ink, alpha: 0.07).cgColor
            title.stringValue = text
            removeButton.isHidden = !selected
            setAccessibilityLabel("History \(text)")
        }
        removeButton.onPress = { [weak self] _ in self?.onRemove?() }

        let stack = NSStackView(views: [badge, title, NSView(), detail, removeButton])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            badge.heightAnchor.constraint(equalToConstant: 18),
            removeButton.widthAnchor.constraint(equalToConstant: 18),
            removeButton.heightAnchor.constraint(equalToConstant: 18),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        setAccessibilityRole(.button)
        setAccessibilityElement(true)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        if isHistory { removeButton.isHidden = false }
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        removeButton.isHidden = !(isHistory && isSelected)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onChoose?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onChoose?()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected || hovering else { return }
        NSColor(lowkeyTokens.ink, alpha: isSelected ? 0.09 : 0.05).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
    }
}
