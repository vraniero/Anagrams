import Foundation

/// Finds a language in which a word exists. Words may come from any language.
public protocol WordValidator: Sendable {
    /// The language (e.g. "it") the word was found in, or nil if it's in none.
    /// `preferring` lists languages to try first, such as the ones spoken.
    func language(of word: String, preferring: [String]) async -> String?
    /// Every language the word exists in, the preferred ones first.
    func languages(of word: String, preferring: [String]) async -> [String]
    /// Whether the word exists in this language (a suggestion from a word list, say).
    func isWord(_ word: String, in language: String) async -> Bool
}

/// A validator backed by a fixed word list per language: for tests and previews.
public struct WordListValidator: WordValidator {
    let lists: [String: Set<String>]

    public init(_ lists: [String: Set<String>]) {
        self.lists = lists.mapValues { Set($0.map { $0.lowercased() }) }
    }

    public func language(of word: String, preferring: [String]) async -> String? {
        let w = word.lowercased()
        let order = preferring + lists.keys.sorted().filter { !preferring.contains($0) }
        return order.first { lists[$0]?.contains(w) == true }
    }

    public func languages(of word: String, preferring: [String]) async -> [String] {
        let w = word.lowercased()
        let order = preferring + lists.keys.sorted().filter { !preferring.contains($0) }
        return order.filter { lists[$0]?.contains(w) == true }
    }

    public func isWord(_ word: String, in language: String) async -> Bool {
        lists[language]?.contains(word.lowercased()) == true
    }
}
