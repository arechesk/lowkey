import Foundation

/// Matches text typed on the wrong layout, as in Ting's launcher.
/// Physical US ↔ Russian/Ukrainian PC keys, not phonetic transliteration.
/// Only matching uses these variants; the prompt and valid typed URLs are left unchanged.
public enum KeyboardLayoutSwap {
    private static let us = Array("qwertyuiop[]asdfghjkl;'zxcvbnm,.`")
    private static let russian = Dictionary(uniqueKeysWithValues: zip(us, Array("йцукенгшщзхъфывапролджэячсмитьбюё")))
    private static let ukrainian = Dictionary(uniqueKeysWithValues: zip(us, Array("йцукенгшщзхїфівапролджєячсмитьбюё")))
    private static let latin: [Character: Character] = {
        var result: [Character: Character] = [:]
        for map in [russian, ukrainian] {
            for (key, letter) in map { result[letter] = key }
        }
        return result
    }()

    /// Original, lowercase query first, then distinct variants. Unmapped characters stay intact.
    public static func variants(of query: String) -> [String] {
        let original = query.lowercased()
        var result = [original]
        for map in [latin, russian, ukrainian] {
            let candidate = String(original.map { map[$0] ?? $0 })
            if !result.contains(candidate) { result.append(candidate) }
        }
        return result
    }
}
