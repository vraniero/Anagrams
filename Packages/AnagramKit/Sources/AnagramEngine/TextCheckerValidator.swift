#if canImport(UIKit)
import UIKit

/// Checks words with the system spell checker, in every language it has a dictionary for.
/// Works offline; coverage depends on the dictionaries on the device.
///
/// Some listed dictionaries accept anything: ones whose data isn't on the device, and ones
/// for another script (Arabic can't judge Latin letters). Each dictionary is tested once per
/// script against known non-words, and only trusted if it rejects them all.
@MainActor
public final class TextCheckerValidator: WordValidator {
    private let checker = UITextChecker()
    private var trusted: [String: Bool] = [:]  // "it_IT|latin" -> rejects non-words

    public init() {}

    enum Script: String { case latin, cyrillic, greek, other }

    /// Non-words used to test a dictionary, per script.
    static let nonWords: [Script: [String]] = [
        .latin: ["xqzvtk", "pwmqzrb", "kjhgfdq"],
        .cyrillic: ["жщъыйц", "хкщзчъп"],
        .greek: ["ξψζχφθ", "ψζξχκπφ"],
    ]

    static func script(of word: String) -> Script {
        guard let v = word.unicodeScalars.first(where: { $0.properties.isAlphabetic })?.value else { return .other }
        switch v {
        case 0x0041..<0x0250, 0x1E00..<0x1F00: return .latin
        case 0x0370..<0x0400, 0x1F00..<0x2000: return .greek
        case 0x0400..<0x0530: return .cyrillic
        default: return .other
        }
    }

    /// System dictionary codes ("it_IT", "en_US"…), grouped so the preferred languages come first.
    static func order(available: [String], preferring: [String]) -> [String] {
        let preferred = preferring.flatMap { lang in available.filter { base($0) == lang } }
        return preferred + available.filter { !preferred.contains($0) }
    }

    static func base(_ code: String) -> String {
        String(code.prefix { $0 != "_" && $0 != "-" }).lowercased()
    }

    public func language(of word: String, preferring: [String]) async -> String? {
        Self.order(available: UITextChecker.availableLanguages, preferring: preferring)
            .first { accepts(word: word, code: $0) }
            .map(Self.base)
    }

    public func languages(of word: String, preferring: [String]) async -> [String] {
        var result: [String] = []
        for code in Self.order(available: UITextChecker.availableLanguages, preferring: preferring)
        where !result.contains(Self.base(code)) && accepts(word: word, code: code) {
            result.append(Self.base(code))
        }
        return result
    }

    public func isWord(_ word: String, in language: String) async -> Bool {
        UITextChecker.availableLanguages.contains { Self.base($0) == language && accepts(word: word, code: $0) }
    }

    /// The word in this dictionary (if the dictionary can be trusted for its script).
    private func accepts(word: String, code: String) -> Bool {
        let lower = word.lowercased()
        guard let first = lower.first, isTrusted(code, for: Self.script(of: lower)) else { return false }
        let capitalized = String(first).uppercased() + lower.dropFirst()
        return Self.forms(lower, capitalized, in: code).contains { accepts($0, code) }
    }

    /// Languages whose ordinary words (nouns) are written capitalized: "haus" is only right
    /// as "Haus". Elsewhere a capitalized entry is a name or an abbreviation ("Oa", "Ao" in
    /// Italian), which doesn't count.
    static let capitalizedNouns: Set<String> = ["de", "lb"]

    static func forms(_ lower: String, _ capitalized: String, in code: String) -> [String] {
        capitalizedNouns.contains(base(code)) ? [lower, capitalized] : [lower]
    }

    private func isTrusted(_ code: String, for script: Script) -> Bool {
        let key = "\(code)|\(script.rawValue)"
        if let known = trusted[key] { return known }
        let ok = (Self.nonWords[script] ?? []).allSatisfy { !accepts($0, code) }
        trusted[key] = ok
        return ok
    }

    private func accepts(_ text: String, _ language: String) -> Bool {
        checker.rangeOfMisspelledWord(in: text, range: NSRange(text.startIndex..., in: text),
                                      startingAt: 0, wrap: false, language: language).location == NSNotFound
    }
}
#endif
