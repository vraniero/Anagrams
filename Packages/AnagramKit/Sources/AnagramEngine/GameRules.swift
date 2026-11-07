import Foundation
import AnagramModels

/// Against the clock: build as many words as you can from the sentence's letters before
/// time runs out. Each word scores its letters, once; a full anagram of the sentence scores
/// double its letters on top. Words taken straight from the sentence don't count.
public struct ClockRound: Equatable, Sendable {
    public static let duration: TimeInterval = 90

    public struct Found: Equatable, Sendable, Identifiable {
        public let text: String
        /// The language of the word; for a full anagram, of each of its words.
        public let languages: [String]
        public let points: Int
        public let isFullAnagram: Bool
        public var id: String { (isFullAnagram ? "*" : "") + text }
    }

    public enum Outcome: Equatable, Sendable {
        case scored(Found)
        case alreadyFound(String)
        case notAWord(String)
        case fromSentence(String)
        /// The words checked together weren't all in one language (when that's the rule).
        case mixedLanguages
    }

    public private(set) var found: [Found] = []
    public var score: Int { found.reduce(0) { $0 + $1.points } }

    public init() {}

    /// Scores a checked candidate; what happened to each word, in order.
    public mutating func score(_ verdict: AnagramVerdict, source: Phrase) -> [Outcome] {
        let checker = AnagramChecker()
        let sentenceWords = Set(source.words.map { checker.normalized($0.text) })
        if verdict.problems.contains(.mixedLanguages) { return [.mixedLanguages] }
        var outcomes: [Outcome] = []
        for word in verdict.words {
            let key = checker.normalized(word.text)
            guard !key.isEmpty else { continue }
            if word.language == nil {
                outcomes.append(.notAWord(word.text))
            } else if sentenceWords.contains(key) {
                outcomes.append(.fromSentence(word.text))
            } else if found.contains(where: { !$0.isFullAnagram && checker.normalized($0.text) == key }) {
                outcomes.append(.alreadyFound(word.text))
            } else {
                let new = Found(text: word.text, languages: word.language.map { [$0] } ?? [], points: key.count,
                                isFullAnagram: false)
                found.append(new)
                outcomes.append(.scored(new))
            }
        }
        if verdict.isValid {
            let text = verdict.words.map(\.text).joined(separator: " ")
            let key = checker.normalized(text)
            if !found.contains(where: { $0.isFullAnagram && checker.normalized($0.text) == key }) {
                let full = Found(text: text, languages: verdict.words.compactMap(\.language), points: key.count * 2,
                                 isFullAnagram: true)
                found.append(full)
                outcomes.append(.scored(full))
            }
        }
        return outcomes
    }
}

/// Two players take turns: one says (or types) a sentence, the other has a limited time to
/// make a full anagram of it. A solved anagram scores its letters plus a point for every
/// ten seconds left.
public struct Duel: Equatable, Sendable {
    public static let solveTime: TimeInterval = 120

    public let players: [String]
    public let rounds: Int
    public private(set) var scores: [Int] = [0, 0]
    /// Turns played; each round is two turns, so both players set a sentence once.
    public private(set) var turn = 0

    public init(players: [String], rounds: Int) {
        precondition(players.count == 2)
        self.players = players
        self.rounds = max(1, rounds)
    }

    public var setter: Int { turn % 2 }
    public var solver: Int { 1 - setter }
    public var round: Int { turn / 2 + 1 }
    public var isOver: Bool { turn >= rounds * 2 }

    /// The leader once the game is over; nil while playing or on a draw.
    public var winner: Int? {
        guard isOver, scores[0] != scores[1] else { return nil }
        return scores[0] > scores[1] ? 0 : 1
    }

    public static func points(letters: Int, secondsLeft: TimeInterval) -> Int {
        letters + Int(max(0, secondsLeft) / 10)
    }

    /// Ends the current turn; the points the solver got.
    @discardableResult
    public mutating func finishTurn(solved: Bool, letters: Int, secondsLeft: TimeInterval) -> Int {
        guard !isOver else { return 0 }
        let points = solved ? Self.points(letters: letters, secondsLeft: secondsLeft) : 0
        scores[solver] += points
        turn += 1
        return points
    }
}
