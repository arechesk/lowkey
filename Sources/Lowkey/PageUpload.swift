import UniformTypeIdentifiers
import WebKit

@MainActor enum PageUpload {
    static func attach(in view: WKWebView, startURL: URL, name: String, bytes: Data, field: String? = nil) async -> String {
        let ext = (name as NSString).pathExtension
        let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        do {
            let result = try await view.callAsyncJavaScript(script, arguments: ["site": startURL.absoluteString,
                "name": name, "mime": mime, "field": field ?? "", "base64": bytes.base64EncodedString()], in: nil, contentWorld: .defaultClient)
            return result as? String ?? "page unavailable"
        } catch { return "page unavailable" }
    }

    private static let script = #"""
    if (!['http:', 'https:'].includes(location.protocol) || location.origin !== new URL(site).origin)
        return 'wrong site origin';
    // Custom upload buttons often have a hidden file input. Include it, but never guess between inputs.
    const normalize = s => (s || '').trim().replace(/\s+/gu, ' ');
    const wanted = normalize(field);
    const roots = [document]; let input;
    for (const root of roots) {
        for (const el of root.querySelectorAll('*')) {
            if (el.shadowRoot) roots.push(el.shadowRoot);
            if (!el.matches('input[type=file]')) continue;
            if (wanted) {
                const labels = Array.from(el.labels || [], l => l.textContent);
                labels.push(el.getAttribute('aria-label'));
                const refs = (el.getAttribute('aria-labelledby') || '').trim().split(/\s+/u);
                labels.push(refs.map(id => root.getElementById(id)?.textContent || '').join(' '));
                if (!labels.some(s => normalize(s) === wanted)) continue;
            }
            if (input) return wanted ? 'ambiguous field' : 'multiple file inputs';
            input = el;
        }
    }
    if (!input) return wanted ? 'field not found' : 'no file input';
    if (input.matches(':disabled') || input.closest('[inert],[aria-disabled="true"]')) return 'control disabled';
    if (input.webkitdirectory) return 'directory input unsupported';
    const types = input.accept.toLowerCase().split(',').map(x => x.trim()).filter(Boolean);
    if (types.length && !types.some(t => t === mime || t === '*/*' || (t.startsWith('.') && name.toLowerCase().endsWith(t)) ||
        (t.endsWith('/*') && mime.startsWith(t.slice(0, -1))))) return 'file type not accepted';
    const raw = atob(base64), bytes = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
    const selection = new DataTransfer();
    selection.items.add(new File([bytes], name, { type: mime }));
    input.files = selection.files;
    input.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
    return 'ok';
    """#
}
