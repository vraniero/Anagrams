import Foundation
import AnagramModels

/// Result of a full anagram check.
public struct AnagramVerdict: Equatable, Sendable {
    public struct CheckedWord: Equatable, Sendable {
        public let text: String
        /// The language the word was found in; nil if it isn't a word in any language.
        public let language: String?
        /// A single letter or an acronym: never counts (see `WordRules`).
        public var isBanned = false

        public init(text: String, language: String?, isBanned: Bool = false) {
            self.text = text
            self.language = language
            self.isBanned = isBanned
        }
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
        /// Single letters and acronyms don't count, even if a dictionary has them.
        case notAllowed([String])
    }

    public let words: [CheckedWord]
    public let problems: [Problem]
    public var isValid: Bool { problems.isEmpty }
}

/// Decides whether a candidate is a valid anagram: same letters, a real rearrangement,
/// and every word a word in some language. Languages may be mixed, unless `sameLanguage`.
/// Punctuation marks are free: they don't count as letters and aren't looked up.
/// Single letters and acronyms aren't words here (`WordRules`).
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
        var banned: [Bool] = []
        for word in words {
            let text = word.lookupText
            var languages: [String]
            if WordRules.fold(text).count < 2 {
                languages = []  // a single letter: not even looked up
            } else if sameLanguage {
                languages = await validator.languages(of: text, preferring: preferring)
            } else {
                languages = await validator.language(of: text, preferring: preferring).map { [$0] } ?? []
                // an acronym there: maybe an ordinary word somewhere else ("nato", Italian)
                if let first = languages.first, !WordRules.isAllowed(text, language: first) {
                    languages = await validator.languages(of: text, preferring: preferring)
                }
            }
            let allowed = languages.filter { WordRules.isAllowed(text, language: $0) }
            banned.append(allowed.isEmpty && (!languages.isEmpty || WordRules.fold(text).count < 2))
            found.append(allowed)
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
        let checked = zip(zip(words, languages), banned).map {
            AnagramVerdict.CheckedWord(text: $0.0.text, language: $0.1, isBanned: $1)
        }
        let notAllowed = checked.filter(\.isBanned).map(\.text)
        if !notAllowed.isEmpty { problems.append(.notAllowed(notAllowed)) }
        let unknown = checked.filter { $0.language == nil && !$0.isBanned }.map(\.text)
        if !unknown.isEmpty { problems.append(.unknownWords(unknown)) }
        return AnagramVerdict(words: checked, problems: problems)
    }
}
