import AppKit
import LowkeyCore
import WebKit

/// Configuration and input history on disk.
/// `LOWKEY_CONFIG=/tmp/x.json` moves both files for manual checks (history: `/tmp/x.json.history.json`).
@MainActor final class Store: ObservableObject {
    @Published private(set) var config: Config
    @Published private(set) var history: InputHistory
    /// The last load or save problem, shown in Settings.
    @Published var problem: String?

    let configURL: URL
    let historyURL: URL

    init(configURL customConfigURL: URL? = nil) {
        let environment = ProcessInfo.processInfo.environment
        if let customConfigURL {
            configURL = customConfigURL
            historyURL = URL(fileURLWithPath: customConfigURL.path + ".history.json")
        } else if let path = environment["LOWKEY_CONFIG"], !path.isEmpty {
            configURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            historyURL = URL(fileURLWithPath: configURL.path + ".history.json")
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            configURL = home.appending(path: ".config/lowkey/config.json")
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            historyURL = support.appending(path: "Lowkey/history.json")
        }
        do {
            config = try Config.load(from: configURL)
        } catch {
            config = Config()
            problem = "Can’t read \(configURL.path): \(error.localizedDescription). Lowkey will not overwrite it until you change a setting."
        }
        history = InputHistory.load(from: historyURL)
    }

    /// Saves a valid configuration. Returns the problems that block saving.
    @discardableResult func update(_ new: Config) -> [String] {
        let problems = new.problems()
        guard problems.isEmpty else { return problems }
        guard new != config else { return [] }
        do {
            try new.save(to: configURL)
            config = new
            problem = nil
        } catch {
            problem = "Can’t save settings: \(error.localizedDescription)"
            return [problem!]
        }
        return []
    }

    func record(_ text: String) {
        history.record(text)
        saveHistory()
    }

    func removeHistory(_ text: String) {
        history.remove(text)
        saveHistory()
    }

    func clearHistory() {
        history.clear()
        saveHistory()
    }

    private func saveHistory() {
        do { try history.save(to: historyURL) } catch { NSLog("Lowkey: can’t save history: \(error.localizedDescription)") }
    }
}

/// Owns the windows and runs commands from deep links, menus and the address prompt.
@MainActor final class AppController {
    let store: Store
    private(set) var siteWindows: [UUID: BrowserWindowController] = [:]
    private(set) var ordinaryWindows: [BrowserWindowController] = []
    private lazy var prompt = AddressPanel(app: self)
    private var settings: SettingsWindowController?
    private(set) var commandHeld = false

    init(store: Store? = nil) {
        self.store = store ?? Store()
        ThemeCenter.shared.appearance = self.store.config.appearance
    }

    var allBrowsers: [BrowserWindowController] { Array(siteWindows.values) + ordinaryWindows }

    /// The site window the user works in, if any.
    var currentBrowser: BrowserWindowController? {
        if let controller = NSApp.keyWindow?.windowController as? BrowserWindowController { return controller }
        if let controller = NSApp.mainWindow?.windowController as? BrowserWindowController { return controller }
        return nil
    }

    /// Includes sign-in/popup windows: the shortcut must use the profile in front.
    var currentWebWindow: WebWindowController? {
        (NSApp.keyWindow?.windowController as? WebWindowController)
            ?? (NSApp.mainWindow?.windowController as? WebWindowController)
    }

    // MARK: Deep links

    func handle(url: URL) {
        switch DeepLink.parse(url) {
        case .success(.prompt):
            showPrompt(target: currentBrowser, newWindow: false)
        case .success(.site(let alias, let command)):
            if alias == "*", command == .toggle {
                toggleSavedWindows()
                return
            }
            guard let site = store.config.site(alias: alias) else {
                showPrompt(target: currentBrowser, newWindow: false, prefill: alias,
                           message: "No site named “\(alias)”. Add it in Settings (⌘,).")
                return
            }
            run(command, on: site)
        case .failure(.unknownCommand(let name)):
            let known = SiteCommand.allCases.map(\.rawValue).joined(separator: ", ")
            showPrompt(target: currentBrowser, newWindow: false, message: "Unknown command “\(name)”. Use: \(known).")
        case .failure(.notLowkey):
            break
        }
    }

    func run(_ command: SiteCommand, on site: Site) {
        if let controller = siteWindows[site.id] {
            controller.perform(command)
            return
        }
        // hide/close on a site that is not open: nothing to do.
        guard command != .hide && command != .close else { return }
        openSite(site)
    }

    /// All existing saved-site windows move in one direction, rather than exchanging visibility.
    /// Unopened aliases and ordinary/default-profile windows are intentionally untouched.
    private func toggleSavedWindows() {
        let controllers = Array(siteWindows.values)
        let action = WindowToggle.groupAction(visibleWindows: controllers.map {
            guard let window = $0.window else { return false }
            return window.isVisible && !window.isMiniaturized
        })
        for controller in controllers {
            switch action {
            case .hide: controller.hide()
            case .show:
                if controller.window?.isMiniaturized == true { controller.window?.deminiaturize(nil) }
                controller.show()
            }
        }
    }

    // MARK: Windows

    @discardableResult func openSite(_ site: Site) -> BrowserWindowController? {
        if let controller = siteWindows[site.id] {
            controller.show()
            return controller
        }
        guard let url = site.url else { return nil }
        let controller = BrowserWindowController(kind: .saved(site.id), startURL: url,
                                                 dataStore: WKWebsiteDataStore(forIdentifier: site.id), app: self)
        siteWindows[site.id] = controller
        controller.updateCloseGlyph(commandHeld: commandHeld)
        controller.load(url)
        controller.show()
        return controller
    }

    func openOrdinary(_ url: URL, near window: NSWindow? = nil) {
        let controller = BrowserWindowController(kind: .ordinary, startURL: url, dataStore: .default(), app: self)
        ordinaryWindows.append(controller)
        controller.load(url)
        controller.show()
    }

    func windowDidClose(_ controller: WebWindowController) {
        guard let browser = controller as? BrowserWindowController else { return }
        if case .saved(let id) = browser.kind, siteWindows[id] === browser { siteWindows[id] = nil }
        ordinaryWindows.removeAll { $0 === browser }
    }

    func windowDidHide(_ controller: BrowserWindowController) {}

    func setCommandHeld(_ held: Bool) {
        guard held != commandHeld else { return }
        commandHeld = held
        for controller in siteWindows.values { controller.updateCloseGlyph(commandHeld: held) }
    }

    // MARK: Address prompt

    func showPrompt(target: WebWindowController?, newWindow: Bool, prefill: String? = nil,
                    message: String? = nil, inCurrentProfile: Bool = false) {
        prompt.show(target: target, newWindow: newWindow, prefill: prefill, message: message,
                    inCurrentProfile: inCurrentProfile)
    }

    /// Opens what the user typed. Returns an error message to show in the prompt.
    func submit(_ text: String, target: WebWindowController?, newWindow: Bool,
                inCurrentProfile: Bool = false) -> String? {
        let resolved = AddressResolver.resolve(text, sites: store.config.sites)
        if inCurrentProfile {
            guard let target, target.window != nil else { return "The profile window is no longer open." }
            let url: URL?
            switch resolved {
            case .site(let site): url = site.url
            case .url(let address): url = address
            case .invalid: url = nil
            }
            guard let url else { return "Enter a site alias or a web address." }
            store.record(url.absoluteString)
            target.loadInCurrentProfile(url)
            target.window?.makeKeyAndOrderFront(nil)
            return nil
        }
        switch resolved {
        case .site(let site):
            store.record(site.alias)
            openSite(site)
        case .url(let url):
            store.record(url.absoluteString)
            // A typed address never replaces a saved site; it gets an ordinary window.
            if !newWindow, let target = target as? BrowserWindowController, target.kind == .ordinary {
                target.load(url)
                target.show()
            } else {
                openOrdinary(url, near: target?.window)
            }
        case .invalid:
            return "“\(text.trimmingCharacters(in: .whitespaces))” is not a site alias or a web address."
        }
        return nil
    }

    // MARK: Settings

    func showSettings() {
        if settings == nil { settings = SettingsWindowController(app: self) }
        settings?.show()
    }

    func applyAppearance(_ appearance: AppearanceConfig) {
        ThemeCenter.shared.appearance = appearance
    }

    /// Closes the window of a removed site and deletes its profile (cookies, storage, logins).
    func removeSiteData(_ id: UUID) {
        siteWindows[id]?.window?.close()
        siteWindows[id] = nil
        // Give WebKit a moment to release the store of the closed window.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: id)
            } catch {
                NSLog("Lowkey: can’t remove the profile of a deleted site: \(error.localizedDescription)")
            }
        }
    }
}
