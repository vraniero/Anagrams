import SwiftUI

/// Home menu → Training (write, build, check), Game or Help.
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
