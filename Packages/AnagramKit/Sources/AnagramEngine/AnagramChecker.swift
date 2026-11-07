import Foundation
import AnagramModels

/// Checks that two phrases use exactly the same letters.
public struct AnagramChecker: Sendable {
    public init() {}

    public func isAnagram(_ candidate: Phrase, of source: Phrase) -> Bool {
        let a = letterCounts(candidate.text)
        return !a.isEmpty && a == letterCounts(source.text) && normalized(candidate.text) != normalized(source.text)
    }

    /// Lowercased letters only, diacritics folded (é → e) so languages mix freely.
    func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .filter(\.isLetter)
    }

    func letterCounts(_ text: String) -> [Character: Int] {
        normalized(text).reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }
}
