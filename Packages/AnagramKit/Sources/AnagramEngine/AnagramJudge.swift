import Foundation
import AnagramModels

/// Result of a full anagram check.
public struct AnagramVerdict: Equatable, Sendable {
    public struct CheckedWord: Equatable, Sendable {
        public let text: String
        /// The language the word was found in; nil if it isn't a word in any language.
        public let language: String?
    }

    public enum Problem: Equatable, Sendable {
        /// Not all letters were used (or letters differ).
        case lettersDiffer
        /// Same letters in the same order: not a rearrangement.
        case sameAsSource
        /// Some words aren't words in any language.
        case unknownWords([String])
        /// The words must all be in one language, and there's none they share.
        case mixedLanguages
    }

    public let words: [CheckedWord]
    public let problems: [Problem]
    public var isValid: Bool { problems.isEmpty }
}

/// Decides whether a candidate is a valid anagram: same letters, a real rearrangement,
/// and every word a word in some language. Languages may be mixed, unless `sameLanguage`.
/// Punctuation marks are free: they don't count as letters and aren't looked up.
public struct AnagramJudge: Sendable {
    let checker = AnagramChecker()
    let validator: any WordValidator

    public init(validator: any WordValidator) {
        self.validator = validator
    }

    public func judge(_ candidate: Phrase, source: Phrase, sameLanguage: Bool = false) async -> AnagramVerdict {
        var problems: [AnagramVerdict.Problem] = []
        if checker.letterCounts(candidate.text) != checker.letterCounts(source.text) || candidate.words.isEmpty {
            problems.append(.lettersDiffer)
        } else if checker.normalized(candidate.text) == checker.normalized(source.text) {
            problems.append(.sameAsSource)
        }
        let preferring = source.languageCodes
        // marks on their own ("!") aren't words to look up
        let words = candidate.words.filter { !$0.lookupText.isEmpty }
        var found: [[String]] = []
        for word in words {
            if sameLanguage {
                found.append(await validator.languages(of: word.lookupText, preferring: preferring))
            } else {
                found.append(await validator.language(of: word.lookupText, preferring: preferring).map { [$0] } ?? [])
            }
        }

        var languages = found.map(\.first)
        if sameLanguage, !found.contains(where: \.isEmpty) {
            let shared = found.dropFirst().reduce(Set(found.first ?? [])) { $0.intersection($1) }
            if let common = found.first?.first(where: shared.contains) {
                languages = Array(repeating: common, count: found.count)
            } else if found.count > 1 {
                problems.append(.mixedLanguages)
            }
        }
        let checked = zip(words, languages).map { AnagramVerdict.CheckedWord(text: $0.text, language: $1) }
        let unknown = checked.filter { $0.language == nil }.map(\.text)
        if !unknown.isEmpty { problems.append(.unknownWords(unknown)) }
        return AnagramVerdict(words: checked, problems: problems)
    }
}
