import SwiftUI

/// Home menu → Training (write, build, check), Game or Help.
struct RootView: View {
    @State private var path: [Destination] = []
    private var center: GameCenter { .shared }

    var body: some View {
        NavigationStack(path: $path) {
            HomeView()
                .navigationDestination(for: Destination.self) { destination in
                    switch destination {
                    case .training: TrainingView()
                    case .game: GameModesView()
                    case .help: HelpView()
                    case .clock: ClockGameView()
                    case .duel: DuelGameView()
                    case .online: OnlineLobbyView()
                    case .onlineSetup: OnlineSetupView()
                    case let .onlineMatch(id): OnlineMatchView(link: center.link(id)).id(id)
                    }
                }
        }
        .tint(Theme.glow)
        .onAppear { center.signInIfUsed() }
        .alert("Game Center", isPresented: Binding { center.error != nil } set: { if !$0 { center.error = nil } }) {
            Button("OK") { center.error = nil }
        } message: {
            Text(center.error ?? "")
        }

        // an online game to show: just created, or its turn came (a notification was tapped)
        .onChange(of: center.opened) { _, id in
            guard let id else { return }
            center.opened = nil
            path = [.game, .online, .onlineMatch(id)]
        }
    }
}

/// Writing the sentence, then building the anagram. Leaving it forgets the sentence.
struct TrainingView: View {
    @Environment(GameSession.self) private var session

    var body: some View {
        Group {
            switch session.stage {
            case .writing: SentenceView()
            case .building: BoardView()
            }
        }
        .navigationTitle("Training")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { OptionsMenu() } }
        .onDisappear { session.restart() }
    }
}
