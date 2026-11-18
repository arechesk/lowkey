import Foundation

/// Addresses and aliases submitted in the Lowkey prompt. Not a log of page visits.
public struct InputHistory: Codable, Equatable, Sendable {
    public static let limit = 1000

    /// Newest first, unique (case-insensitive).
    public private(set) var entries: [String]

    public init(entries: [String] = []) {
        self.entries = []
        for entry in entries.reversed() { record(entry) }
    }

    /// Moves the entry to the top. A removed entry comes back when submitted again.
    public mutating func record(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        entries.removeAll { $0.caseInsensitiveCompare(text) == .orderedSame }
        entries.insert(text, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    public mutating func remove(_ text: String) {
        entries.removeAll { $0.caseInsensitiveCompare(text) == .orderedSame }
    }

    public mutating func clear() { entries.removeAll() }

    public static func load(from url: URL) -> InputHistory {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([String].self, from: data) else { return InputHistory() }
        return InputHistory(entries: entries)
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        try encoder.encode(entries).write(to: url, options: .atomic)
    }
}

public enum Suggestion: Equatable, Sendable {
    case site(Site)
    case history(String)

    /// The text that the prompt submits for this suggestion.
    public var text: String {
        switch self {
        case .site(let site): site.alias
        case .history(let text): text
        }
    }
}

public enum Suggestions {
    /// Saved sites first, then history. Original spelling outranks layout variants;
    /// prefixes outrank substrings. Ties preserve site order / newest-first history.
    public static func make(query: String, sites: [Site], history: InputHistory, limit: Int = 8) -> [Suggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sites.prefix(max(0, limit)).map(Suggestion.site) }
        let queries = KeyboardLayoutSwap.variants(of: trimmed)
        func rank(_ text: String, preferPrefix: Bool = false) -> Int? {
            let text = text.lowercased()
            for (index, q) in queries.enumerated() where text.contains(q) {
                return index * 2 + (preferPrefix && text.hasPrefix(q) ? 0 : 1)
            }
            return nil
        }
        func best(_ values: Int?...) -> Int? { values.compactMap { $0 }.min() }
        func sorted<T>(_ items: [T], rank: (T) -> Int?) -> [T] {
            items.enumerated().compactMap { index, item -> (Int, Int, T)? in
                rank(item).map { ($0, index, item) }
            }.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }.map { $0.2 }
        }

        let siteHits = sorted(sites) {
            best(rank($0.alias, preferPrefix: true), rank($0.title), rank($0.startURL))
        }
        let aliases = Set(sites.map { $0.alias.lowercased() })
        let historyHits = sorted(history.entries.filter { !aliases.contains($0.lowercased()) }) {
            best(rank($0, preferPrefix: true), rank(strippedScheme($0), preferPrefix: true))
        }
        return Array((siteHits.map(Suggestion.site) + historyHits.map(Suggestion.history)).prefix(max(0, limit)))
    }

    static func strippedScheme(_ text: String) -> String {
        for prefix in ["https://", "http://"] where text.lowercased().hasPrefix(prefix) {
            return String(text.dropFirst(prefix.count))
        }
        return text
    }
}
