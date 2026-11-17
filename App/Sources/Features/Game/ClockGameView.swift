import SwiftUI
import AnagramEngine

/// Against the clock: pick a level (and where the sentence comes from); the app makes the
/// sentence and the clock starts. Every word you build and check scores its letters (once);
/// a full anagram scores double, and double again if its words mean something together.
struct ClockGameView: View {
    private enum Phase { case setup, playing, over }

    @State private var session = GameSession()
    @State private var phase = Phase.setup
    @State private var made: MadeSentence?
    @State private var round = ClockRound()
    @State private var start = Date.now
    @State private var end: Date?
    @State private var feedback: [ClockRound.Outcome] = []

    var body: some View {
        Group {
            switch phase {
            case .setup:
                ClockSetupView(start: startRound)
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
            if stage == .building && phase == .setup { begin() }
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
            if let headline = made?.headline {
                Label(headline, systemImage: "newspaper")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let quote = made?.quote {
                Label("“\(quote.text)” — \(quote.credit)", systemImage: "books.vertical")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if session.isCheckingMeaning {
                Label { Text("Checking the meaning…") } icon: { ProgressView() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !feedback.isEmpty {
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

    /// The app's sentence is ready: on the board, and the clock starts.
    private func startRound(_ sentence: MadeSentence) {
        made = sentence
        session.restart()
        session.startOver(with: sentence.text, language: sentence.language)
        session.makeAnagram()
    }

    private func begin() {
        round = ClockRound()
        feedback = []
        start = .now
        end = start.addingTimeInterval(ClockRound.duration)
        phase = .playing
    }

    private func check() async {
        guard phase == .playing else { return }
        let verdict = await session.evaluate()
        // checked in time: it counts even if the clock runs out while the meaning is read
        let meaningBonus = UserDefaults.standard.object(forKey: ClockSetupView.meaningBonusKey) as? Bool ?? true
        let meaning = meaningBonus || Options.swearBonus ? await session.meaning(of: verdict, phrase: true) : nil
        let outcomes = round.score(verdict, source: session.source, meaning: meaning,
                                   meaningBonus: meaningBonus, swearBonus: Options.swearBonus)
        guard phase == .playing else { return }
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
        made = nil
        phase = .setup
    }
}

private struct FeedbackChip: View {
    let outcome: ClockRound.Outcome

    /// "silent", "🤬 shit ×2", "★ anagram", "★ anagram ✦ makes sense", "★ anagram 🤬 ×3".
    static func label(_ found: ClockRound.Found) -> String {
        guard found.isFullAnagram else {
            if found.isSwear { return "🤬 \(found.text.lowercased()) ×2" }
            return found.meaning != nil ? "✦ \(found.text.lowercased()) ×2" : found.text.lowercased()
        }
        if found.isSwear { return "★ anagram 🤬 rude ×3" }
        return found.meaning != nil ? "★ anagram ✦ makes sense" : "★ anagram"
    }

    var body: some View {
        let (text, color): (String, Color) = switch outcome {
        case .scored(let found):
            ("+\(found.points) \(Self.label(found)) · \(languageNames(found.languages))", .green)
        case .alreadyFound(let word): ("\(word.lowercased()): already found", .orange)
        case .notAWord(let word): ("\(word.lowercased()): not a word", .red)
        case .notAllowed(let word): ("\(word.lowercased()): no single letters or acronyms", .red)
        case .fromSentence(let word): ("\(word.lowercased()): from the sentence", .orange)
        case .mixedLanguages: ("words must share one language", .orange)
        }
        Text(text)
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
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
                                if found.isSwear {
                                    Text("🤬").accessibilityLabel(found.isFullAnagram ? "rude, triple" : "swear word, double")
                                } else if found.meaning != nil {
                                    Image(systemName: "sparkles").foregroundStyle(.orange)
                                        .accessibilityLabel("makes sense")
                                }
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

/// Before the clock starts: how hard, where the sentence comes from, which language.
struct ClockSetupView: View {
    static let meaningBonusKey = "clock.meaningBonus"
    let start: (MadeSentence) -> Void
    @Environment(GameSession.self) private var session
    @AppStorage(meaningBonusKey) private var meaningBonus = true
    @AppStorage(Options.swearBonusKey) private var swearBonus = false

    @AppStorage("clock.level") private var level = SentenceBank.Level.medium.rawValue
    @AppStorage(Options.sentenceSourceKey) private var source = SentenceSource.classic.rawValue
    @AppStorage(Options.sentenceLanguageKey) private var language = ""
    @State private var isMaking = false
    @State private var note: String?

    var body: some View {
        ThemedScreen {
            ScrollView {
                VStack(spacing: 22) {
                    HStack(spacing: 4) {
                        ForEach(Array("90SEC").indices, id: \.self) { CreamTile(letter: Array("90SEC")[$0], size: 48) }
                    }
                    .padding(.top, 12)
                    Text("The app gives you a sentence. Make as many words as you can before the time is up.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    SentenceChoice(level: $level, source: $source, language: $language)
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $meaningBonus) {
                            Text("Meaning bonus").font(.headline).foregroundStyle(.white)
                        }
                        .tint(Theme.glow)
                        .disabled(!session.canCheckMeaning)
                        Text(session.canCheckMeaning
                             ? "Words you check together that mean something score double each; a full anagram that does, double again."
                             : "Needs Apple Intelligence, which isn't available on this iPhone.")
                            .font(.footnote).foregroundStyle(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                        if FeatureFlags.swearing {
                            Divider().overlay(.white.opacity(0.15)).padding(.vertical, 6)
                            Toggle(isOn: $swearBonus) {
                                Text("Swear words bonus").font(.headline).foregroundStyle(.white)
                            }
                            .tint(Theme.glow)
                            Text(session.canCheckMeaning
                                 ? "Each swear word scores double; a full anagram that's a profanity as a whole, triple."
                                 : "Each swear word scores double.")
                                .font(.footnote).foregroundStyle(.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(18)
                    .background(Theme.navyDeep.opacity(0.9), in: .rect(cornerRadius: 22, style: .continuous))
                    if let note {
                        Text(note).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                    }
                    Button {
                        Task { await go() }
                    } label: {
                        if isMaking {
                            Label(source == SentenceSource.news.rawValue ? "Reading the news…" : "Making a sentence…",
                                  systemImage: "hourglass")
                        } else {
                            Label("Start", systemImage: "timer")
                        }
                    }
                    .buttonStyle(Raised3DButtonStyle())
                    .disabled(isMaking)
                }
                .padding(24)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func go() async {
        isMaking = true
        defer { isMaking = false }
        note = nil
        let chosen = SentenceBank.Level(rawValue: level) ?? .medium
        guard let sentence = await SentenceMaker.make(chosen, source: SentenceSource(rawValue: source) ?? .classic,
                                                      language: language.isEmpty ? nil : language) else {
            note = "No sentence for that choice. Try another language."
            return
        }
        if sentence.isFallback {
            note = "Couldn't read the news, so here's one of the app's sentences."
            try? await Task.sleep(for: .seconds(1.5))
        }
        start(sentence)
    }
}

/// Level, source and language of the sentence the app makes, on a dark card.
struct SentenceChoice: View {
    @Binding var level: String
    @Binding var source: String
    @Binding var language: String
    /// false: inside a card already.
    var onCard = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Difficulty").font(.headline).foregroundStyle(.white)
                Picker("Difficulty", selection: $level) {
                    ForEach(SentenceBank.Level.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Text((SentenceBank.Level(rawValue: level) ?? .medium).detail)
                    .font(.footnote).foregroundStyle(.white.opacity(0.7))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Sentence from").font(.headline).foregroundStyle(.white)
                Picker("Sentence from", selection: $source) {
                    ForEach(SentenceSource.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Text((SentenceSource(rawValue: source) ?? .classic).detail)
                    .font(.footnote).foregroundStyle(.white.opacity(0.7))
            }
            HStack {
                Text("Language").font(.headline).foregroundStyle(.white)
                Spacer()
                Picker("Language", selection: $language) {
                    Text("Any language").tag("")
                    ForEach(SentenceBank.languages, id: \.self) { code in
                        Text(languageName(code) ?? code).tag(code)
                    }
                }
                .tint(Theme.glowLight)
            }
        }
        .padding(onCard ? 18 : 0)
        .background(onCard ? Theme.navyDeep.opacity(0.9) : .clear, in: .rect(cornerRadius: 22, style: .continuous))
    }
}
