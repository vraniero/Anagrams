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
        #expect(board.candidate.text.lowercased() == "amèro")  // the tiles keep the sentence's letters
        #expect(board.tray.isEmpty)
        board.arrange(["ramo", "e"])
        #expect(board.candidate.words.map(\.text).map { $0.lowercased() } == ["ramo", "è"])
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
