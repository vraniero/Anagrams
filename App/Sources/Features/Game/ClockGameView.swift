import SwiftUI
import AnagramEngine

/// Against the clock: say or type a sentence; when you tap Make anagram the clock starts.
/// Every word you build and check scores its letters (once); a full anagram scores double.
struct ClockGameView: View {
    private enum Phase { case sentence, playing, over }

    @State private var session = GameSession()
    @State private var phase = Phase.sentence
    @State private var round = ClockRound()
    @State private var start = Date.now
    @State private var end: Date?
    @State private var feedback: [ClockRound.Outcome] = []

    var body: some View {
        Group {
            switch phase {
            case .sentence:
                ListeningView(prompt: "Type a sentence, or read one with the camera. The clock starts when you tap Make anagram.",
                              voice: false)
            case .playing:
                BoardView(header: AnyView(header),
                          leading: BoardAction(title: "Stop", symbol: "stop.fill") { finish() },
                          onCheck: check)
            case .over:
                ClockResultView(round: round, playAgain: playAgain)
            }
        }
        .environment(session)
        .navigationTitle("Against the clock")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { OptionsMenu() } }
        .onChange(of: session.stage) { _, stage in
            if stage == .building && phase == .sentence { begin() }
        }
        .task(id: end) {
            guard let end else { return }
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            if !Task.isCancelled && phase == .playing { finish() }
        }
        .sensoryFeedback(.success, trigger: round.score)
        .onDisappear { session.restart() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                if let end { Countdown(start: start, end: end) }
                Spacer(minLength: 24)
                ScoreLabel(name: "Score", points: round.score)
            }
            if !feedback.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(feedback.enumerated()), id: \.offset) { _, outcome in
                        FeedbackChip(outcome: outcome)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding()
    }

    private func begin() {
        round = ClockRound()
        feedback = []
        start = .now
        end = start.addingTimeInterval(ClockRound.duration)
        phase = .playing
    }

    private func check() async {
        let verdict = await session.evaluate()
        guard phase == .playing else { return }
        let outcomes = round.score(verdict, source: session.source)
        withAnimation(.snappy) { feedback = outcomes }
        // scored: clear the board for the next words; otherwise leave it to fix
        if outcomes.contains(where: { if case .scored = $0 { true } else { false } }) {
            withAnimation(BoardView.move) { session.board.clear() }
        }
    }

    private func finish() {
        end = nil
        session.verdict = nil
        withAnimation { phase = .over }
    }

    private func playAgain() {
        session.restart()
        round = ClockRound()
        feedback = []
        phase = .sentence
    }
}

private struct FeedbackChip: View {
    let outcome: ClockRound.Outcome

    var body: some View {
        let (text, color): (String, Color) = switch outcome {
        case .scored(let found):
            ("+\(found.points) \(found.isFullAnagram ? "★ anagram" : found.text.lowercased()) · \(languageNames(found.languages))", .green)
        case .alreadyFound(let word): ("\(word.lowercased()): already found", .orange)
        case .notAWord(let word): ("\(word.lowercased()): not a word", .red)
        case .fromSentence(let word): ("\(word.lowercased()): from the sentence", .orange)
        case .mixedLanguages: ("words must share one language", .orange)
        }
        Text(text)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }
}

private struct ClockResultView: View {
    let round: ClockRound
    let playAgain: () -> Void

    var body: some View {
        ThemedScreen {
            VStack(spacing: 18) {
                Text("Time's up!")
                    .font(.largeTitle.weight(.heavy))
                    .foregroundStyle(.white)
                HStack(spacing: 4) {
                    let digits = Array(String(round.score))
                    ForEach(digits.indices, id: \.self) { CreamTile(letter: digits[$0], size: 64) }
                }
                Text(round.score == 1 ? "point" : "points")
                    .foregroundStyle(Theme.glowLight)
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(round.found) { found in
                            HStack {
                                Text(found.isFullAnagram ? "★ \(found.text.lowercased())" : found.text.lowercased())
                                    .font(.headline)
                                Spacer()
                                Text(languageNames(found.languages)).font(.subheadline).foregroundStyle(.white.opacity(0.6))
                                Text("+\(found.points)").font(.headline).monospacedDigit()
                            }
                            .foregroundStyle(.white)
                        }
                        if round.found.isEmpty {
                            Text("No words this time.").foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 280)
                .background(Theme.navyDeep.opacity(0.9), in: .rect(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 24)
                Button("Play again", action: playAgain)
                    .buttonStyle(CreamButtonStyle())
            }
            .padding(.vertical)
        }
    }
}
