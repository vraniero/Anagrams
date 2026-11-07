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

    @Test func sentenceWordsAndNonWordsDontScore() async {
        var round = ClockRound()
        let outcomes = round.score(await judge.judge(Phrase(text: "listen tsil"), source: source), source: source)
        #expect(outcomes == [.fromSentence("listen"), .notAWord("tsil")])
        #expect(round.score == 0)
    }
}

struct DuelTests {
    @Test func playersTakeTurnsAndScore() {
        var duel = Duel(players: ["Ada", "Bo"], rounds: 1)
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
        var duel = Duel(players: ["Ada", "Bo"], rounds: 1)
        duel.finishTurn(solved: true, letters: 5, secondsLeft: 0)
        duel.finishTurn(solved: true, letters: 5, secondsLeft: 0)
        #expect(duel.winner == nil && duel.isOver)
    }
}
