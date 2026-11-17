import Foundation

/// Choices that apply to every mode, remembered between launches.
enum Options {
    static let sameLanguageKey = "sameLanguage"
    static let suggestionsKey = "suggestions"
    static let sentenceLanguageKey = "sentenceLanguage"
    static let sentenceSourceKey = "sentenceSource"
    static let swearBonusKey = "swearBonus"

    /// All words of an anagram must be in one language.
    static var sameLanguage: Bool { UserDefaults.standard.bool(forKey: sameLanguageKey) }

    /// Swear words score double, a rude anagram triple (only when the feature is on).
    static var swearBonus: Bool { FeatureFlags.swearing && UserDefaults.standard.bool(forKey: swearBonusKey) }
}

/// Features built but kept out of the app for now.
enum FeatureFlags {
    /// The swear words bonus: swear words score double, a profane anagram triple, and Apple
    /// Intelligence is told rude phrases are part of the game. Off for the App Store; to try
    /// it, launch with `-swearing` (or set this to true).
    static let swearing = ProcessInfo.processInfo.arguments.contains("-swearing")
}
