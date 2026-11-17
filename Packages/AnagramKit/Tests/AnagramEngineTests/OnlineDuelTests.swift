import Foundation
import Testing
@testable import AnagramEngine

struct OnlineDuelTests {
    let dormitory = OnlineDuel.Sentence(text: "Dormitory", language: "en")
    let listen = OnlineDuel.Sentence(text: "Listen", language: "en", credit: "From the news: “Listen”")

    @Test func turnsAlternateSolveThenSend() {
        var game = OnlineDuel(settings: Duel.Settings(rounds: 1))
        #expect(game.current == 0 && game.waiting == nil)  // player 0 starts by sending
        game.send(dormitory)
        #expect(game.current == 1)
        game.startSolving(at: Date(timeIntervalSince1970: 0))
        #expect(game.deadline == Date(timeIntervalSince1970: 120))
        game.finishSolving(solved: true, answer: [.init(text: "dirty room", language: "en")], points: 9)
        #expect(game.current == 1 && game.waiting == nil)  // the solver now sends one back
        #expect(game.solveStarted == nil && !game.isOver)
        game.send(listen)
        #expect(game.current == 0)
        game.finishSolving(solved: false, answer: [.init(text: "nope", language: nil)], points: 5)
        #expect(game.isOver)
        #expect(game.scores == [0, 9])
        #expect(game.winner == 1)
        #expect(game.solves[1].answer.isEmpty && game.solves[1].points == 0)
        #expect(game.lastSolve(by: 1)?.sentence == dormitory)
        game.send(dormitory)  // nothing more once it's over
        #expect(game.waiting == nil)
    }

    @Test func clockStartsOnce() {
        var game = OnlineDuel(settings: Duel.Settings(solveTime: 60))
        game.startSolving(at: .now)  // nothing to solve yet
        #expect(game.solveStarted == nil)
        game.send(dormitory)
        game.startSolving(at: Date(timeIntervalSince1970: 100))
        game.startSolving(at: Date(timeIntervalSince1970: 500))  // reopening doesn't reset it
        #expect(game.deadline == Date(timeIntervalSince1970: 160))
    }

    @Test func drawAndRounds() {
        var game = OnlineDuel(settings: Duel.Settings(rounds: 2))
        #expect(game.totalSolves == 4 && game.round == 1)
        for _ in 0..<4 {
            game.send(dormitory)
            game.finishSolving(solved: true, answer: [], points: 3)
        }
        #expect(game.isOver && game.round == 2)
        #expect(game.scores == [6, 6] && game.winner == nil)
    }

    @Test func travelsAsData() throws {
        var game = OnlineDuel(settings: Duel.Settings(rounds: 4, sameLanguage: true, scoring: .anagrams),
                              appSentences: .init(level: "easy", source: "news", language: "it"))
        game.send(listen)
        game.startSolving(at: Date(timeIntervalSince1970: 42))
        let copy = try OnlineDuel(data: game.encoded())
        #expect(copy == game)
        #expect(copy.settings.scoring == .anagrams && copy.appSentences?.language == "it")
    }
}
