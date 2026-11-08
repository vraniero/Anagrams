import SwiftUI
import AnagramEngine

/// Two to four players, one phone. The rules (time, rounds, languages, scoring) are chosen
/// before the game and stay fixed. In turn, one player writes a sentence (typed, or read with
/// the camera) and passes the phone; the next one has the chosen time to make a full anagram.
struct DuelGameView: View {
    private enum Phase: Equatable {
        case setup, setting, handoff, solving
        case result(points: Int, solved: Bool, answer: [AnagramVerdict.CheckedWord], meaning: Meaning?)
        case over
    }

    @State private var session = GameSession()
    @State private var phase = Phase.setup
    @State private var duel = Duel(players: ["Player 1", "Player 2"])
    @State private var sentence = ""
    @State private var start = Date.now
    @State private var end: Date?

    var body: some View {
        Group {
            switch phase {
            case .setup:
                DuelSetupView(start: begin)
            case .setting:
                ListeningView(prompt: "\(setter): type a sentence for \(solver), or read one with the camera.",
                              voice: false, maxLetters: duel.settings.maxLetters, requiresCorrectSentence: true)
            case .handoff:
                handoff
            case .solving:
                BoardView(header: AnyView(header),
                          leading: BoardAction(title: "Give up", symbol: "flag.fill") { endTurn(solved: false) },
                          onCheck: check,
                          allowsSuggestions: false)
            case let .result(points, solved, answer, meaning):
                result(points: points, solved: solved, answer: answer, meaning: meaning)
            case .over:
                over
            }
        }
        .environment(session)
        .navigationTitle(phase == .setup ? "Multiplayer" : "Round \(min(duel.round, duel.rounds)) of \(duel.rounds)")
        .navigationBarTitleDisplayMode(.inline)
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
    private var letters: Int { session.letterCount }

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
                Text("\(letters) letters, \(duration(duel.settings.solveTime)) to make an anagram.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                RulesSummary(settings: duel.settings)
                Button("I'm ready", action: startSolving)
                    .buttonStyle(CreamButtonStyle())
            }
            .padding(32)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            if let end {
                Countdown(start: start, end: end)
            } else if session.isCheckingMeaning {
                Label { Text("Solved! Checking the meaning…") } icon: { ProgressView() }
                    .font(.headline)
            }
            HStack(alignment: .top, spacing: 14) {
                ForEach(duel.players.indices, id: \.self) { i in
                    ScoreLabel(name: duel.players[i], points: duel.scores[i])
                        .opacity(i == duel.solver ? 1 : 0.6)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
    }

    private func result(points: Int, solved: Bool, answer: [AnagramVerdict.CheckedWord], meaning: Meaning?) -> some View {
        ThemedScreen {
            ScrollView {
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
                    if solved, let meaning {
                        VStack(spacing: 4) {
                            Label(meaning.makesSense ? "It makes sense: double points!" : "No meaning bonus",
                                  systemImage: meaning.makesSense ? "sparkles" : "text.word.spacing")
                                .font(.headline)
                                .foregroundStyle(meaning.makesSense ? Color.orange : Theme.glowLight)
                            Text(meaning.reading)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    scoreboard
                    Button(duel.isOver ? "See who won" : "Next: \(setter) writes a sentence", action: next)
                        .buttonStyle(CreamButtonStyle())
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
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
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                scoreboard
                Button("Play again", action: playAgain)
                    .buttonStyle(CreamButtonStyle())
                Button("Change the rules") { withAnimation { phase = .setup } }
                    .foregroundStyle(Theme.glowLight)
            }
            .padding(24)
        }
    }

    private var scoreboard: some View {
        let many = duel.players.count > 2
        return HStack(spacing: many ? 12 : 32) {
            ForEach(duel.players.indices, id: \.self) { i in
                VStack {
                    Text(duel.players[i]).font(.headline).foregroundStyle(Theme.glowLight).lineLimit(1)
                    Text("\(duel.scores[i])").font(.system(size: many ? 32 : 44, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: many ? .infinity : nil)
            }
        }
        .padding()
        .background(Theme.navyDeep.opacity(0.9), in: .rect(cornerRadius: 18, style: .continuous))
    }

    // MARK: flow

    private func begin(_ players: [String], _ settings: Duel.Settings) {
        duel = Duel(players: players, settings: settings)
        session.restart()
        session.sameLanguageRule = settings.sameLanguage
        phase = .setting
    }

    /// Same players, same rules.
    private func playAgain() {
        begin(duel.players, duel.settings)
    }

    private func startSolving() {
        start = .now
        end = start.addingTimeInterval(duel.settings.solveTime)
        phase = .solving
    }

    private func check() async {
        let secondsLeft = end?.timeIntervalSinceNow ?? 0
        let verdict = await session.evaluate()
        guard phase == .solving else { return }
        guard verdict.isValid else {
            session.verdict = verdict  // "Not yet", and why
            return
        }
        end = nil  // solved: the clock stops while the meaning is read
        let meaning = duel.settings.meaningBonus ? await session.meaning(of: verdict) : nil
        guard phase == .solving else { return }
        endTurn(solved: true, answer: verdict.words, secondsLeft: secondsLeft, meaning: meaning)
    }

    private func endTurn(solved: Bool, answer: [AnagramVerdict.CheckedWord] = [], secondsLeft: TimeInterval? = nil,
                         meaning: Meaning? = nil) {
        let secondsLeft = secondsLeft ?? end?.timeIntervalSinceNow ?? 0
        end = nil
        session.verdict = nil
        let points = duel.finishTurn(solved: solved, letters: letters, secondsLeft: secondsLeft,
                                     makesSense: meaning?.makesSense == true)
        withAnimation { phase = .result(points: points, solved: solved, answer: answer, meaning: meaning) }
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

/// "1 minute", "2 minutes", "90 seconds".
private func duration(_ seconds: TimeInterval) -> String {
    let s = Int(seconds)
    if s % 60 != 0 { return "\(s) seconds" }
    return s == 60 ? "1 minute" : "\(s / 60) minutes"
}

extension Duel.Settings.Scoring {
    var title: String {
        switch self {
        case .lettersAndTime: "Letters + speed"
        case .letters: "Letters"
        case .anagrams: "Anagrams"
        }
    }

    var detail: String {
        switch self {
        case .lettersAndTime: "A point per letter, plus one for every 10 seconds left."
        case .letters: "A point per letter of the sentence."
        case .anagrams: "One point for each anagram made."
        }
    }
}

/// The game's rules, as chips.
private struct RulesSummary: View {
    let settings: Duel.Settings

    var body: some View {
        FlowLayout(spacing: 8) {
            chip(settings.sameLanguage ? "One language" : "Any languages", "character.book.closed")
            chip(settings.scoring.title, "star")
            chip("\(settings.rounds) \(settings.rounds == 1 ? "round" : "rounds")", "repeat")
            chip("≤ \(settings.maxLetters) letters", "textformat.size")
            if settings.meaningBonus { chip("Meaning ×2", "sparkles") }
        }
    }

    private func chip(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.navyDeep.opacity(0.9), in: .capsule)
            .foregroundStyle(Theme.glowLight)
    }
}

/// Players and rules, decided before the game starts (and remembered for next time).
private struct DuelSetupView: View {
    let start: ([String], Duel.Settings) -> Void

    @AppStorage("duel.players") private var savedNames = ""
    @AppStorage("duel.time") private var time = 120.0
    @AppStorage("duel.rounds") private var rounds = 3
    @AppStorage("duel.sameLanguage") private var sameLanguage = false
    @AppStorage("duel.scoring") private var scoring = Duel.Settings.Scoring.lettersAndTime.rawValue
    @AppStorage("duel.meaningBonus") private var meaningBonus = true
    @AppStorage("duel.maxLetters") private var maxLetters = 20
    @Environment(GameSession.self) private var session
    private struct Entry: Identifiable {
        let id = UUID()
        var name = ""
    }

    @State private var entries = [Entry(), Entry()]
    @State private var loaded = false

    private var scoringChoice: Binding<Duel.Settings.Scoring> {
        Binding { Duel.Settings.Scoring(rawValue: scoring) ?? .lettersAndTime } set: { scoring = $0.rawValue }
    }

    var body: some View {
        ThemedScreen {
            ScrollView {
                VStack(spacing: 16) {
                    section("Players") {
                        ForEach($entries) { $entry in
                            let i = entries.firstIndex { $0.id == entry.id } ?? 0
                            HStack {
                                TextField("", text: $entry.name,
                                          prompt: Text("Player \(i + 1)").foregroundStyle(.white.opacity(0.5)))
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .textInputAutocapitalization(.words)
                                    .submitLabel(.next)
                                if entries.count > Duel.Settings.playerRange.lowerBound {
                                    Button("Remove player \(i + 1)", systemImage: "minus.circle.fill") {
                                        let id = entry.id
                                        withAnimation { entries.removeAll { $0.id == id } }
                                    }
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(.white.opacity(0.6))
                                }
                            }
                            .padding(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.glow.opacity(0.6)))
                        }
                        if entries.count < Duel.Settings.playerRange.upperBound {
                            Button("Add player", systemImage: "plus.circle.fill") {
                                withAnimation { entries.append(Entry()) }
                            }
                            .foregroundStyle(Theme.glowLight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    section("Rules") {
                        rule("Time to solve") {
                            Picker("Time to solve", selection: $time) {
                                ForEach(Duel.Settings.times, id: \.self) { t in
                                    Text("\(Int(t) / 60) min").tag(t)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        rule("Rounds") {
                            Stepper(value: $rounds, in: Duel.Settings.roundRange) {
                                Text("\(rounds) \(rounds == 1 ? "round" : "rounds")")
                                    .foregroundStyle(.white)
                            }
                            Text("Each round, everyone writes one sentence for the next player.")
                                .font(.footnote).foregroundStyle(.white.opacity(0.7))
                        }
                        rule("Longest sentence") {
                            Picker("Longest sentence", selection: $maxLetters) {
                                ForEach(Duel.Settings.letterLimits, id: \.self) { Text("\($0)").tag($0) }
                            }
                            .pickerStyle(.segmented)
                            Text("At most \(maxLetters) letters per sentence. Spaces and punctuation don't count.")
                                .font(.footnote).foregroundStyle(.white.opacity(0.7))
                        }
                        rule("Languages") {
                            Picker("Languages", selection: $sameLanguage) {
                                Text("Any languages").tag(false)
                                Text("One language").tag(true)
                            }
                            .pickerStyle(.segmented)
                            Text(sameLanguage ? "All the words of an anagram must be in the same language."
                                              : "Each word may be in a different language.")
                                .font(.footnote).foregroundStyle(.white.opacity(0.7))
                        }
                        rule("Scoring") {
                            Picker("Scoring", selection: scoringChoice) {
                                ForEach(Duel.Settings.Scoring.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            Text(scoringChoice.wrappedValue.detail)
                                .font(.footnote).foregroundStyle(.white.opacity(0.7))
                        }
                        rule("Meaning bonus") {
                            Toggle(isOn: $meaningBonus) {
                                Text("Double points when the anagram means something")
                                    .foregroundStyle(.white)
                            }
                            .disabled(!session.canCheckMeaning)
                            .tint(Theme.glow)
                            Text(session.canCheckMeaning
                                 ? "For anagrams of two or more words. Apple Intelligence reads them on this iPhone."
                                 : "Needs Apple Intelligence, which isn't available on this iPhone.")
                                .font(.footnote).foregroundStyle(.white.opacity(0.7))
                        }
                    }

                    Text("In turn, each player writes a sentence and passes the phone to the next, who makes the anagram. No suggestions in a game.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Start", action: go)
                        .buttonStyle(CreamButtonStyle())
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .environment(\.colorScheme, .dark)
        .onAppear(perform: load)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.glowLight)
            content()
        }
        .padding(16)
        .background(Theme.navyDeep.opacity(0.9), in: .rect(cornerRadius: 18, style: .continuous))
    }

    private func rule<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(.white)
            content()
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let saved = savedNames.components(separatedBy: "\n")
        if Duel.Settings.playerRange.contains(saved.count) { entries = saved.map { Entry(name: $0) } }
        if !Duel.Settings.times.contains(time) { time = 120 }
        if !Duel.Settings.letterLimits.contains(maxLetters) { maxLetters = 20 }
    }

    private func go() {
        savedNames = entries.map(\.name).joined(separator: "\n")
        let players = entries.enumerated().map { i, entry in
            let trimmed = entry.name.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "Player \(i + 1)" : trimmed
        }
        start(players, Duel.Settings(solveTime: time, rounds: rounds, sameLanguage: sameLanguage,
                                     scoring: scoringChoice.wrappedValue,
                                     meaningBonus: meaningBonus && session.canCheckMeaning,
                                     maxLetters: maxLetters))
    }
}
