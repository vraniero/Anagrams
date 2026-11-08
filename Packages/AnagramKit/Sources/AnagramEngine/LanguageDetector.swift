import Foundation
import NaturalLanguage

/// Detects the dominant language of a piece of text.
public struct LanguageDetector: Sendable {
    public init() {}

    public func dominantLanguage(of text: String) -> String? {
        NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue
    }

    /// Top-N language hypotheses with probabilities.
    public func hypotheses(for text: String, max: Int = 3) -> [String: Double] {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return Dictionary(uniqueKeysWithValues:
            recognizer.languageHypotheses(withMaximum: max).map { ($0.key.rawValue, $0.value) })
    }
}
