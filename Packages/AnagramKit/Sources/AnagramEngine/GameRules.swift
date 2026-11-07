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

/// Players (2 to 4) take turns: one writes a sentence, the next has a limited time to make
/// a full anagram of it. Each round, everyone sets a sentence once. The rules are chosen
/// before the game starts and don't change while it's played.
public struct Duel: Equatable, Sendable {
    public struct Settings: Equatable, Sendable {
        public enum Scoring: String, CaseIterable, Sendable {
            /// A point per letter, plus one for every ten seconds left.
            case lettersAndTime
            /// A point per letter.
            case letters
            /// A point per anagram.
            case anagrams
        }

        public static let times: [TimeInterval] = [60, 120, 180, 300]
        public static let playerRange = 2...4
        public static let roundRange = 1...10

        public var solveTime: TimeInterval
        public var rounds: Int
        /// All the words of an anagram must be in one language.
        public var sameLanguage: Bool
        public var scoring: Scoring

        public init(solveTime: TimeInterval = 120, rounds: Int = 3, sameLanguage: Bool = false,
                    scoring: Scoring = .lettersAndTime) {
            self.solveTime = max(10, solveTime)
            self.rounds = min(max(rounds, Self.roundRange.lowerBound), Self.roundRange.upperBound)
            self.sameLanguage = sameLanguage
            self.scoring = scoring
        }

        public func points(letters: Int, secondsLeft: TimeInterval) -> Int {
            switch scoring {
            case .lettersAndTime: letters + Int(max(0, secondsLeft) / 10)
            case .letters: letters
            case .anagrams: 1
            }
        }
    }

    public let players: [String]
    public let settings: Settings
    public private(set) var scores: [Int]
    /// Turns played; a round is one turn per player, so everyone sets a sentence once.
    public private(set) var turn = 0

    public init(players: [String], settings: Settings = Settings()) {
        precondition(Settings.playerRange.contains(players.count))
        self.players = players
        self.settings = settings
        scores = Array(repeating: 0, count: players.count)
    }

    public var rounds: Int { settings.rounds }
    /// Who writes the sentence; the next player solves it.
    public var setter: Int { turn % players.count }
    public var solver: Int { (setter + 1) % players.count }
    public var round: Int { turn / players.count + 1 }
    public var isOver: Bool { turn >= rounds * players.count }

    /// The leader once the game is over; nil while playing or on a tie for first.
    public var winner: Int? {
        guard isOver, let best = scores.max(), scores.filter({ $0 == best }).count == 1 else { return nil }
        return scores.firstIndex(of: best)
    }

    /// Ends the current turn; the points the solver got.
    @discardableResult
    public mutating func finishTurn(solved: Bool, letters: Int, secondsLeft: TimeInterval) -> Int {
        guard !isOver else { return 0 }
        let points = solved ? settings.points(letters: letters, secondsLeft: secondsLeft) : 0
        scores[solver] += points
        turn += 1
        return points
    }
}
