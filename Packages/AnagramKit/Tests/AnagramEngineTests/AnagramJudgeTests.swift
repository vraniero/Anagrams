import Testing
import AnagramModels
@testable import AnagramEngine

struct AnagramJudgeTests {
    let judge = AnagramJudge(validator: WordListValidator([
        "en": ["silent", "listen", "a", "night", "thing"],
        "it": ["amore", "roma", "è"],
    ]))

    @Test func validAnagramMixingLanguages() async {
        let source = Phrase(text: "Roma è night", languageCode: "it")
        let verdict = await judge.judge(Phrase(text: "amore thing"), source: source)
        #expect(verdict.isValid)
        #expect(verdict.words.map(\.language) == ["it", "en"])
    }

    @Test func unusedLettersAreReported() async {
        let verdict = await judge.judge(Phrase(text: "amore"), source: Phrase(text: "Roma è night"))
        #expect(verdict.problems == [.lettersDiffer])
    }

    @Test func sameOrderIsNotAnAnagram() async {
        let verdict = await judge.judge(Phrase(text: "listen"), source: Phrase(text: "listen"))
        #expect(verdict.problems == [.sameAsSource])
    }

    @Test func unknownWordsAreNamed() async {
        let verdict = await judge.judge(Phrase(text: "tsilen"), source: Phrase(text: "listen"))
        #expect(verdict.problems == [.unknownWords(["tsilen"])])
    }

    @Test func spokenLanguagesAreTriedFirst() async {
        let both = WordListValidator(["en": ["a"], "it": ["a"]])
        #expect(await both.language(of: "a", preferring: ["it"]) == "it")
        #expect(await both.language(of: "A", preferring: []) == "en")
    }
}
