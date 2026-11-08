import Testing
import AnagramModels
@testable import AnagramEngine

struct SameLanguageTests {
    let judge = AnagramJudge(validator: WordListValidator([
        "en": ["silent", "a", "me", "night"],
        "it": ["amore", "a", "e", "me"],
    ]))

    @Test func mixedIsFineByDefault() async {
        let verdict = await judge.judge(Phrase(text: "amore night"), source: Phrase(text: "Roma è thing"))
        #expect(verdict.isValid)
    }

    @Test func sameLanguageRejectsAMix() async {
        let verdict = await judge.judge(Phrase(text: "amore night"), source: Phrase(text: "Roma è thing"), sameLanguage: true)
        #expect(verdict.problems == [.mixedLanguages])
    }

    @Test func sameLanguagePicksTheSharedOne() async {
        // "a" is English first, but "amore" only Italian: both become Italian
        let verdict = await judge.judge(Phrase(text: "a amore"), source: Phrase(text: "Roma è a"), sameLanguage: true)
        #expect(verdict.words.map(\.language) == ["it", "it"])
        #expect(verdict.isValid)
    }
}

struct PunctuationTests {
    let judge = AnagramJudge(validator: WordListValidator(["en": ["silent", "dirty", "room"]]))

    @Test func marksAreFreeAndNotLookedUp() async {
        let verdict = await judge.judge(Phrase(anagram: "dirty, room !"), source: Phrase(text: "dormitory"))
        #expect(verdict.isValid)
        #expect(verdict.words.map(\.text) == ["dirty,", "room"])
    }

    @Test func boardAddsAndDropsMarks() {
        var board = AnagramBoard(source: Phrase(text: "Listen"))
        board.place(board.tray[0].id)
        board.addMark("!")
        #expect(board.words[0].text == "L!")
        let mark = board.words[0].blocks[1].id
        #expect(board.isMark(mark))
        board.remove(mark)
        #expect(board.words[0].text == "L")
        #expect(board.tray.count == 5)
    }

    @Test func arrangeLaysOutASuggestion() {
        var board = AnagramBoard(source: Phrase(text: "Roma è"))
        board.arrange(["amerò"])
        #expect(board.candidate.text.lowercased() == "amerò")  // accents as in the suggestion
        #expect(board.tray.isEmpty)
        board.arrange(["ramo", "e"])
        #expect(board.candidate.words.map(\.text).map { $0.lowercased() } == ["ramo", "e"])
    }

    @Test func lettersMovedDownLoseTheirAccentsAndGetThemBackInTheTray() throws {
        var board = AnagramBoard(source: Phrase(text: "Città è"))
        let a = try #require(board.tray.first { $0.character == "à" })
        board.place(a.id)
        #expect(board.candidate.text == "a")
        board.remove(a.id)
        #expect(board.tray.contains { $0.id == a.id && $0.character == "à" })
    }

    @Test func accentsGoOnTheLastLetter() throws {
        var board = AnagramBoard(source: Phrase(text: "perché"))
        for ch in "perche" { board.place(try #require(board.tray.first { AnagramBoard.plain($0.character) == ch }).id) }
        board.addMark("!")
        #expect(board.candidate.text == "perche!")
        let acute: Character = "\u{301}", grave: Character = "\u{300}", cedilla: Character = "\u{327}"
        #expect(board.canAccent(acute) && board.canAccent(cedilla))  // ȩ exists in Unicode
        board.toggleAccent(acute)
        #expect(board.candidate.text == "perché!" && board.hasAccent(acute))
        board.toggleAccent(grave)                      // another accent replaces it
        #expect(board.candidate.text == "perchè!")
        board.toggleAccent(grave)                      // the same one takes it off
        #expect(board.candidate.text == "perche!" && !board.hasAccent(grave))
    }

    @Test func accentsOnlyWhereALetterExists() {
        #expect(AnagramBoard.adding("\u{327}", to: "c") == "ç")
        #expect(AnagramBoard.adding("\u{327}", to: "q") == nil)
        var board = AnagramBoard(source: Phrase(text: "qua"))
        board.place(board.tray[0].id)
        #expect(!board.canAccent("\u{327}") && !board.canAccent("\u{301}"))  // no q́, no q̧
        #expect(AnagramBoard.adding("\u{303}", to: "N") == "Ñ")
        #expect(AnagramBoard.plain("È") == "E" && AnagramBoard.plain("ø") == "ø")
    }
}

struct SolverTests {
    let solver = AnagramSolver(lexicons: [
        "en": ["the", "listen", "silent", "enlist", "tin", "lens", "dirty", "room", "a"],
        "it": ["amore", "roma", "ramo", "e", "mare"],
    ])

    @Test func findsSingleAndMultiWordAnagrams() {
        let candidates = solver.candidates(for: "Dormitory")
        let found = solver.solve("Dormitory", candidates: candidates, sameLanguage: false).map(\.text)
        #expect(found.contains("dirty room"))
    }

    @Test func excludesTheSentenceItself() {
        let found = solver.solve("Listen", candidates: solver.candidates(for: "Listen"), sameLanguage: false).map(\.text)
        #expect(found.contains("silent") && found.contains("enlist"))
        #expect(!found.contains("listen"))
    }

    @Test func sameLanguageDoesntMix() {
        let candidates = solver.candidates(for: "Roma tin lens")
        let mixed = solver.solve("Roma tin lens", candidates: candidates, sameLanguage: false)
        #expect(mixed.contains { Set($0.languages).count > 1 })
        let same = solver.solve("Roma tin lens", candidates: candidates, sameLanguage: true)
        #expect(same.allSatisfy { Set($0.languages).count == 1 })
    }
}
