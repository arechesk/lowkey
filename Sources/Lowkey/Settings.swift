import AppKit
import BobukUI
import LowkeyCore
import SwiftUI

@MainActor final class SettingsModel: ObservableObject {
    private unowned let app: AppController
    @Published var draft: Config { didSet { commit() } }
    @Published var selection: UUID?
    @Published var problems: [String] = []
    /// Which mode's colors the color pickers edit.
    @Published var editingDark: Bool

    init(app: AppController) {
        self.app = app
        draft = app.store.config
        selection = app.store.config.sites.first?.id
        editingDark = ThemeCenter.shared.isDark
    }

    var store: Store { app.store }

    /// Saves valid changes at once. With site problems, the appearance still saves and the sites wait.
    private func commit() {
        problems = draft.problems()
        if problems.isEmpty {
            problems = store.update(draft)
        } else {
            var config = store.config
            config.appearance = draft.appearance
            store.update(config)
        }
        app.applyAppearance(draft.appearance)
    }

    var selectedIndex: Int? { draft.sites.firstIndex { $0.id == selection } }

    func site<T>(_ keyPath: WritableKeyPath<Site, T>, default value: T) -> Binding<T> {
        Binding(get: { [weak self] in
            guard let self, let index = self.selectedIndex else { return value }
            return self.draft.sites[index][keyPath: keyPath]
        }, set: { [weak self] newValue in
            guard let self, let index = self.selectedIndex else { return }
            self.draft.sites[index][keyPath: keyPath] = newValue
        })
    }

    func addSite() {
        var number = draft.sites.count + 1
        while draft.site(alias: "SITE\(number)") != nil { number += 1 }
        let site = Site(alias: "SITE\(number)", title: "", startURL: "https://")
        draft.sites.append(site)
        selection = site.id
    }

    func removeSelected() {
        guard let index = selectedIndex else { return }
        let site = draft.sites[index]
        let alert = NSAlert()
        alert.messageText = "Remove “\(site.displayTitle)”?"
        alert.informativeText = "lowkey closes its window and deletes its profile: cookies, sign-ins and site data. This can’t be undone."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let wasSaved = store.config.site(id: site.id) != nil
        draft.sites.remove(at: index)
        selection = draft.sites.indices.contains(index) ? draft.sites[index].id : draft.sites.last?.id
        if wasSaved { app.removeSiteData(site.id) }
    }

    // MARK: Appearance

    var colors: ThemeColors {
        get { draft.appearance.colors(dark: editingDark) }
        set {
            if editingDark { draft.appearance.dark = newValue } else { draft.appearance.light = newValue }
        }
    }

    var isDefaultForEditingMode: Bool {
        colors == ThemePreset.amber.colors(dark: editingDark)
    }

    func applyPreset(_ id: String) {
        guard let preset = ThemePreset.named(id) else { return }
        colors = preset.colors(dark: editingDark)
    }

    func color(for role: ThemeColorRole) -> Binding<Color> {
        Binding(get: { [weak self] in
            guard let self else { return .gray }
            return Color(ThemeTokens(colors: self.colors).color(for: role))
        }, set: { [weak self] color in
            guard let self, let rgb = NSColor(color).rgb else { return }
            let current = ThemeTokens(colors: self.colors).color(for: role)
            guard rgb.hex != current.hex else { return }
            var next = self.colors
            next.set(rgb.hex, for: role)
            self.colors = next
        })
    }

    func canResetToAuto(_ role: ThemeColorRole) -> Bool {
        guard role != .panel && role != .accent else { return false }
        return colors.preset == ThemeColors.customPresetID && colors.hex(for: role) != nil
    }

    func resetToAuto(_ role: ThemeColorRole) {
        var next = colors
        next.set(nil, for: role)
        colors = next
    }

    func resetColors() { applyPreset(ThemePreset.amber.id) }

    func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear input history?"
        alert.informativeText = "lowkey forgets every address and alias you typed. Saved sites stay."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.clearHistory()
        objectWillChange.send()
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var store: Store

    var body: some View {
        let activeTokens = ThemeTokens(colors: model.draft.appearance.colors(dark: ThemeCenter.shared.isDark))
        TabView {
            SitesPane(model: model)
                .tabItem { Label("Sites", systemImage: "rectangle.stack") }
            AppearancePane(model: model)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            GeneralPane(model: model, store: store)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .padding(16)
        .frame(width: 680, height: 540)
        .tint(activeTokens.accentColor)
    }
}

private struct SitesPane: View {
    @ObservedObject var model: SettingsModel
    @State private var originsText = ""
    @FocusState private var originsFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                List(selection: $model.selection) {
                    ForEach(model.draft.sites) { site in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(site.displayTitle).lineLimit(1)
                            Text(site.alias).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        .tag(site.id)
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: false))
                HStack(spacing: 2) {
                    Button(action: model.addSite) { Image(systemName: "plus").frame(width: 18, height: 16) }
                        .help("Add a site").accessibilityLabel("Add a site")
                    Button(action: model.removeSelected) { Image(systemName: "minus").frame(width: 18, height: 16) }
                        .help("Remove the site and its data").accessibilityLabel("Remove the selected site")
                        .disabled(model.selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(.top, 6)
            }
            .frame(width: 190)

            if model.selectedIndex != nil {
                detail
            } else {
                VStack(spacing: 8) {
                    Text("No sites yet").font(.headline)
                    Text("Add a site with +, give it an alias such as HA, and open it with lowkey://HA/open.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: loadOrigins)
        .onChange(of: model.selection) { loadOrigins() }
        .onChange(of: originsFocused) { if !originsFocused { saveOrigins() } }
    }

    private var detail: some View {
        let alias = model.site(\.alias, default: "")
        return Form {
            TextField("Alias", text: alias)
                .font(.body.monospaced())
            LabeledContent("Deep link") {
                HStack {
                    Text(DeepLink.url(alias: alias.wrappedValue)).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(DeepLink.url(alias: alias.wrappedValue), forType: .string)
                    }
                    .controlSize(.small)
                }
            }
            TextField("Title", text: model.site(\.title, default: ""), prompt: Text("Optional"))
            TextField("Start URL", text: model.site(\.startURL, default: ""))
                .font(.body.monospaced())
            Picker("Links to other sites", selection: model.site(\.externalLinks, default: .defaultBrowser)) {
                Text("Open in the default browser").tag(ExternalLinkPolicy.defaultBrowser)
                Text("Open in lowkey").tag(ExternalLinkPolicy.lowkey)
            }
            TextField("Own origins", text: $originsText, prompt: Text("ha.example.com, *.nabu.casa"))
                .font(.body.monospaced())
                .focused($originsFocused)
                .onSubmit(saveOrigins)
            Text("Addresses that count as this site, separated by commas. The start URL’s origin always counts. Sign-in pages (Google, Apple, Microsoft…) open in a separate window and return here.")
                .font(.caption).foregroundStyle(.secondary)
            if !model.problems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.problems, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.caption)
                    }
                    Text("Changes to sites are saved when these are fixed.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func loadOrigins() {
        originsText = model.site(\.extraOrigins, default: []).wrappedValue.joined(separator: ", ")
    }

    private func saveOrigins() {
        let origins = originsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        model.site(\.extraOrigins, default: []).wrappedValue = origins
    }
}

struct AppearancePane: View {
    @ObservedObject var model: SettingsModel
    @State private var showMoreColors = false

    private static let coreRoles: [(ThemeColorRole, String)] = [
        (.panel, "Panel"),
        (.accent, "Accent"),
        (.ink, "Text"),
    ]

    private static let advancedRoles: [(ThemeColorRole, String)] = [
        (.surface, "Surface"),
        (.muted, "Muted text"),
        (.border, "Border"),
        (.selection, "Selection"),
        (.link, "Link"),
        (.success, "Success"),
        (.danger, "Danger"),
    ]

    private func colorRow(_ role: ThemeColorRole, title: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                if model.canResetToAuto(role) {
                    Button("Auto") { model.resetToAuto(role) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Use automatic contrast-matched color")
                }
                ColorPicker(title, selection: model.color(for: role), supportsOpacity: false)
                    .labelsHidden()
            }
        }
    }

    var body: some View {
        let tokens = ThemeTokens(colors: model.colors)
        Form {
            Picker("Mode", selection: $model.draft.appearance.mode) {
                Text("Tint").tag(ThemeMode.tint)
                Text("Page").tag(ThemeMode.page)
                Text("System").tag(ThemeMode.system)
                Text("Light").tag(ThemeMode.light)
                Text("Dark").tag(ThemeMode.dark)
            }
            .pickerStyle(.segmented)
            Section {
                Picker("Edit colors for", selection: $model.editingDark) {
                    Text("Light").tag(false)
                    Text("Dark").tag(true)
                }
                .pickerStyle(.segmented)
                LabeledContent("Theme") {
                    HStack(spacing: 10) {
                        ThemeSwatchStrip(tokens: tokens)
                        Picker("Theme", selection: Binding(
                            get: {
                                let id = model.colors.preset
                                return ThemePreset.all.contains(where: { $0.id == id }) ? id : ThemeColors.customPresetID
                            },
                            set: { model.applyPreset($0) }
                        )) {
                            ForEach(ThemePreset.all) { preset in Text(preset.title).tag(preset.id) }
                            if model.colors.preset == ThemeColors.customPresetID {
                                Divider()
                                Text("Custom").tag(ThemeColors.customPresetID)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                }
                ForEach(Self.coreRoles, id: \.0) { role, title in
                    colorRow(role, title: title)
                }
                DisclosureGroup("More colors", isExpanded: $showMoreColors) {
                    ForEach(Self.advancedRoles, id: \.0) { role, title in
                        colorRow(role, title: title)
                    }
                }
                LabeledContent("Preview") {
                    HStack(alignment: .top, spacing: 10) {
                        StripPreview(tokens: tokens)
                        ThemePreview(tokens: tokens)
                    }
                }
                if tokens.lowAccentContrast {
                    Label("The accent color is hard to see on this panel.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(tokens.dangerColor)
                }
                if tokens.lowInkContrast {
                    Label("The text color has low contrast on this panel.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(tokens.dangerColor)
                }
                HStack {
                    Spacer()
                    Button("Reset to Amber", action: model.resetColors)
                        .disabled(model.isDefaultForEditingMode)
                }
            } footer: {
                Text("Tint follows the page’s theme color or background on the window strip. Page follows each page’s light or dark background. Light and dark palettes keep their own colors; lowkey never recolors the page.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.draft.appearance.mode) { _, next in
            if next == .light { model.editingDark = false }
            else if next == .dark { model.editingDark = true }
        }
    }
}

private struct StripPreview: View {
    let tokens: ThemeTokens

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(tokens.accentColor).frame(height: 3)
            HStack(spacing: 8) {
                Text("×")
                Spacer()
                Text("‹  ⇤  ›")
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tokens.mutedColor)
            .padding(.horizontal, 6)
            .frame(height: ChromeMetrics.stripHeight)
            .background(tokens.panelColor)
            Rectangle().fill(tokens.strokeColor).frame(height: 1)
            Rectangle().fill(Color(nsColor: .textBackgroundColor)).frame(height: 55)
        }
        .frame(width: 170)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(tokens.lineColor, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

private struct GeneralPane: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var store: Store

    var body: some View {
        Form {
            Section("Input history") {
                LabeledContent("Saved entries", value: "\(store.history.entries.count) of \(InputHistory.limit)")
                Text("Addresses and aliases you type in ⌘L. To forget one entry, point at it in the ⌘L list and click ×.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Clear History…", action: model.clearHistory)
                    .disabled(store.history.entries.isEmpty)
            }
            Section("Files") {
                LabeledContent("Settings") {
                    Button(store.configURL.path) { NSWorkspace.shared.activateFileViewerSelecting([store.configURL]) }
                        .buttonStyle(.link).font(.caption.monospaced())
                }
                if let problem = store.problem {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }
}

@MainActor final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: SettingsModel
    private var themeObserver: NSObjectProtocol?

    init(app: AppController) {
        model = SettingsModel(app: app)
        let window = LowkeyWindow(contentRect: NSRect(x: 0, y: 0, width: 712, height: 586), resizable: false)
        window.title = "lowkey Settings"
        window.setContent(SettingsView(model: model, store: app.store))
        super.init(window: window)
        window.delegate = self
        window.closeButton.label = "Close · ⌘W"
        window.closeButton.glyph = .terminate
        window.closeButton.onPress = { [weak self] _ in self?.close() }
        window.setFrameAutosaveName("LowkeySettings")
        if !window.setFrameUsingName("LowkeySettings") { window.center() }
        applyTheme()
        themeObserver = NotificationCenter.default.addObserver(forName: ThemeCenter.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyTheme() }
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func applyTheme() {
        window?.appearance = ThemeCenter.shared.windowAppearance
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc func lowkeyCloseWindow(_ sender: Any?) { close() }
    @objc func lowkeyCloseSite(_ sender: Any?) { close() }
}
