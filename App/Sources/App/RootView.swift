import SwiftUI

/// Home menu → Training (listen, build, check), Game or Help.
struct RootView: View {
    var body: some View {
        NavigationStack {
            HomeView()
                .navigationDestination(for: Destination.self) { destination in
                    switch destination {
                    case .training: TrainingView()
                    case .game: GameModesView()
                    case .help: HelpView()
                    case .clock: ClockGameView()
                    case .duel: DuelGameView()
                    }
                }
        }
        .tint(Theme.glow)
    }
}

/// Listening, then building the anagram. Leaving it stops listening and forgets the sentence.
struct TrainingView: View {
    @Environment(GameSession.self) private var session

    var body: some View {
        Group {
            switch session.stage {
            case .listening: ListeningView()
            case .building: BoardView()
            }
        }
        .navigationTitle("Training")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { OptionsMenu() } }
        .onDisappear { session.restart() }
    }
}
