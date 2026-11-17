@preconcurrency import GameKit
import SwiftUI
import AnagramEngine

/// One online game as the lobby lists it.
struct MatchSummary: Identifiable, Equatable {
    enum State: Equatable { case yourTurn, theirTurn, findingOpponent, won, lost, draw, ended }
    let id: String
    let opponent: String
    let state: State
    let updated: Date?
}

/// A game as one player sees it, at the moment it was loaded.
struct MatchSnapshot {
    /// nil until the first player sets the rules.
    var game: OnlineDuel?
    /// Which player this phone is (0 or 1).
    var me: Int
    var names: [String]
    var isMyTurn: Bool
    var isOpen: Bool
    /// Still looking for someone to play against.
    var isMatching: Bool
    var opponentQuit: Bool

    var opponent: String { names[1 - me] }
}

/// Talks to one online game.
@MainActor
protocol MatchLink: AnyObject {
    var id: String { get }
    func load() async throws -> MatchSnapshot
    /// Stores the game without passing the turn.
    func save(_ game: OnlineDuel) async throws
    /// Stores the game and hands the turn to the other player.
    func pass(_ game: OnlineDuel, message: String) async throws
    /// The game is over: stores it and gives each player their outcome.
    func end(_ game: OnlineDuel) async throws
    /// Gives up the game: the other player wins.
    func resign(_ game: OnlineDuel?) async throws
}

/// Signing in to Game Center, the list of online games, and opening one when its turn
/// comes (from a notification) or when it's created.
@MainActor @Observable
final class GameCenter {
    static let shared = GameCenter()

    enum Status: Equatable { case unknown, signingIn, signedIn, signedOut(String) }
    var status = Status.unknown
    var matches: [MatchSummary] = []
    var isLoading = false
    var error: String?
    /// A game to show now.
    var opened: String?
    /// Bumped when a game changes elsewhere, so an open game reloads.
    private(set) var changes: [String: Int] = [:]
    /// The rules for the next game this player creates.
    var newGame: OnlineDuel?

    /// Plays against a pretend opponent instead of Game Center (for UI tests and screenshots).
    let isDemo = ProcessInfo.processInfo.arguments.contains("-onlineDemo")
    private var demo: [String: DemoMatchLink] = [:]
    private var listener: Listener?
    private weak var matchmaker: UIViewController?

    /// Remembered so the app signs in at launch (to hear about turns) only for those who play online.
    @ObservationIgnored @AppStorage("online.used") private var used = false

    private init() {}

    func link(_ id: String) -> MatchLink {
        if isDemo { return demo[id] ?? DemoMatchLink(id: id) }
        return GameKitMatchLink(id: id)
    }

    /// At launch: signs in quietly if this player has played online before.
    func signInIfUsed() {
        if used { signIn() }
    }

    func signIn() {
        if isDemo {
            status = .signedIn
            return
        }
        if GKLocalPlayer.local.isAuthenticated { return authenticated(nil, nil) }
        guard status != .signingIn else { return }
        status = .signingIn
        GKLocalPlayer.local.authenticateHandler = { controller, error in
            MainActor.assumeIsolated {
                GameCenter.shared.authenticated(controller, error)
            }
        }
    }

    private func authenticated(_ controller: UIViewController?, _ error: Error?) {
        if let controller {
            Self.present(controller)
            return
        }
        if GKLocalPlayer.local.isAuthenticated {
            status = .signedIn
            used = true
            if listener == nil {
                let listener = Listener()
                GKLocalPlayer.local.register(listener)
                self.listener = listener
            }
            Task { await refresh() }
        } else {
            status = .signedOut(error?.localizedDescription ?? "Not signed in to Game Center.")
        }
    }

    func refresh() async {
        if isDemo {
            matches = demo.values.map { $0.summary() }.sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }
            return
        }
        guard status == .signedIn else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let found = try await GKTurnBasedMatch.loadMatches()
            matches = found.map(Self.summary).sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// A game against whoever Game Center finds.
    func playSomeoneNew(_ game: OnlineDuel) async {
        newGame = game
        if isDemo { return openDemo(game) }
        do {
            let match = try await GKTurnBasedMatch.find(for: Self.request)
            opened = match.matchID
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// A game against a friend, chosen in Game Center's own screen (which can also invite by
    /// message).
    func inviteFriend(_ game: OnlineDuel) {
        newGame = game
        if isDemo { return openDemo(game) }
        let controller = GKTurnBasedMatchmakerViewController(matchRequest: Self.request)
        controller.showExistingMatches = false
        controller.turnBasedMatchmakerDelegate = MatchmakerDelegate.shared
        matchmaker = controller
        Self.present(controller)
    }

    func remove(_ id: String) async {
        if !isDemo, let match = try? await GKTurnBasedMatch.load(withID: id) {
            try? await match.remove()
        }
        demo[id] = nil
        matches.removeAll { $0.id == id }
    }

    fileprivate func turnEvent(_ id: String, becameActive: Bool) {
        changes[id, default: 0] += 1
        if let matchmaker {
            matchmaker.dismiss(animated: true)
            self.matchmaker = nil
            opened = id
        } else if becameActive {
            opened = id
        }
        Task { await refresh() }
    }

    fileprivate func matchmakerClosed(_ error: Error?) {
        matchmaker?.dismiss(animated: true)
        matchmaker = nil
        if let error { self.error = error.localizedDescription }
    }

    private func openDemo(_ game: OnlineDuel) {
        let link = DemoMatchLink(id: UUID().uuidString)
        demo[link.id] = link
        opened = link.id
    }

    private static var request: GKMatchRequest {
        let request = GKMatchRequest()
        request.minPlayers = OnlineDuel.playerCount
        request.maxPlayers = OnlineDuel.playerCount
        request.inviteMessage = "Let's play Anagrams!"
        return request
    }

    private static func summary(_ match: GKTurnBasedMatch) -> MatchSummary {
        let me = match.participants.first { $0.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID }
        let other = match.participants.first { $0 !== me }
        let state: MatchSummary.State = switch match.status {
        case .ended:
            switch me?.matchOutcome {
            case .won: .won
            case .lost, .quit, .timeExpired: .lost
            case .tied: .draw
            default: .ended
            }
        case .matching where other?.player == nil && match.currentParticipant !== me: .findingOpponent
        default:
            match.currentParticipant === me ? .yourTurn
                : other?.player == nil ? .findingOpponent : .theirTurn
        }
        return MatchSummary(id: match.matchID, opponent: other?.player?.displayName ?? "Someone new",
                            state: state, updated: match.participants.compactMap(\.lastTurnDate).max() ?? match.creationDate)
    }

    static func present(_ controller: UIViewController) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard var top = scene?.keyWindow?.rootViewController ?? scene?.windows.first?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        top.present(controller, animated: true)
    }

    /// Hears about turns, also when a notification is tapped.
    private final class Listener: NSObject, GKLocalPlayerListener, Sendable {
        func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool) {
            let id = match.matchID
            Task { @MainActor in GameCenter.shared.turnEvent(id, becameActive: didBecomeActive) }
        }

        func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
            let id = match.matchID
            Task { @MainActor in GameCenter.shared.turnEvent(id, becameActive: false) }
        }
    }

    private final class MatchmakerDelegate: NSObject, GKTurnBasedMatchmakerViewControllerDelegate, Sendable {
        static let shared = MatchmakerDelegate()

        func turnBasedMatchmakerViewControllerWasCancelled(_ viewController: GKTurnBasedMatchmakerViewController) {
            Task { @MainActor in GameCenter.shared.matchmakerClosed(nil) }
        }

        func turnBasedMatchmakerViewController(_ viewController: GKTurnBasedMatchmakerViewController,
                                               didFailWithError error: Error) {
            let message = error.localizedDescription
            Task { @MainActor in GameCenter.shared.matchmakerClosed(NSError(domain: "GameCenter", code: 0,
                                                                         userInfo: [NSLocalizedDescriptionKey: message])) }
        }
    }
}

/// A Game Center turn-based match.
@MainActor
final class GameKitMatchLink: MatchLink {
    let id: String
    private var match: GKTurnBasedMatch?

    init(id: String) { self.id = id }

    func load() async throws -> MatchSnapshot {
        let match = try await GKTurnBasedMatch.load(withID: id)
        self.match = match
        let data = try await match.loadMatchData()
        let local = GKLocalPlayer.local.gamePlayerID
        let me = match.participants.firstIndex { $0.player?.gamePlayerID == local } ?? 0
        let names = match.participants.enumerated().map { i, participant in
            i == me ? "You" : participant.player?.displayName ?? "Your opponent"
        }
        let other = match.participants.indices.contains(1 - me) ? match.participants[1 - me] : nil
        return MatchSnapshot(game: data.flatMap { $0.isEmpty ? nil : try? OnlineDuel(data: $0) },
                             me: me, names: names,
                             isMyTurn: match.currentParticipant?.player?.gamePlayerID == local,
                             isOpen: match.status == .open || match.status == .matching,
                             isMatching: other?.player == nil,
                             opponentQuit: other?.matchOutcome == .quit)
    }

    private func loaded() async throws -> GKTurnBasedMatch {
        if let match { return match }
        _ = try await load()
        return match!
    }

    func save(_ game: OnlineDuel) async throws {
        try await loaded().saveCurrentTurn(withMatch: game.encoded())
    }

    func pass(_ game: OnlineDuel, message: String) async throws {
        let match = try await loaded()
        let others = match.participants.filter { $0.player?.gamePlayerID != GKLocalPlayer.local.gamePlayerID }
        match.message = message
        try await match.endTurn(withNextParticipants: others, turnTimeout: GKTurnTimeoutDefault,
                                match: game.encoded())
    }

    func end(_ game: OnlineDuel) async throws {
        let match = try await loaded()
        // whoever didn't leave wins; otherwise the score decides
        let someoneQuit = match.participants.contains { $0.matchOutcome == .quit }
        for (i, participant) in match.participants.enumerated() where participant.matchOutcome == .none {
            participant.matchOutcome = someoneQuit ? .won : game.winner == nil ? .tied : game.winner == i ? .won : .lost
        }
        match.message = "Game over"
        try await match.endMatchInTurn(withMatch: game.encoded())
    }

    func resign(_ game: OnlineDuel?) async throws {
        let match = try await loaded()
        let local = GKLocalPlayer.local.gamePlayerID
        guard match.status != .ended else { return }
        if match.currentParticipant?.player?.gamePlayerID == local {
            for participant in match.participants {
                participant.matchOutcome = participant.player?.gamePlayerID == local ? .quit : .won
            }
            try await match.endMatchInTurn(withMatch: (try? game?.encoded()) ?? match.matchData ?? Data())
        } else {
            try await match.participantQuitOutOfTurn(with: .quit)
        }
    }
}

/// A pretend game against "Robin", who never solves anything and always sends "Dormitory"
/// straight back. For UI tests and screenshots (`-onlineDemo`).
@MainActor
final class DemoMatchLink: MatchLink {
    let id: String
    private var game: OnlineDuel?
    private var myTurn = true
    private var outcome: MatchSummary.State?
    private var updated = Date.now

    init(id: String) {
        self.id = id
        game = nil
    }

    func load() async throws -> MatchSnapshot {
        MatchSnapshot(game: game, me: 0, names: ["You", "Robin"], isMyTurn: myTurn && outcome == nil,
                      isOpen: outcome == nil, isMatching: false, opponentQuit: false)
    }

    func summary() -> MatchSummary {
        MatchSummary(id: id, opponent: "Robin", state: outcome ?? (myTurn ? .yourTurn : .theirTurn), updated: updated)
    }

    func save(_ game: OnlineDuel) async throws {
        self.game = game
    }

    func pass(_ game: OnlineDuel, message: String) async throws {
        var game = game
        updated = .now
        // Robin's turn: gives up on the sentence, then sends one back
        game.finishSolving(solved: false)
        if game.isOver {
            self.game = game
            outcome = game.winner == 0 ? .won : game.winner == nil ? .draw : .lost
            return
        }
        game.send(.init(text: "Dormitory", language: "en"))
        self.game = game
        myTurn = true
    }

    func end(_ game: OnlineDuel) async throws {
        self.game = game
        outcome = game.winner == 0 ? .won : game.winner == nil ? .draw : .lost
    }

    func resign(_ game: OnlineDuel?) async throws {
        outcome = .lost
    }
}
