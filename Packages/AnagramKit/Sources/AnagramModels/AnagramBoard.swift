import Foundation

/// The anagram being built: blocks move from the source phrase (the tray) down into the
/// candidate's words, and back. Every block exists exactly once, in the tray or in a word.
public struct AnagramBoard: Hashable, Sendable {
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
        guard let block = takeBlock(id) else { return }
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
    /// letter, accents and case ignored ("amerò" takes an "o" block).
    public mutating func arrange(_ texts: [String]) {
        clear()
        func fold(_ c: Character) -> String {
            String(c).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        }
        for text in texts {
            newWord()
            for ch in text where ch.isLetter {
                if let block = tray.first(where: { fold($0.character) == fold(ch) }) { place(block.id) }
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
