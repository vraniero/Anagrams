import Foundation

/// A game for two players on two phones, played a turn at a time (through Game Center).
/// Everything the game needs travels with it: the rules, every solve so far and the sentence
/// waiting for the next player.
///
/// Player 0 starts by sending a sentence. From then on a turn is: solve the sentence you got,
/// then send one back. A round is one solve each, so a game is `rounds × 2` solves; whoever
/// makes the last one ends the game.
public struct OnlineDuel: Codable, Equatable, Sendable {
    public static let playerCount = 2

    public struct Sentence: Codable, Equatable, Sendable {
        public var text: String
        public var language: String
        /// Where it comes from: "From the news: …", or the author of a line.
        public var credit: String?

        public init(text: String, language: String, credit: String? = nil) {
            self.text = text
            self.language = language
            self.credit = credit
        }
    }

    public struct Word: Codable, Equatable, Sendable {
        public var text: String
        public var language: String?

        public init(text: String, language: String?) {
            self.text = text
            self.language = language
        }
    }

    /// A sentence one player sent and what the other made of it.
    public struct Solve: Codable, Equatable, Sendable {
        public var solver: Int
        public var sentence: Sentence
        public var solved: Bool
        public var answer: [Word]
        public var points: Int
        public var bonus: String?
        /// What Apple Intelligence read in the answer, when it was asked.
        public var reading: String?
    }

    /// When the app writes every sentence, instead of the players.
    public struct AppSentences: Codable, Equatable, Sendable {
        public var level: String
        public var source: String
        public var language: String?

        public init(level: String, source: String, language: String?) {
            self.level = level
            self.source = source
            self.language = language
        }
    }

    public var version = 1
    public let settings: Duel.Settings
    public let appSentences: AppSentences?
    public private(set) var solves: [Solve] = []
    /// The sentence sent to the player whose turn it is; nil when they have to send one.
    public private(set) var waiting: Sentence?
    /// When the player opened the waiting sentence: the clock runs from there, even if they
    /// leave the app.
    public private(set) var solveStarted: Date?

    public init(settings: Duel.Settings, appSentences: AppSentences? = nil) {
        self.settings = settings
        self.appSentences = appSentences
    }

    public var totalSolves: Int { settings.rounds * Self.playerCount }
    public var isOver: Bool { solves.count >= totalSolves }
    public var round: Int { min(solves.count / Self.playerCount + 1, settings.rounds) }

    /// Whose turn it is: who has to solve the waiting sentence, or else send one.
    public var current: Int {
        waiting == nil ? solves.count % Self.playerCount : (solves.count + 1) % Self.playerCount
    }

    public var scores: [Int] {
        var scores = Array(repeating: 0, count: Self.playerCount)
        for solve in solves { scores[solve.solver] += solve.points }
        return scores
    }

    /// The leader once the game is over; nil while playing or on a draw.
    public var winner: Int? {
        guard isOver else { return nil }
        let scores = scores
        guard let best = scores.max(), scores.filter({ $0 == best }).count == 1 else { return nil }
        return scores.firstIndex(of: best)
    }

    /// The last solve of the other player, which `player` hasn't seen played.
    public func lastSolve(by player: Int) -> Solve? {
        solves.last { $0.solver == player }
    }

    /// The deadline of the solve under way.
    public var deadline: Date? {
        solveStarted.map { $0.addingTimeInterval(settings.solveTime) }
    }

    /// The current player sends the next sentence.
    public mutating func send(_ sentence: Sentence) {
        guard !isOver, waiting == nil else { return }
        waiting = sentence
        solveStarted = nil
    }

    /// The current player opens the waiting sentence; the clock starts once.
    public mutating func startSolving(at date: Date = .now) {
        guard waiting != nil, solveStarted == nil else { return }
        solveStarted = date
    }

    /// The current player is done with the waiting sentence; it's then up to them to send one,
    /// unless that was the game's last solve.
    public mutating func finishSolving(solved: Bool, answer: [Word] = [], points: Int = 0,
                                       bonus: String? = nil, reading: String? = nil) {
        guard let waiting, !isOver else { return }
        solves.append(Solve(solver: current, sentence: waiting, solved: solved, answer: solved ? answer : [],
                            points: solved ? points : 0, bonus: solved ? bonus : nil, reading: solved ? reading : nil))
        self.waiting = nil
        solveStarted = nil
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public init(data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
    }
}
