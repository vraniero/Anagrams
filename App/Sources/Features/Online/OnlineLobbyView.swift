import SwiftUI
import AnagramEngine

/// The online games: whose turn it is in each, and a new game with a friend or someone new.
struct OnlineLobbyView: View {
    private var center: GameCenter { .shared }

    var body: some View {
        ThemedScreen {
            switch center.status {
            case .signedIn:
                games
            case let .signedOut(message):
                signedOut(message)
            case .unknown, .signingIn:
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large).tint(.white)
                    Text("Signing in to Game Center…").font(.headline).foregroundStyle(.white)
                }
            }
        }
        .navigationTitle("Online")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            center.signIn()
            Task { await center.refresh() }
        }
    }

    static func create(_ settings: Duel.Settings, _ sentences: AppSentences?, friend: Bool) {
        let game = OnlineDuel(settings: settings, appSentences: sentences.map {
            .init(level: $0.level.rawValue, source: $0.source.rawValue, language: $0.language)
        })
        if friend {
            GameCenter.shared.inviteFriend(game)
        } else {
            Task { await GameCenter.shared.playSomeoneNew(game) }
        }
    }

    private var games: some View {
        ScrollView {
            VStack(spacing: 16) {
                NavigationLink("New game", value: Destination.onlineSetup)
                    .buttonStyle(CreamButtonStyle())
                    .padding(.vertical, 8)
                let groups: [(String, [MatchSummary])] = [
                    ("Your turn", center.matches.filter { $0.state == .yourTurn }),
                    ("Their turn", center.matches.filter { $0.state == .theirTurn || $0.state == .findingOpponent }),
                    ("Finished", center.matches.filter { ![.yourTurn, .theirTurn, .findingOpponent].contains($0.state) }),
                ]
                ForEach(groups, id: \.0) { title, matches in
                    if !matches.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(title.uppercased())
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.glowLight)
                            ForEach(matches) { row($0) }
                        }
                        .padding(16)
                        .background(Theme.navyDeep.opacity(0.9), in: .rect(cornerRadius: 18, style: .continuous))
                    }
                }
                if center.matches.isEmpty {
                    Text(center.isLoading ? "Loading your games…"
                                          : "No games yet. Invite a friend, or play someone new: you take turns whenever you like, and Game Center tells you when it's yours.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 12)
                }
            }
            .padding(20)
        }
        .refreshable { await center.refresh() }
    }

    private func row(_ match: MatchSummary) -> some View {
        NavigationLink(value: Destination.onlineMatch(match.id)) {
            HStack(spacing: 12) {
                Image(systemName: symbol(match.state))
                    .font(.title3)
                    .foregroundStyle(match.state == .yourTurn ? Theme.ink : Theme.glowLight)
                    .frame(width: 40, height: 40)
                    .background(match.state == .yourTurn ? Theme.cream : Theme.glow.opacity(0.2),
                                in: .rect(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.state == .findingOpponent ? "Someone new" : match.opponent)
                        .font(.headline).foregroundStyle(.white)
                    Text(detail(match.state)).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.glowLight)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if ![.yourTurn, .theirTurn, .findingOpponent].contains(match.state) {
                Button("Remove", systemImage: "trash", role: .destructive) {
                    Task { await center.remove(match.id) }
                }
            }
        }
    }

    private func symbol(_ state: MatchSummary.State) -> String {
        switch state {
        case .yourTurn: "hand.point.right.fill"
        case .theirTurn: "hourglass"
        case .findingOpponent: "person.fill.questionmark"
        case .won: "trophy.fill"
        case .lost: "flag.fill"
        case .draw, .ended: "equal.circle.fill"
        }
    }

    private func detail(_ state: MatchSummary.State) -> String {
        switch state {
        case .yourTurn: "Your turn"
        case .theirTurn: "Their turn"
        case .findingOpponent: "Game Center is finding an opponent"
        case .won: "You won"
        case .lost: "You lost"
        case .draw: "A draw"
        case .ended: "Over"
        }
    }

    private func signedOut(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("Sign in to Game Center to play online")
                .font(.title2.weight(.heavy))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Text("\(message)\n\nYou can sign in from Settings → Game Center.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.8))
            Button("Try again") {
                center.status = .unknown
                center.signIn()
            }
            .buttonStyle(CreamButtonStyle())
        }
        .padding(32)
    }
}

/// The rules of a new online game, then a friend or someone new.
struct OnlineSetupView: View {
    var body: some View {
        DuelSetupView(startOnline: OnlineLobbyView.create)
            .navigationTitle("New online game")
            .navigationBarTitleDisplayMode(.inline)
    }
}
