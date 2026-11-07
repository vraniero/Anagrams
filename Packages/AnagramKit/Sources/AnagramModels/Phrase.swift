import Foundation

/// A word built from letter blocks. In a spoken sentence only letters become blocks; in an
/// anagram the player may add punctuation marks too.
public struct Word: Identifiable, Hashable, Sendable {
    /// The marks a player can add while anagramming.
    public static let marks: [Character] = [",", ".", "!", "?", "'", "-", ":", ";"]

    public let id: UUID
    public var blocks: [LetterBlock]
    /// Language the word was spoken in (BCP-47 / Whisper code), if known.
    public var languageCode: String?

    public init(id: UUID = UUID(), blocks: [LetterBlock], languageCode: String? = nil) {
        self.id = id
        self.blocks = blocks
        self.languageCode = languageCode
    }

    public init(_ text: String, languageCode: String? = nil, keepingMarks: Bool = false) {
        self.init(blocks: text.filter { $0.isLetter || (keepingMarks && Self.marks.contains($0)) }
                    .map { LetterBlock(character: $0) },
                  languageCode: languageCode)
    }

    /// The word to look up: no marks around it ("silent!" → "silent"); inside, an
    /// apostrophe or hyphen stays ("l'amore"). Empty for marks alone.
    public var lookupText: String {
        let t = text.trimmingCharacters(in: CharacterSet(charactersIn: String(Self.marks)))
        return t.filter { $0.isLetter || $0 == "'" || $0 == "-" }
    }

    public var text: String { String(blocks.map(\.character)) }
}

/// A recognized (source) or user-built (anagram) phrase.
public struct Phrase: Hashable, Sendable {
    public var words: [Word]

    public init(words: [Word] = []) {
        self.words = words
    }

    public init(text: String, languageCode: String? = nil) {
        self.init(words: Self.words(in: text, languageCode: languageCode))
    }

    /// An anagram as typed, punctuation marks included ("silent, dear!").
    public init(anagram text: String) {
        self.init(words: text.split(whereSeparator: { $0.isWhitespace })
            .map { Word(String($0), keepingMarks: true) }
            .filter { !$0.blocks.isEmpty })
    }

    /// Appends a recognized utterance (which may be in a different language).
    public mutating func append(text: String, languageCode: String?) {
        words += Self.words(in: text, languageCode: languageCode)
    }

    public var text: String { words.map(\.text).joined(separator: " ") }

    /// Languages heard, in order of first appearance.
    public var languageCodes: [String] {
        var seen = Set<String>()
        return words.compactMap(\.languageCode).filter { seen.insert($0).inserted }
    }

    private static func words(in text: String, languageCode: String?) -> [Word] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { Word(String($0), languageCode: languageCode) }
            .filter { !$0.blocks.isEmpty }
    }
}
