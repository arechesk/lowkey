import AppKit
import LowkeyCore
import WebKit

/// A web view that turns ⌘← / ⌘→ into history navigation unless a text field has focus.
@MainActor final class LowkeyWebView: WKWebView {
    /// Reported by the page: a text field, text area or editable element has focus.
    var isEditingText = false

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Save as PDF…", action: #selector(LowkeyActions.lowkeySavePDF(_:)), keyEquivalent: ""))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        if flags == .command, event.type == .keyDown, !isEditingText,
           let responder = window?.firstResponder as? NSView, responder.isDescendant(of: self) {
            switch event.keyCode {
            case 123: if canGoBack { goBack() }; return true
            case 124: if canGoForward { goForward() }; return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Receives focus reports from the page script in an isolated content world.
final class EditingReporter: NSObject, WKScriptMessageHandler {
    static let shared = EditingReporter()
    static let name = "lowkeyEditing"

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            guard let webView = message.webView as? LowkeyWebView, let editing = message.body as? Bool else { return }
            webView.isEditingText = editing
        }
    }

    /// Runs in `.defaultClient`, invisible to the page's own scripts.
    static let script = """
    (() => {
      const closed = new Set(['button','checkbox','color','file','hidden','image','radio','range','reset','submit']);
      const editable = (el) => {
        if (!el) return false;
        if (el.isContentEditable) return true;
        const tag = el.tagName;
        if (tag === 'TEXTAREA') return !el.readOnly && !el.disabled;
        if (tag === 'SELECT') return true;
        if (tag === 'INPUT') return !closed.has((el.type || 'text').toLowerCase()) && !el.readOnly && !el.disabled;
        return false;
      };
      const deep = () => {
        let el = document.activeElement;
        while (el && el.shadowRoot && el.shadowRoot.activeElement) el = el.shadowRoot.activeElement;
        return el;
      };
      const report = () => {
        const el = deep();
        // Focus inside a child frame: that frame reports for itself.
        if (el && (el.tagName === 'IFRAME' || el.tagName === 'FRAME')) return;
        try { window.webkit.messageHandlers.lowkeyEditing.postMessage(editable(el)); } catch (e) {}
      };
      document.addEventListener('focusin', report, true);
      document.addEventListener('focusout', () => setTimeout(report, 0), true);
    })();
    """
}

enum WebKitSupport {
    /// A new configuration for a window. Popups must instead use the configuration WebKit passes in.
    @MainActor static func configuration(dataStore: WKWebsiteDataStore) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let content = WKUserContentController()
        content.addUserScript(WKUserScript(source: EditingReporter.script, injectionTime: .atDocumentEnd,
                                           forMainFrameOnly: false, in: .defaultClient))
        content.add(EditingReporter.shared, contentWorld: .defaultClient, name: EditingReporter.name)
        configuration.userContentController = content
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.applicationNameForUserAgent = userAgentSuffix
        return configuration
    }

    /// Identify Lowkey without impersonating Safari or bypassing identity-provider policy.
    static var userAgentSuffix: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return "lowkey/\(version)"
    }

    @MainActor static func makeWebView(configuration: WKWebViewConfiguration) -> LowkeyWebView {
        let webView = LowkeyWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        return webView
    }

    @MainActor static func pin(_ view: NSView, in container: NSView, top: NSLayoutYAxisAnchor? = nil) {
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: top ?? container.topAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    /// Simple themed error page. Never offers to bypass certificate errors.
    static func errorPage(url: URL?, error: Error, dark: Bool) -> String {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        let (bg, ink, muted) = dark ? ("#1b2226", "#eef1ec", "#a4afb3") : ("#f7f8f5", "#222a2e", "#59666c")
        let address = escape(url?.absoluteString ?? "")
        return """
        <!doctype html><meta charset="utf-8"><title>Can’t open page</title>
        <style>body{margin:0;height:100vh;display:grid;place-items:center;background:\(bg);color:\(ink);
        font:14px -apple-system,sans-serif}main{max-width:520px;padding:24px}h1{font-size:22px;font-weight:600;margin:0 0 8px}
        p{color:\(muted);line-height:1.5;margin:0 0 6px}code{font:12px ui-monospace,Menlo,monospace;color:\(ink);word-break:break-all}</style>
        <main><h1>Can’t open this page</h1><p>\(escape(error.localizedDescription))</p>
        <p><code>\(address)</code></p><p>Press ⌘R to try again.</p></main>
        """
    }
}

/// Saves downloads to ~/Downloads with a unique name and bounces the Downloads stack.
@MainActor final class DownloadManager: NSObject, WKDownloadDelegate {
    static let shared = DownloadManager()
    private var destinations: [ObjectIdentifier: URL] = [:]

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let name = (suggestedFilename as NSString).lastPathComponent
        let safe = name.isEmpty ? "download" : name
        var url = folder.appending(path: safe)
        var index = 2
        let base = (safe as NSString).deletingPathExtension
        let ext = (safe as NSString).pathExtension
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appending(path: ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)")
            index += 1
        }
        destinations[ObjectIdentifier(download)] = url
        completionHandler(url)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = destinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: url.path)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        destinations.removeValue(forKey: ObjectIdentifier(download))
        NSLog("lowkey download failed: \(error.localizedDescription)")
    }
}

/// JavaScript dialogs, file pickers and HTTP sign-in prompts, shown as sheets.
@MainActor enum PageDialogs {
    static func alert(_ message: String, in window: NSWindow?, completion: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        present(alert, in: window) { _ in completion() }
    }

    static func confirm(_ message: String, in window: NSWindow?, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert, in: window) { completion($0 == .alertFirstButtonReturn) }
    }

    static func prompt(_ message: String, defaultText: String?, in window: NSWindow?, completion: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        present(alert, in: window) { completion($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    static func credentials(host: String, in window: NSWindow?, completion: @escaping (URLCredential?) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Sign in to \(host)"
        alert.informativeText = "The site asks for a user name and password."
        let user = NSTextField(frame: NSRect(x: 0, y: 30, width: 260, height: 24))
        user.placeholderString = "User name"
        let password = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        password.placeholderString = "Password"
        let stack = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 54))
        stack.addSubview(user)
        stack.addSubview(password)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Sign In")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = user
        present(alert, in: window) { response in
            guard response == .alertFirstButtonReturn else { return completion(nil) }
            completion(URLCredential(user: user.stringValue, password: password.stringValue, persistence: .forSession))
        }
    }

    static func openFiles(allowsMultiple: Bool, directories: Bool, in window: NSWindow?, completion: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = allowsMultiple
        panel.canChooseDirectories = directories
        panel.canChooseFiles = !directories
        if let window {
            panel.beginSheetModal(for: window) { completion($0 == .OK ? panel.urls : nil) }
        } else {
            completion(panel.runModal() == .OK ? panel.urls : nil)
        }
    }

    private static func present(_ alert: NSAlert, in window: NSWindow?, handler: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }
}
