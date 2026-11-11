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

    @Test func singleLettersAndAcronymsDontCount() async {
        let judge = AnagramJudge(validator: WordListValidator([
            "en": ["a", "nasa", "tv", "nato", "san", "vat", "tan", "ant", "ova"],
            "it": ["nato", "è"],
        ]))
        let letter = await judge.judge(Phrase(text: "a ant"), source: Phrase(text: "tana"))
        #expect(letter.problems == [.notAllowed(["a"])])
        #expect(letter.words.first?.isBanned == true)
        let acronym = await judge.judge(Phrase(text: "nasa"), source: Phrase(text: "sana"))
        #expect(acronym.problems == [.notAllowed(["nasa"])])
        let noVowel = await judge.judge(Phrase(text: "tv ova"), source: Phrase(text: "vota v"))
        #expect(noVowel.problems == [.notAllowed(["tv"])])
        // an acronym in English, a word in Italian: it counts
        let nato = await judge.judge(Phrase(text: "nato"), source: Phrase(text: "tona"))
        #expect(nato.isValid)
        #expect(nato.words.map(\.language) == ["it"])
    }

    @Test func wordRules() {
        #expect(!WordRules.isAllowed("A", language: "en"))
        #expect(!WordRules.isAllowed("è", language: "it"))
        #expect(!WordRules.isAllowed("NASA", language: nil))
        #expect(!WordRules.isAllowed("km", language: "it"))
        #expect(!WordRules.isAllowed("dvd", language: "en"))
        #expect(WordRules.isAllowed("eu", language: "pt"))
        #expect(!WordRules.isAllowed("eu", language: "en"))
        #expect(WordRules.isAllowed("un", language: "fr"))
        #expect(WordRules.isAllowed("by", language: "en"))
        #expect(WordRules.isAllowed("Città", language: "it"))
        #expect(WordRules.isAllowed("дом", language: "ru"))
    }
}
