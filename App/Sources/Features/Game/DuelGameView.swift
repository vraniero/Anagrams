import SwiftUI
import AnagramEngine

/// Two players, one phone. In turn, one says (or types) a sentence and passes the phone;
/// the other has two minutes to make a full anagram of it.
struct DuelGameView: View {
    private enum Phase: Equatable {
        case setup, setting, handoff, solving
        case result(points: Int, solved: Bool, answer: [AnagramVerdict.CheckedWord])
        case over
    }

    @State private var session = GameSession()
    @State private var phase = Phase.setup
    @State private var names = ["", ""]
    @State private var rounds = 3
    @State private var duel = Duel(players: ["Player 1", "Player 2"], rounds: 3)
    @State private var sentence = ""
    @State private var start = Date.now
    @State private var end: Date?

    var body: some View {
        Group {
            switch phase {
            case .setup:
                DuelSetupView(names: $names, rounds: $rounds, start: begin)
            case .setting:
                ListeningView(prompt: "\(setter): say or type a sentence for \(solver).")
            case .handoff:
                handoff
            case .solving:
                BoardView(header: AnyView(header),
                          leading: BoardAction(title: "Give up", symbol: "flag.fill") { endTurn(solved: false) },
                          onCheck: check)
            case let .result(points, solved, answer):
                result(points: points, solved: solved, answer: answer)
            case .over:
                over
            }
        }
        .environment(session)
        .navigationTitle(phase == .setup ? "Two players" : "Round \(min(duel.round, duel.rounds)) of \(duel.rounds)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { OptionsMenu() } }
        .onChange(of: session.stage) { _, stage in
            if stage == .building && phase == .setting {
                sentence = session.source.text
                phase = .handoff
            }
        }
        .task(id: end) {
            guard let end else { return }
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            if !Task.isCancelled && phase == .solving { endTurn(solved: false) }
        }
        .onDisappear { session.restart() }
    }

    private var setter: String { duel.players[duel.setter] }
    private var solver: String { duel.players[duel.solver] }
    private var letters: Int { session.source.words.reduce(0) { $0 + $1.blocks.count } }

    // MARK: screens

    private var handoff: some View {
        ThemedScreen {
            VStack(spacing: 24) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.glowLight)
                Text("Pass the phone to \(solver)")
                    .font(.largeTitle.weight(.heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Text("\(letters) letters, \(Int(Duel.solveTime / 60)) minutes to make an anagram.")
                    .foregroundStyle(.white.opacity(0.8))
                Button("I'm ready", action: startSolving)
                    .buttonStyle(CreamButtonStyle())
            }
            .padding(32)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            if let end { Countdown(start: start, end: end).frame(maxWidth: 160) }
            Spacer()
            ScoreLabel(name: duel.players[0], points: duel.scores[0])
            ScoreLabel(name: duel.players[1], points: duel.scores[1])
                .padding(.leading, 12)
        }
        .padding()
    }

    private func result(points: Int, solved: Bool, answer: [AnagramVerdict.CheckedWord]) -> some View {
        ThemedScreen {
            VStack(spacing: 18) {
                Image(systemName: solved ? "checkmark.seal.fill" : "hourglass")
                    .font(.system(size: 56))
                    .foregroundStyle(solved ? .green : Theme.glowLight)
                // the turn has moved on: who just solved now sets the next sentence
                Text(solved ? "\(duel.players[duel.setter]) did it! +\(points)" : "No anagram this time")
                    .font(.title.weight(.heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                VStack(spacing: 6) {
                    Text(sentence.lowercased()).font(.headline)
                    if !answer.isEmpty {
                        Image(systemName: "arrow.down")
                        ForEach(Array(answer.enumerated()), id: \.offset) { _, word in
                            HStack(spacing: 8) {
                                Text(word.text.lowercased()).font(.headline)
                                Text(languageName(word.language) ?? "")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.glowLight)
                            }
                        }
                    }
                }
                .foregroundStyle(Theme.cream)
                scoreboard
                Button(duel.isOver ? "See who won" : "Next: \(setter) says a sentence", action: next)
                    .buttonStyle(CreamButtonStyle())
            }
            .padding(24)
        }
    }

    private var over: some View {
        ThemedScreen {
            VStack(spacing: 22) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.yellow)
                    .symbolEffect(.bounce, options: .repeat(2))
                Text(duel.winner.map { "\(duel.players[$0]) wins!" } ?? "It's a draw!")
                    .font(.largeTitle.weight(.heavy))
                    .foregroundStyle(.white)
                scoreboard
                Button("Play again", action: begin)
                    .buttonStyle(CreamButtonStyle())
            }
            .padding(24)
        }
    }

    private var scoreboard: some View {
        HStack(spacing: 32) {
            ForEach(0..<2, id: \.self) { i in
                VStack {
                    Text(duel.players[i]).font(.headline).foregroundStyle(Theme.glowLight)
                    Text("\(duel.scores[i])").font(.system(size: 44, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
        }
        .padding()
        .background(Theme.navyDeep.opacity(0.9), in: .rect(cornerRadius: 18, style: .continuous))
    }

    // MARK: flow

    private func begin() {
        let players = names.enumerated().map { i, name in
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "Player \(i + 1)" : trimmed
        }
        duel = Duel(players: players, rounds: rounds)
        session.restart()
        phase = .setting
    }

    private func startSolving() {
        start = .now
        end = start.addingTimeInterval(Duel.solveTime)
        phase = .solving
    }

    private func check() async {
        let verdict = await session.evaluate()
        guard phase == .solving else { return }
        if verdict.isValid {
            endTurn(solved: true, answer: verdict.words)
        } else {
            session.verdict = verdict  // "Not yet", and why
        }
    }

    private func endTurn(solved: Bool, answer: [AnagramVerdict.CheckedWord] = []) {
        let secondsLeft = end?.timeIntervalSinceNow ?? 0
        end = nil
        session.verdict = nil
        let points = duel.finishTurn(solved: solved, letters: letters, secondsLeft: secondsLeft)
        withAnimation { phase = .result(points: points, solved: solved, answer: answer) }
    }

    private func next() {
        if duel.isOver {
            withAnimation { phase = .over }
        } else {
            session.restart()
            phase = .setting
        }
    }
}

private struct DuelSetupView: View {
    @Binding var names: [String]
    @Binding var rounds: Int
    let start: () -> Void

    var body: some View {
        ThemedScreen {
            VStack(spacing: 18) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.glowLight)
                ForEach(0..<2, id: \.self) { i in
                    TextField("", text: $names[i], prompt: Text("Player \(i + 1)").foregroundStyle(.white.opacity(0.5)))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(Theme.navyDeep.opacity(0.9), in: .rect(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.glow.opacity(0.6)))
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                }
                Stepper(value: $rounds, in: 1...10) {
                    Text("\(rounds) \(rounds == 1 ? "round" : "rounds")")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(14)
                .background(Theme.navyDeep.opacity(0.9), in: .rect(cornerRadius: 14, style: .continuous))
                Text("Each round, both of you say a sentence for the other. A full anagram scores a point per letter, plus one for every 10 seconds left.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Start", action: start)
                    .buttonStyle(CreamButtonStyle())
                    .padding(.top, 8)
            }
            .padding(24)
        }
    }
}
