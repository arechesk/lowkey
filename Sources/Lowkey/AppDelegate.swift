import AppKit
import LowkeyCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var controller: AppController!
    private var handledURL = false
    private var flagsMonitor: Any?

    func applicationWillFinishLaunching(_ notification: Notification) {
        controller = AppController()
        NSApp.mainMenu = makeMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.controller.setCommandHeld(event.modifierFlags.contains(.command))
            return event
        }
        // Started without a deep link: show the prompt. URL events at launch arrive shortly after this.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            #if DEBUG
            // Development builds: LOWKEY_DEBUG_OPEN=settings opens Settings for visual checks.
            if ProcessInfo.processInfo.environment["LOWKEY_DEBUG_OPEN"] == "settings" {
                self.controller.showSettings()
                return
            }
            #endif
            guard !self.handledURL, self.controller.allBrowsers.isEmpty else { return }
            self.controller.showPrompt(target: nil, newWindow: false)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        handledURL = true
        for url in urls { controller.handle(url: url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        controller.allBrowsers.forEach { $0.savePlacement() }
    }

    func applicationDidResignActive(_ notification: Notification) {
        controller.setCommandHeld(false)
    }

    /// Dock click with nothing on screen: the prompt (hidden sites open by alias).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { controller.showPrompt(target: nil, newWindow: false) }
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: Actions

    @objc func showSettings(_ sender: Any?) { controller.showSettings() }
    @objc func openLocation(_ sender: Any?) { controller.showPrompt(target: controller.currentBrowser, newWindow: false) }
    @objc func newWindow(_ sender: Any?) { controller.showPrompt(target: controller.currentBrowser, newWindow: true) }
    @objc func openInProfile(_ sender: Any?) {
        controller.showPrompt(target: controller.currentWebWindow, newWindow: false, inCurrentProfile: true)
    }

    /// Fallback for windows without their own handler (About panel and others).
    @objc func lowkeyCloseWindow(_ sender: Any?) { NSApp.keyWindow?.performClose(sender) }
    @objc func lowkeyCloseSite(_ sender: Any?) { NSApp.keyWindow?.performClose(sender) }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(openInProfile(_:)):
            return controller.currentWebWindow != nil
        case #selector(lowkeyCloseWindow(_:)):
            item.title = "Close Window"
            return NSApp.keyWindow != nil
        case #selector(lowkeyCloseSite(_:)):
            item.title = "Close Site"
            return false
        default:
            return true
        }
    }

    // MARK: Menu

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let app = submenu(in: main, title: "Lowkey")
        app.addItem(withTitle: "About Lowkey", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(item("Settings…", #selector(showSettings(_:)), ",", target: self))
        app.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "Services")
        NSApp.servicesMenu = services.submenu
        app.addItem(services)
        app.addItem(.separator())
        app.addItem(item("Hide Lowkey", #selector(NSApplication.hide(_:)), "h"))
        app.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        app.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:)), ""))
        app.addItem(.separator())
        app.addItem(item("Quit Lowkey", #selector(NSApplication.terminate(_:)), "q"))

        let file = submenu(in: main, title: "File")
        file.addItem(item("New Window…", #selector(newWindow(_:)), "n", target: self))
        file.addItem(item("Open Location…", #selector(openLocation(_:)), "l", target: self))
        file.addItem(item("Open Location in This Profile…", #selector(openInProfile(_:)), "l", [.command, .shift], target: self))
        file.addItem(.separator())
        file.addItem(item("Hide Window", #selector(LowkeyActions.lowkeyCloseWindow(_:)), "w"))
        file.addItem(item("Close Site", #selector(LowkeyActions.lowkeyCloseSite(_:)), "w", [.command, .shift]))

        let edit = submenu(in: main, title: "Edit")
        edit.addItem(item("Undo", Selector(("undo:")), "z"))
        edit.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]))
        edit.addItem(item("Delete", #selector(NSText.delete(_:)), ""))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))

        let view = submenu(in: main, title: "View")
        view.addItem(item("Reload Page", #selector(LowkeyActions.lowkeyReload(_:)), "r"))
        view.addItem(.separator())
        view.addItem(item("Back", #selector(LowkeyActions.lowkeyBack(_:)), "["))
        view.addItem(item("Forward", #selector(LowkeyActions.lowkeyForward(_:)), "]"))
        view.addItem(item("Start Page", #selector(LowkeyActions.lowkeyStart(_:)), "h", [.command, .shift]))
        view.addItem(.separator())
        view.addItem(item("Actual Size", #selector(LowkeyActions.lowkeyActualSize(_:)), "0"))
        view.addItem(item("Zoom In", #selector(LowkeyActions.lowkeyZoomIn(_:)), "="))
        view.addItem(item("Zoom Out", #selector(LowkeyActions.lowkeyZoomOut(_:)), "-"))
        view.addItem(.separator())
        view.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))

        let window = submenu(in: main, title: "Window")
        window.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        window.addItem(item("Zoom", #selector(NSWindow.performZoom(_:)), ""))
        window.addItem(.separator())
        window.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), ""))
        NSApp.windowsMenu = window

        return main
    }

    private func submenu(in main: NSMenu, title: String) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        main.addItem(item)
        return menu
    }

    private func item(_ title: String, _ action: Selector, _ key: String,
                      _ modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }
}
