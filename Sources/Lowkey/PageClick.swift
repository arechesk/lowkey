import WebKit

@MainActor enum PageClick {
    /// Evaluate in an isolated world in the main frame. Check the document origin and
    /// select and click synchronously in the same script, so navigation can't swap documents.
    static func perform(in webView: WKWebView, startURL: URL, label: String) async -> String {
        do {
            let result = try await webView.callAsyncJavaScript(script,
                arguments: ["site": startURL.absoluteString, "label": label], in: nil, contentWorld: .defaultClient)
            return result as? String ?? "page unavailable"
        } catch { return "page unavailable" }
    }

    private static let script = #"""
    if (!['http:', 'https:'].includes(location.protocol) || location.origin !== new URL(site).origin)
        return 'wrong site origin';
    const normalize = s => (s || '').trim().replace(/\s+/gu, ' ');
    const wanted = normalize(label);
    const matches = [];
    const roots = [document];
    for (const root of roots) {
        for (const el of root.querySelectorAll('*')) {
            if (el.shadowRoot) roots.push(el.shadowRoot);
            if (!(el instanceof HTMLElement) || !el.matches('button,a[href],input[type=button],input[type=submit],input[type=reset],[role=button],[role=link]')) continue;
            if (!el.getClientRects().length || getComputedStyle(el).visibility !== 'visible') continue;
            const text = el instanceof HTMLInputElement ? el.value : el.innerText;
            if (![text, el.getAttribute('aria-label')].some(s => normalize(s) === wanted)) continue;
            matches.push(el);
            if (matches.length > 1) return 'ambiguous label';
        }
    }
    if (!matches.length) return 'label not found';
    const el = matches[0];
    if (el.matches(':disabled') || el.closest('[inert],[aria-disabled="true"]')) return 'control disabled';
    if (el instanceof HTMLAnchorElement && !['http:', 'https:'].includes(el.protocol)) return 'unsupported link';
    el.click();
    return 'ok';
    """#
}
