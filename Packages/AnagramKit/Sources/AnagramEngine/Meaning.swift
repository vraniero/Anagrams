import Foundation

/// Whether an anagram, read as a phrase, means something.
public struct Meaning: Equatable, Sendable {
    public let makesSense: Bool
    /// One short sentence: what it means, or why it doesn't make sense.
    public let reading: String

    public init(makesSense: Bool, reading: String) {
        self.makesSense = makesSense
        self.reading = reading
    }

    /// Only a correct anagram of two or more words is worth asking about: a single word
    /// always "means" something.
    public static func applies(to verdict: AnagramVerdict) -> Bool {
        verdict.isValid && verdict.words.count >= 2
    }

    /// Whether `natural` (the phrase as a model would say it) is the same words as `phrase`
    /// in another order: then the player's order is wrong ("mare il blu" → "il mare blu").
    /// A rewording (a word added, translated) says nothing about the order.
    public static func isReordering(_ natural: String, of phrase: String) -> Bool {
        func words(_ text: String) -> [String] {
            text.lowercased()
                .split { !($0.isLetter || $0 == "'") }
                .map(String.init)
        }
        let a = words(natural), b = words(phrase)
        return a != b && a.sorted() == b.sorted()
    }
}

/// Reads a phrase (possibly in several languages) and says whether it means something.
public protocol MeaningChecker: Sendable {
    /// Whether it can check at all on this device right now.
    var isAvailable: Bool { get }
    /// nil when it couldn't tell (model unavailable, unsupported language, refused).
    func meaning(of phrase: String, languages: [String]) async -> Meaning?
}
