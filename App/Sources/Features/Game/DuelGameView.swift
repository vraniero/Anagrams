import SwiftUI
import AnagramEngine

/// The sentences the app writes in a Multiplayer game, when chosen before it starts (otherwise
/// the players write them for each other).
struct AppSentences: Equatable {
    var level: SentenceBank.Level
    var source: SentenceSource
    var language: String?
}

/// Two to four players, one phone. The rules (time, rounds, languages, scoring, and who writes
/// the sentences) are chosen before the game and stay fixed. In turn, one player writes a
/// sentence (typed, read with the camera, or given by the app) and passes the phone; the next
/// one has the chosen time to make a full anagram. Or the app writes every sentence, each
/// one new, and the players just take turns solving.
struct DuelGameView: View {
    private enum Phase: Equatable {
        case setup, setting, making, handoff, solving
        case result(points: Int, solved: Bool, answer: [AnagramVerdict.CheckedWord], meaning: Meaning?, bonus: String?)
        case over
    }

    @State private var session = GameSession()
    @State private var phase = Phase.setup
    @State private var duel = Duel(players: ["Player 1", "Player 2"])
    @State private var sentence = ""
    @State private var sentences: AppSentences?
    @State private var made: MadeSentence?
    @State private var makingFailed = false
    /// Anagrams that were possible this turn; nil while looking.
    @State private var solutions: [Suggestion]?
    @State private var turnID = UUID()
    @State private var start = Date.now
    @State private var end: Date?

    var body: some View {
        Group {
            switch phase {
            case .setup:
                DuelSetupView(start: begin)
            case .setting:
                SentenceView(prompt: "\(setter): write a sentence for \(solver).",
                              givesSentences: true, maxLetters: duel.settings.maxLetters, requiresCorrectSentence: true)
            case .making:
                making
            case .handoff:
                handoff
            case .solving:
                BoardView(header: AnyView(header),
                          leading: BoardAction(title: "Give up", symbol: "flag.fill") { endTurn(solved: false) },
                          onCheck: check,
                          allowsSuggestions: false)
            case let .result(points, solved, answer, meaning, bonus):
                result(points: points, solved: solved, answer: answer, meaning: meaning, bonus: bonus)
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
                if made?.isFallback == true {
                    Text("Couldn't read the news, so here's one of the app's sentences.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.orange)
                }
                RulesSummary(settings: duel.settings, sentences: sentences)
                Button("I'm ready", action: startSolving)
                    .buttonStyle(CreamButtonStyle())
            }
            .padding(32)
        }
    }

    /// The app is writing the next sentence.
    private var making: some View {
        ThemedScreen {
            VStack(spacing: 24) {
                if makingFailed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.orange)
                    Text("No sentence for that choice")
                        .font(.title.weight(.heavy))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Button("Try again") { Task { await makeSentence() } }
                        .buttonStyle(CreamButtonStyle())
                    Button("Change the rules") { withAnimation { phase = .setup } }
                        .foregroundStyle(Theme.glowLight)
                } else {
                    ProgressView().controlSize(.large).tint(.white)
                    Text(sentences?.source == .news ? "Reading the news for \(solver)…"
                                                          : "Making a sentence for \(solver)…")
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                }
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

    private func result(points: Int, solved: Bool, answer: [AnagramVerdict.CheckedWord], meaning: Meaning?,
                        bonus: String?) -> some View {
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
                        if let headline = made?.headline {
                            Text("From the news: “\(headline)”")
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.7))
                        } else if let quote = made?.quote {
                            Text("From \(quote.credit): “\(quote.text)”")
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.7))
                        }
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
                    if solved, bonus != nil || meaning != nil {
                        VStack(spacing: 4) {
                            Label(bonus ?? "No bonus", systemImage: bonus == nil ? "text.word.spacing" : "sparkles")
                                .font(.headline)
                                .foregroundStyle(bonus == nil ? Theme.glowLight : Color.orange)
                            if let meaning {
                                Text(meaning.reading)
                                    .font(.subheadline)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                    }
                    PossibleAnagrams(solutions: solutions, solved: solved)
                    scoreboard
                    Button(duel.isOver ? "See who won"
                           : sentences == nil ? "Next: \(setter) writes a sentence" : "Next: \(solver)'s turn",
                           action: next)
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

    private func begin(_ players: [String], _ settings: Duel.Settings, _ sentences: AppSentences?) {
        duel = Duel(players: players, settings: settings)
        self.sentences = sentences
        session.restart()
        session.sameLanguageRule = settings.sameLanguage
        nextSentence()
    }

    /// Same players, same rules.
    private func playAgain() {
        begin(duel.players, duel.settings, sentences)
    }

    /// The setter writes it, or the app makes it.
    private func nextSentence() {
        made = nil
        if sentences == nil {
            phase = .setting
        } else {
            Task { await makeSentence() }
        }
    }

    /// A sentence from the app, never given before, within the game's letter limit.
    private func makeSentence() async {
        guard let choice = sentences else { return }
        makingFailed = false
        phase = .making
        guard let new = await SentenceMaker.make(choice.level, source: choice.source, language: choice.language,
                                                 maxLetters: duel.settings.maxLetters) else {
            makingFailed = true
            return
        }
        guard phase == .making else { return }
        made = new
        session.restart()
        session.startOver(with: new.text, language: new.language)
        sentence = session.source.text
        session.makeAnagram()
        phase = .handoff
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
        let settings = duel.settings
        let meaning = settings.meaningBonus || settings.swearBonus ? await session.meaning(of: verdict) : nil
        guard phase == .solving else { return }
        let hasSwear = FeatureFlags.swearing && verdict.words.contains { Profanity.isSwear($0.text, language: $0.language) }
        endTurn(solved: true, answer: verdict.words, secondsLeft: secondsLeft, meaning: meaning, hasSwear: hasSwear)
    }

    private func endTurn(solved: Bool, answer: [AnagramVerdict.CheckedWord] = [], secondsLeft: TimeInterval? = nil,
                         meaning: Meaning? = nil, hasSwear: Bool = false) {
        let secondsLeft = secondsLeft ?? end?.timeIntervalSinceNow ?? 0
        end = nil
        session.verdict = nil
        let settings = duel.settings
        let makesSense = meaning?.makesSense == true
        let isProfane = FeatureFlags.swearing && meaning?.isProfane == true
        let points = duel.finishTurn(solved: solved, letters: letters, secondsLeft: secondsLeft,
                                     makesSense: makesSense, hasSwear: hasSwear, isProfane: isProfane)
        let bonus = settings.bonus(makesSense: makesSense, hasSwear: hasSwear, isProfane: isProfane)
        findSolutions(besides: answer)
        withAnimation {
            phase = .result(points: points, solved: solved, answer: answer,
                            meaning: settings.meaningBonus || isProfane ? meaning : nil, bonus: solved ? bonus : nil)
        }
    }

    /// What else the sentence could have become (the player's own answer left out).
    private func findSolutions(besides answer: [AnagramVerdict.CheckedWord]) {
        let id = UUID()
        turnID = id
        solutions = nil
        func words(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .split(whereSeparator: { !$0.isLetter }).joined(separator: " ")
        }
        let given = words(answer.map(\.text).joined(separator: " "))
        Task {
            let found = await session.suggestions()
            guard turnID == id else { return }
            withAnimation { solutions = Array(found.filter { words($0.text) != given }.prefix(5)) }
        }
    }

    private func next() {
        if duel.isOver {
            withAnimation { phase = .over }
        } else {
            session.restart()
            nextSentence()
        }
    }
}

/// The anagrams the sentence allowed, shown after each turn.
struct PossibleAnagrams: View {
    let solutions: [Suggestion]?
    let solved: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text((solved ? "Other possible anagrams" : "Possible anagrams").uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.glowLight)
            if let solutions, solutions.isEmpty {
                Text(solved ? "None found: well done!" : "None found: a tough one.")
                    .foregroundStyle(.white.opacity(0.8))
            } else if let solutions {
                ForEach(solutions) { solution in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(solution.text.lowercased())
                            .font(.headline)
                            .foregroundStyle(Theme.cream)
                        Text(Array(Set(solution.languages)).sorted().map { languageName($0) ?? $0 }
                            .joined(separator: ", "))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            } else {
                Label { Text("Looking for anagrams…") } icon: { ProgressView().tint(.white) }
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.navyDeep.opacity(0.9), in: .rect(cornerRadius: 18, style: .continuous))
    }
}

extension Duel.Settings {
    /// The biggest bonus is the one that counts.
    func bonus(makesSense: Bool, hasSwear: Bool, isProfane: Bool) -> String? {
        if swearBonus && isProfane { "A proper profanity: triple points! 🤬" }
        else if swearBonus && hasSwear { "A swear word: double points! 🤬" }
        else if meaningBonus && makesSense { "It makes sense: double points!" }
        else { nil }
    }
}

/// "1 minute", "2 minutes", "90 seconds".
func duration(_ seconds: TimeInterval) -> String {
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
struct RulesSummary: View {
    let settings: Duel.Settings
    let sentences: AppSentences?

    var body: some View {
        FlowLayout(spacing: 8) {
            if let made = sentences {
                chip(made.source == .news ? "News sentences" : made.source == .literature ? "Literature" : "App sentences", "dice")
            }
            chip(settings.sameLanguage ? "One language" : "Any languages", "character.book.closed")
            chip(settings.scoring.title, "star")
            chip("\(settings.rounds) \(settings.rounds == 1 ? "round" : "rounds")", "repeat")
            chip("≤ \(settings.maxLetters) letters", "textformat.size")
            if settings.meaningBonus { chip("Meaning ×2", "sparkles") }
            if settings.swearBonus && FeatureFlags.swearing { chip("Swearing ×2 ×3", "exclamationmark.bubble") }
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

/// Players and rules, decided before the game starts (and remembered for next time). Online,
/// there are no names to write: the game starts with a friend or someone new.
struct DuelSetupView: View {
    var start: ([String], Duel.Settings, AppSentences?) -> Void = { _, _, _ in }
    /// For an online game: the rules, and whether to invite a friend.
    var startOnline: ((Duel.Settings, AppSentences?, _ friend: Bool) -> Void)? = nil

    @AppStorage("duel.players") private var savedNames = ""
    @AppStorage("duel.time") private var time = 120.0
    @AppStorage("duel.rounds") private var rounds = 3
    @AppStorage("duel.sameLanguage") private var sameLanguage = false
    @AppStorage("duel.scoring") private var scoring = Duel.Settings.Scoring.lettersAndTime.rawValue
    @AppStorage("duel.meaningBonus") private var meaningBonus = true
    @AppStorage("duel.swearBonus") private var swearBonus = false
    @AppStorage("duel.maxLetters") private var maxLetters = 20
    @AppStorage("duel.sentencesBy") private var sentencesBy = "players"
    @AppStorage("duel.level") private var level = SentenceBank.Level.medium.rawValue
    @AppStorage("duel.source") private var source = SentenceSource.classic.rawValue
    @AppStorage("duel.language") private var language = ""
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
                    if !isOnline {
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
                    }

                    section("Sentences") {
                        Picker("Sentences written by", selection: $sentencesBy) {
                            Text("The players").tag("players")
                            Text("The app").tag("app")
                        }
                        .pickerStyle(.segmented)
                        Text(byApp ? "The app gives every sentence, a new one each time. Players just solve."
                                   : "In turn, each player writes a sentence for the next, or asks the app for one.")
                            .font(.footnote).foregroundStyle(.white.opacity(0.7))
                        if byApp {
                            SentenceChoice(level: $level, source: $source, language: $language, onCard: false)
                                .padding(.top, 4)
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
                            Text(byApp ? "Each round, everyone solves one sentence."
                                       : "Each round, everyone writes one sentence for the next player.")
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
                        if FeatureFlags.swearing {
                            rule("Swear words bonus") {
                                Toggle(isOn: $swearBonus) {
                                    Text("Rude anagrams score more")
                                        .foregroundStyle(.white)
                                }
                                .tint(Theme.glow)
                                Text(session.canCheckMeaning
                                     ? "An anagram with a swear word scores double; one that's a profanity as a whole, triple."
                                     : "An anagram with a swear word scores double.")
                                    .font(.footnote).foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }

                    Text(footer)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    if let startOnline {
                        Button("Invite a friend") { startOnline(settings, appSentences, true) }
                            .buttonStyle(CreamButtonStyle())
                            .padding(.top, 4)
                        Button("Play someone new") { startOnline(settings, appSentences, false) }
                            .font(.headline)
                            .foregroundStyle(Theme.glowLight)
                    } else {
                        Button("Start", action: go)
                            .buttonStyle(CreamButtonStyle())
                            .padding(.top, 4)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .environment(\.colorScheme, .dark)
        .onAppear(perform: load)
    }

    private var byApp: Bool { sentencesBy == "app" }
    private var isOnline: Bool { startOnline != nil }

    private var footer: String {
        switch (isOnline, byApp) {
        case (true, true): "Two players, each on their own iPhone. In turn, you solve the app's sentence for you, whenever you like. No suggestions in a game."
        case (true, false): "Two players, each on their own iPhone. In turn, you solve the sentence you got, then write one back, whenever you like. No suggestions in a game."
        case (false, true): "In turn, each player gets the phone and makes an anagram of the app's sentence. No suggestions in a game."
        case (false, false): "In turn, each player writes a sentence and passes the phone to the next, who makes the anagram. No suggestions in a game."
        }
    }

    private var settings: Duel.Settings {
        Duel.Settings(solveTime: time, rounds: rounds, sameLanguage: sameLanguage, scoring: scoringChoice.wrappedValue,
                      meaningBonus: meaningBonus && session.canCheckMeaning, maxLetters: maxLetters, swearBonus: swearBonus && FeatureFlags.swearing)
    }

    private var appSentences: AppSentences? {
        byApp ? AppSentences(level: SentenceBank.Level(rawValue: level) ?? .medium,
                             source: SentenceSource(rawValue: source) ?? .classic,
                             language: language.isEmpty ? nil : language)
              : nil
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
        start(players, settings, appSentences)
    }
}
