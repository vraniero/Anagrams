import Foundation

/// The anagram being built: blocks move from the source phrase (the tray) down into the
/// candidate's words, and back. Every block exists exactly once, in the tray or in a word.
///
/// Accents work like punctuation: a letter moved down loses its accent ("è" → "e") and gets
/// it back in the tray; in the anagram, any letter may take any accent it can carry.
public struct AnagramBoard: Hashable, Sendable {
    /// The accents a player can put on a letter (combining marks): acute, grave, circumflex,
    /// diaeresis, tilde, cedilla.
    public static let accents: [Character] = ["\u{301}", "\u{300}", "\u{302}", "\u{308}", "\u{303}", "\u{327}"]

    public private(set) var source: Phrase
    /// The words being built. The last one is where tapped blocks go; it may be empty.
    public private(set) var words: [Word] = [Word(blocks: [])]

    public init(source: Phrase = Phrase()) {
        self.source = source
    }

    /// Blocks not used yet, in the source's order.
    public var tray: [LetterBlock] {
        let used = Set(words.flatMap(\.blocks).map(\.id))
        return source.words.flatMap(\.blocks).filter { !used.contains($0.id) }
    }

    public var candidate: Phrase {
        Phrase(words: words.filter { !$0.blocks.isEmpty })
    }

    public var isComplete: Bool { tray.isEmpty && !candidate.words.isEmpty }

    /// More of the sentence arrived (pending speech transcribed after "Make anagram").
    public mutating func updateSource(_ phrase: Phrase) {
        source = phrase
    }

    /// Moves a block (from the tray or another word) into `word` at `index`
    /// (default: the end of the last word).
    public mutating func place(_ id: LetterBlock.ID, inWord word: Int? = nil, at index: Int? = nil) {
        let fromTray = !words.contains { $0.blocks.contains { $0.id == id } }
        guard var block = takeBlock(id) else { return }
        if fromTray { block = LetterBlock(id: block.id, character: Self.plain(block.character)) }
        let w = min(word ?? words.count - 1, words.count - 1)
        let i = min(index ?? words[w].blocks.count, words[w].blocks.count)
        words[w].blocks.insert(block, at: i)
        tidy()
    }

    /// Adds a punctuation mark (there are as many as you like) to `word` at `index`
    /// (default: the end of the last word).
    public mutating func addMark(_ mark: Character, inWord word: Int? = nil, at index: Int? = nil) {
        let w = min(word ?? words.count - 1, words.count - 1)
        let i = min(index ?? words[w].blocks.count, words[w].blocks.count)
        words[w].blocks.insert(LetterBlock(character: mark), at: i)
    }

    /// Whether `accent` can go on the anagram's last letter (or comes off it, if it's there).
    public func canAccent(_ accent: Character) -> Bool {
        guard let (w, i) = accentTarget else { return false }
        return Self.adding(accent, to: words[w].blocks[i].character) != nil
    }

    /// Whether the anagram's last letter carries `accent`.
    public func hasAccent(_ accent: Character) -> Bool {
        guard let (w, i) = accentTarget else { return false }
        let c = words[w].blocks[i].character
        return Self.adding(accent, to: c) == c && Self.plain(c) != c
    }

    /// Puts `accent` on the anagram's last letter (punctuation after it is skipped),
    /// replacing any other accent; takes it off if it's already there.
    public mutating func toggleAccent(_ accent: Character) {
        guard let (w, i) = accentTarget else { return }
        let block = words[w].blocks[i]
        let next = hasAccent(accent) ? Self.plain(block.character) : Self.adding(accent, to: block.character)
        guard let next else { return }
        words[w].blocks[i] = LetterBlock(id: block.id, character: next)
    }

    /// The letter without accents ("È" → "E"); letters that aren't accented ones ("ø", "ß") stay.
    public static func plain(_ c: Character) -> Character {
        let scalars = String(c).decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { $0.properties.generalCategory != .nonspacingMark }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view).precomposedStringWithCanonicalMapping.first ?? c
    }

    /// The letter with `accent` instead of its own; nil if there's no such letter ("ç" but no "a" with a cedilla).
    public static func adding(_ accent: Character, to c: Character) -> Character? {
        let s = (String(plain(c)) + String(accent)).precomposedStringWithCanonicalMapping
        return s.unicodeScalars.count == 1 ? Character(s) : nil
    }

    /// The last letter of the anagram (marks after it don't count).
    private var accentTarget: (Int, Int)? {
        for w in words.indices.reversed() {
            for i in words[w].blocks.indices.reversed() where words[w].blocks[i].character.isLetter && !isMark(words[w].blocks[i].id) {
                return (w, i)
            }
        }
        return nil
    }

    /// Whether the block is a punctuation mark the player added (not from the sentence).
    public func isMark(_ id: LetterBlock.ID) -> Bool {
        blockInSource(id) == nil
    }

    /// Sends a block back to the tray (a punctuation mark just goes away).
    public mutating func remove(_ id: LetterBlock.ID) {
        _ = takeBlock(id)
        tidy()
    }

    /// Starts a new word (if the last one isn't already empty).
    public mutating func newWord() {
        if words.last?.blocks.isEmpty == false { words.append(Word(blocks: [])) }
    }

    /// Lays out an anagram (a suggestion): its words built from the tray's blocks, letter by
    /// letter, accents and case ignored ("amerò" takes an "o" block, and gets the accent).
    public mutating func arrange(_ texts: [String]) {
        clear()
        func fold(_ c: Character) -> String {
            String(c).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        }
        for text in texts {
            newWord()
            for ch in text where ch.isLetter {
                guard let block = tray.first(where: { fold($0.character) == fold(ch) }) else { continue }
                place(block.id)
                // the suggestion's accent, on the tile's own letter (its case kept)
                let marks = String(ch).decomposedStringWithCanonicalMapping.unicodeScalars
                    .filter { $0.properties.generalCategory == .nonspacingMark }
                if let accent = marks.first, let w = words.indices.last, let i = words[w].blocks.indices.last,
                   let accented = Self.adding(Character(accent), to: words[w].blocks[i].character) {
                    words[w].blocks[i] = LetterBlock(id: block.id, character: accented)
                }
            }
        }
    }

    /// Everything back to the tray.
    public mutating func clear() {
        words = [Word(blocks: [])]
    }

    private func blockInSource(_ id: LetterBlock.ID) -> LetterBlock? {
        source.words.lazy.flatMap(\.blocks).first { $0.id == id }
    }

    /// Detaches a block from wherever it is; nil if it isn't on the board.
    private mutating func takeBlock(_ id: LetterBlock.ID) -> LetterBlock? {
        for w in words.indices {
            if let i = words[w].blocks.firstIndex(where: { $0.id == id }) {
                return words[w].blocks.remove(at: i)
            }
        }
        return blockInSource(id)
    }

    /// Drops empty words, except the last one (the word being typed into).
    private mutating func tidy() {
        let last = words.count - 1
        words = words.enumerated().filter { !$0.element.blocks.isEmpty || $0.offset == last }.map(\.element)
    }
}
