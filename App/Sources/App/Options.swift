import Foundation

/// Choices that apply to every mode, remembered between launches.
enum Options {
    static let sameLanguageKey = "sameLanguage"
    static let suggestionsKey = "suggestions"
    static let sentenceLanguageKey = "sentenceLanguage"

    /// All words of an anagram must be in one language.
    static var sameLanguage: Bool { UserDefaults.standard.bool(forKey: sameLanguageKey) }
}
