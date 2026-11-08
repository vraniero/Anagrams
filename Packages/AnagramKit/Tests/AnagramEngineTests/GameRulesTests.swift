import Testing
import AnagramModels
@testable import AnagramEngine

struct ClockRoundTests {
    let judge = AnagramJudge(validator: WordListValidator(["en": ["silent", "listen", "tin", "lens", "enlist"]]))
    let source = Phrase(text: "Listen", languageCode: "en")

    @Test func wordsScoreTheirLettersOnce() async {
        var round = ClockRound()
        let first = round.score(await judge.judge(Phrase(text: "tin lens"), source: source), source: source)
        #expect(first.count == 2)
        #expect(round.score == 7)
        let again = round.score(await judge.judge(Phrase(text: "tin"), source: source), source: source)
        #expect(again == [.alreadyFound("tin")])
        #expect(round.score == 7)
    }

    @Test func fullAnagramScoresDoubleOnTop() async {
        var round = ClockRound()
        _ = round.score(await judge.judge(Phrase(text: "silent"), source: source), source: source)
        #expect(round.score == 6 + 12)
        #expect(round.found.last?.isFullAnagram == true)
        #expect(round.found.map(\.languages) == [["en"], ["en"]])
    }

    @Test func aMeaningfulFullAnagramScoresDoubleAgain() async {
        var round = ClockRound()
        let verdict = await judge.judge(Phrase(text: "lens tin"), source: Phrase(text: "silent n", languageCode: "en"))
        #expect(verdict.isValid)
        let sense = Meaning(makesSense: true, reading: "A lens made of tin.")
        _ = round.score(verdict, source: Phrase(text: "silent n", languageCode: "en"), meaning: sense)
        let full = round.found.last
        #expect(full?.isFullAnagram == true && full?.points == 7 * 4 && full?.meaning == "A lens made of tin.")

        // no sense, or a single word: no bonus
        var plain = ClockRound()
        _ = plain.score(verdict, source: Phrase(text: "silent n", languageCode: "en"),
                        meaning: Meaning(makesSense: false, reading: "Just two words."))
        #expect(plain.found.last?.points == 14 && plain.found.last?.meaning == nil)
        var single = ClockRound()
        _ = single.score(await judge.judge(Phrase(text: "silent"), source: source), source: source, meaning: sense)
        #expect(single.found.last?.points == 12)
    }

    @Test func sentenceWordsAndNonWordsDontScore() async {
        var round = ClockRound()
        let outcomes = round.score(await judge.judge(Phrase(text: "listen tsil"), source: source), source: source)
        #expect(outcomes == [.fromSentence("listen"), .notAWord("tsil")])
        #expect(round.score == 0)
    }
}

struct DuelTests {
    @Test func playersTakeTurnsAndScore() {
        var duel = Duel(players: ["Ada", "Bo"], settings: .init(rounds: 1))
        #expect(duel.setter == 0 && duel.solver == 1)
        #expect(duel.finishTurn(solved: true, letters: 6, secondsLeft: 45) == 10)
        #expect(duel.setter == 1 && duel.solver == 0)
        #expect(duel.finishTurn(solved: false, letters: 8, secondsLeft: 0) == 0)
        #expect(duel.isOver)
        #expect(duel.scores == [0, 10])
        #expect(duel.winner == 1)
        #expect(duel.finishTurn(solved: true, letters: 5, secondsLeft: 10) == 0)
    }

    @Test func drawHasNoWinner() {
        var duel = Duel(players: ["Ada", "Bo"], settings: .init(rounds: 1))
        duel.finishTurn(solved: true, letters: 5, secondsLeft: 0)
        duel.finishTurn(solved: true, letters: 5, secondsLeft: 0)
        #expect(duel.winner == nil && duel.isOver)
    }

    @Test func threePlayersEachSetOncePerRound() {
        var duel = Duel(players: ["Ada", "Bo", "Cy"], settings: .init(rounds: 2, scoring: .letters))
        var pairs: [[Int]] = []
        while !duel.isOver {
            pairs.append([duel.setter, duel.solver])
            duel.finishTurn(solved: true, letters: 4 + duel.solver, secondsLeft: 50)
        }
        #expect(pairs == [[0, 1], [1, 2], [2, 0], [0, 1], [1, 2], [2, 0]])
        #expect(duel.round == 3)
        #expect(duel.scores == [8, 10, 12])  // letters only: no time bonus
        #expect(duel.winner == 2)
    }

    @Test func scoringModels() {
        #expect(Duel.Settings(scoring: .lettersAndTime).points(letters: 6, secondsLeft: 45) == 10)
        #expect(Duel.Settings(scoring: .letters).points(letters: 6, secondsLeft: 45) == 6)
        #expect(Duel.Settings(scoring: .anagrams).points(letters: 6, secondsLeft: 45) == 1)
        #expect(Duel.Settings(rounds: 99).rounds == 10)
    }

    @Test func meaningBonusDoublesWhenOn() {
        #expect(Duel.Settings(scoring: .letters, meaningBonus: true).points(letters: 6, secondsLeft: 0, makesSense: true) == 12)
        #expect(Duel.Settings(scoring: .letters, meaningBonus: true).points(letters: 6, secondsLeft: 0, makesSense: false) == 6)
        #expect(Duel.Settings(scoring: .letters, meaningBonus: false).points(letters: 6, secondsLeft: 0, makesSense: true) == 6)
        var duel = Duel(players: ["Ada", "Bo"], settings: .init(rounds: 1, scoring: .anagrams, meaningBonus: true))
        #expect(duel.finishTurn(solved: true, letters: 8, secondsLeft: 30, makesSense: true) == 2)
    }

    @Test func sentencesMustFitTheLetterLimit() {
        let settings = Duel.Settings(maxLetters: 10)
        #expect(settings.allows(letters: 10))
        #expect(!settings.allows(letters: 11))
        #expect(!settings.allows(letters: 0))
        #expect(Duel.Settings().maxLetters == 20)
    }

    @Test func tieForFirstHasNoWinner() {
        var duel = Duel(players: ["Ada", "Bo", "Cy"], settings: .init(rounds: 1, scoring: .anagrams))
        duel.finishTurn(solved: true, letters: 5, secondsLeft: 0)   // Bo
        duel.finishTurn(solved: true, letters: 5, secondsLeft: 0)   // Cy
        duel.finishTurn(solved: false, letters: 5, secondsLeft: 0)  // Ada
        #expect(duel.scores == [0, 1, 1])
        #expect(duel.winner == nil)
    }
}

struct MeaningTests {
    @Test func reorderingIsSameWordsInAnotherOrder() {
        #expect(Meaning.isReordering("il mare blu", of: "mare il blu"))
        #expect(Meaning.isReordering("A dog barks.", of: "barks a dog!"))
        #expect(!Meaning.isReordering("il mare blu", of: "Il mare, blu"))   // same order
        #expect(!Meaning.isReordering("an elegant man", of: "elegant man"))  // a word added
        #expect(!Meaning.isReordering("the sun rises", of: "el sol sale"))   // translated
    }
}

struct SentenceReviewTests {
    @Test func onlyCapitalsPunctuationAndAccentsMayDiffer() {
        #expect(SentenceReview.comparing(corrected: "Perché sei qui?", to: "perche sei qui").isCorrect)
        #expect(SentenceReview.comparing(corrected: "das Haus ist groß", to: "Das Haus ist gross").isCorrect)
        let wrong = SentenceReview.comparing(corrected: "I have two dogs.", to: "I has two dogs")
        #expect(!wrong.isCorrect && wrong.suggestion == "I have two dogs.")
        #expect(SentenceReview.comparing(corrected: "the cat sleeps", to: "the cat sleeps").suggestion == nil)
    }
}

struct SwearBonusTests {
    @Test func swearWordsAreFoundInTheirLanguage() {
        #expect(Profanity.isSwear("Merda", language: "it"))
        #expect(Profanity.isSwear("cabron", language: "es"))      // accents ignored
        #expect(!Profanity.isSwear("merda", language: "en"))      // not in that language's list
        #expect(Profanity.isSwear("shit", language: nil))         // unknown language: any list
        #expect(!Profanity.isSwear("silent", language: "en"))
    }

    @Test func clockSwearWordsDoubleAndProfaneAnagramsTriple() async {
        let judge = AnagramJudge(validator: WordListValidator(["en": ["shit", "tins", "this", "tin", "s"]]))
        let source = Phrase(text: "this tin s", languageCode: "en")
        var round = ClockRound()
        _ = round.score(await judge.judge(Phrase(text: "shit"), source: source), source: source, swearBonus: true)
        #expect(round.found.last?.points == 8 && round.found.last?.isSwear == true)
        var off = ClockRound()
        _ = off.score(await judge.judge(Phrase(text: "shit"), source: source), source: source)
        #expect(off.found.last?.points == 4)

        let full = await judge.judge(Phrase(text: "shit tins"), source: source)
        #expect(full.isValid)
        var profane = ClockRound()
        _ = profane.score(full, source: source,
                          meaning: Meaning(makesSense: true, reading: "Rude.", isProfane: true), swearBonus: true)
        #expect(profane.found.last?.isFullAnagram == true && profane.found.last?.points == 8 * 2 * 3)
    }

    @Test func multiplayerTakesTheBiggestBonus() {
        let on = Duel.Settings(scoring: .letters, meaningBonus: true, swearBonus: true)
        #expect(on.points(letters: 6, secondsLeft: 0, hasSwear: true) == 12)
        #expect(on.points(letters: 6, secondsLeft: 0, makesSense: true, hasSwear: true) == 12)
        #expect(on.points(letters: 6, secondsLeft: 0, makesSense: true, hasSwear: true, isProfane: true) == 18)
        #expect(Duel.Settings(scoring: .letters).points(letters: 6, secondsLeft: 0, hasSwear: true, isProfane: true) == 6)
    }
}
