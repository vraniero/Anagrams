import Testing
import AnagramModels

struct AnagramBoardTests {
    func board(_ text: String) -> AnagramBoard { AnagramBoard(source: Phrase(text: text)) }
    func id(_ b: AnagramBoard, _ c: Character) -> LetterBlock.ID { b.tray.first { $0.character == c }!.id }

    @Test func placingMovesBlocksOutOfTheTray() {
        var b = board("ab")
        b.place(id(b, "b"))
        b.place(id(b, "a"))
        #expect(b.candidate.text == "ba")
        #expect(b.tray.isEmpty && b.isComplete)
    }

    @Test func newWordSplitsAndRemoveReturnsToTray() {
        var b = board("abc")
        b.place(id(b, "c"))
        b.newWord()
        b.newWord()  // no second empty word
        b.place(id(b, "a"))
        b.place(id(b, "b"))
        #expect(b.candidate.text == "c ab")
        let c = b.candidate.words[0].blocks[0].id
        b.remove(c)
        #expect(b.candidate.text == "ab")  // the emptied word is gone
        #expect(b.tray.map(\.character) == ["c"])
    }

    @Test func blocksCanBeReorderedBetweenWords() {
        var b = board("abc")
        for ch in "abc" { b.place(id(b, ch)) }
        let c = b.words[0].blocks[2].id
        b.place(c, inWord: 0, at: 0)
        #expect(b.candidate.text == "cab")
    }

    @Test func lateSpeechJoinsTheTray() {
        var b = board("ab")
        b.place(id(b, "a"))
        var more = b.source
        more.append(text: "c", languageCode: "en")
        b.updateSource(more)
        #expect(b.tray.map(\.character) == ["b", "c"])
        b.clear()
        #expect(b.tray.count == 3 && b.candidate.words.isEmpty)
    }
}
