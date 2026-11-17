import SwiftUI
import AnagramEngine

/// One online game, on this player's phone. On your turn you solve the sentence you got (the
/// clock starts when you open it, and keeps running if you leave), then send one back: written
/// by you, or by the app if those are the rules. Otherwise you see the score and what happened.
struct OnlineMatchView: View {
    let link: MatchLink

    private struct Outcome: Equatable {
        var solved: Bool
        var points: Int
        var answer: [AnagramVerdict.CheckedWord]
        var bonus: String?
        var reading: String?
    }

    private enum Phase: Equatable {
        case loading
        case failed(String)
        /// The other player's turn, or no opponent yet.
        case waiting
        /// A sentence to solve, not opened yet.
        case ready
        case solving
        case result(Outcome)
        /// Writing the sentence to send.
        case writing
        /// The app is making the sentence to send.
        case making(failed: Bool)
        case sending
        case over
    }

    @State private var session = GameSession()
    @State private var phase = Phase.loading
    @State private var snapshot: MatchSnapshot?
    @State private var game: OnlineDuel?
    @State private var start = Date.now
    @State private var end: Date?
    @State private var solutions: [Suggestion]?
    @State private var confirmsResign = false
    @State private var sendError: String?
    private var center: GameCenter { .shared }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ThemedScreen { ProgressView().controlSize(.large).tint(.white) }
            case let .failed(message):
                failed(message)
            case .waiting:
                waiting
            case .ready:
                ready
            case .solving:
                BoardView(header: AnyView(header),
                          leading: BoardAction(title: "Give up", symbol: "flag.fill") { finish(solved: false) },
                          onCheck: check,
                          allowsSuggestions: false)
            case let .result(outcome):
                result(outcome)
            case .writing:
                SentenceView(prompt: "Write a sentence for \(opponent).",
                             givesSentences: true, maxLetters: game?.settings.maxLetters, requiresCorrectSentence: true)
            case let .making(failed):
                making(failed: failed)
            case .sending:
                busy("Sending it to \(opponent)…")
            case .over:
                over
            }
        }
        .environment(session)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if snapshot?.isOpen == true && phase != .over {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Game", systemImage: "ellipsis.circle") {
                        Button("Resign", systemImage: "flag", role: .destructive) { confirmsResign = true }
                    }
                }
            }
        }
        .confirmationDialog("Resign this game? \(opponent) wins.", isPresented: $confirmsResign, titleVisibility: .visible) {
            Button("Resign", role: .destructive) { Task { await resign() } }
        }
        .alert("Couldn't reach Game Center", isPresented: Binding { sendError != nil } set: { if !$0 { sendError = nil } }) {
            Button("Try again") { Task { await retrySend() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(sendError ?? "")
        }
        .onChange(of: session.stage) { _, stage in
            if stage == .building && phase == .writing {
                let text = session.source.text
                let language = session.source.languageCodes.first ?? ""
                Task { await send(.init(text: text, language: language)) }
            }
        }
        .task { await load() }
        .onChange(of: center.changes[link.id]) {
            // the other player moved: reload unless this phone is mid-turn
            if [.waiting, .loading].contains(phase) || phase == .over { Task { await load() } }
        }
        .task(id: end) {
            guard let end else { return }
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            if !Task.isCancelled && phase == .solving { finish(solved: false) }
        }
        .onDisappear { session.restart() }
    }

    private var me: Int { snapshot?.me ?? 0 }
    private var opponent: String {
        guard let snapshot else { return "your opponent" }
        return snapshot.isMatching ? "your opponent" : snapshot.opponent
    }

    private var title: String {
        guard let game else { return "Online" }
        return "Round \(game.round) of \(game.settings.rounds)"
    }

    // MARK: flow

    private func load() async {
        if snapshot == nil { phase = .loading }
        do {
            let snapshot = try await link.load()
            self.snapshot = snapshot
            var game = snapshot.game
            if game == nil, snapshot.isMyTurn {
                // a new game: the rules its creator chose
                game = center.newGame ?? OnlineDuel(settings: Duel.Settings())
                center.newGame = nil
                if let game { try? await link.save(game) }
            }
            self.game = game
            decide()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// What this phone shows for the game as it stands.
    private func decide() {
        guard let snapshot, let game else {
            phase = .waiting
            return
        }
        session.sameLanguageRule = game.settings.sameLanguage
        if !snapshot.isOpen || game.isOver {
            phase = .over
        } else if snapshot.opponentQuit {
            Task {
                try? await link.end(game)
                self.snapshot?.isOpen = false
                phase = .over
            }
        } else if !snapshot.isMyTurn {
            phase = .waiting
        } else if let sentence = game.waiting {
            session.restart()
            session.startOver(with: sentence.text, language: sentence.language.isEmpty ? nil : sentence.language)
            session.makeAnagram()
            if let deadline = game.deadline {
                // opened before: the clock kept running
                if deadline > .now {
                    start = game.solveStarted ?? .now
                    end = deadline
                    phase = .solving
                } else {
                    finish(solved: false)
                }
            } else {
                phase = .ready
            }
        } else {
            sendNext()
        }
    }

    /// The player sends the next sentence: they write it, or the app makes it.
    private func sendNext() {
        session.restart()
        if game?.appSentences != nil {
            Task { await makeSentence() }
        } else {
            phase = .writing
        }
    }

    private func makeSentence() async {
        guard let choice = game?.appSentences, let game else { return }
        phase = .making(failed: false)
        guard let made = await SentenceMaker.make(SentenceBank.Level(rawValue: choice.level) ?? .medium,
                                                  source: SentenceSource(rawValue: choice.source) ?? .classic,
                                                  language: choice.language, maxLetters: game.settings.maxLetters) else {
            phase = .making(failed: true)
            return
        }
        let credit = made.headline.map { "From the news: “\($0)”" } ?? made.quote.map { "From \($0.credit)" }
        await send(.init(text: made.text, language: made.language, credit: credit))
    }

    @State private var unsent: OnlineDuel?

    private func send(_ sentence: OnlineDuel.Sentence) async {
        guard var game else { return }
        game.send(sentence)
        self.game = game
        phase = .sending
        unsent = game
        await retrySend()
    }

    private func retrySend() async {
        guard let unsent else { return }
        do {
            try await link.pass(unsent, message: "A new sentence to anagram!")
            self.unsent = nil
            await load()
            await center.refresh()
        } catch {
            sendError = error.localizedDescription
        }
    }

    private func startSolving() {
        guard var game else { return }
        game.startSolving()
        self.game = game
        start = game.solveStarted ?? .now
        end = game.deadline
        phase = .solving
        Task { try? await link.save(game) }  // the clock runs from now, even if the app closes
    }

    private func check() async {
        let secondsLeft = end?.timeIntervalSinceNow ?? 0
        let verdict = await session.evaluate()
        guard phase == .solving, let settings = game?.settings else { return }
        guard verdict.isValid else {
            session.verdict = verdict
            return
        }
        end = nil
        let meaning = settings.meaningBonus || settings.swearBonus ? await session.meaning(of: verdict) : nil
        guard phase == .solving else { return }
        let hasSwear = FeatureFlags.swearing && verdict.words.contains { Profanity.isSwear($0.text, language: $0.language) }
        let makesSense = meaning?.makesSense == true
        let isProfane = FeatureFlags.swearing && meaning?.isProfane == true
        let points = settings.points(letters: session.letterCount, secondsLeft: secondsLeft, makesSense: makesSense,
                                     hasSwear: hasSwear, isProfane: isProfane)
        finish(solved: true, outcome: Outcome(
            solved: true, points: points, answer: verdict.words,
            bonus: settings.bonus(makesSense: makesSense, hasSwear: hasSwear, isProfane: isProfane),
            reading: settings.meaningBonus || isProfane ? meaning?.reading : nil))
    }

    private func finish(solved: Bool, outcome: Outcome? = nil) {
        guard var game else { return }
        let outcome = outcome ?? Outcome(solved: false, points: 0, answer: [])
        end = nil
        session.verdict = nil
        game.finishSolving(solved: solved, answer: outcome.answer.map { .init(text: $0.text, language: $0.language) },
                           points: outcome.points, bonus: outcome.bonus, reading: outcome.reading)
        self.game = game
        findSolutions(besides: outcome.answer)
        withAnimation { phase = .result(outcome) }
        Task {
            do {
                if game.isOver {
                    try await link.end(game)
                    await center.refresh()
                } else {
                    try await link.save(game)
                }
            } catch {
                sendError = error.localizedDescription
            }
        }
    }

    private func findSolutions(besides answer: [AnagramVerdict.CheckedWord]) {
        solutions = nil
        func words(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .split(whereSeparator: { !$0.isLetter }).joined(separator: " ")
        }
        let given = words(answer.map(\.text).joined(separator: " "))
        Task {
            let found = await session.suggestions()
            withAnimation { solutions = Array(found.filter { words($0.text) != given }.prefix(5)) }
        }
    }

    private func resign() async {
        do {
            try await link.resign(game)
            await load()
            await center.refresh()
            phase = .over
        } catch {
            sendError = error.localizedDescription
        }
    }

    // MARK: screens

    private var header: some View {
        VStack(spacing: 10) {
            if let end {
                Countdown(start: start, end: end)
            } else if session.isCheckingMeaning {
                Label { Text("Solved! Checking the meaning…") } icon: { ProgressView() }
                    .font(.headline)
            }
            HStack(alignment: .top, spacing: 14) {
                ForEach(0..<OnlineDuel.playerCount, id: \.self) { i in
                    ScoreLabel(name: name(i), points: game?.scores[i] ?? 0)
                        .opacity(i == me ? 1 : 0.6)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
    }

    private func name(_ player: Int) -> String {
        player == me ? "You" : opponent.capitalizedFirst
    }

    private var waiting: some View {
        ThemedScreen {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: snapshot?.isMatching == true ? "person.fill.questionmark" : "hourglass")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.glowLight)
                    Text(snapshot?.isMatching == true ? "Finding an opponent" : "\(opponent.capitalizedFirst)'s turn")
                        .font(.largeTitle.weight(.heavy))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Text(snapshot?.isMatching == true
                         ? "Game Center is looking for someone to play. You'll get a notification when it's your turn."
                         : "You'll get a notification when it's your turn.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.85))
                    if let game {
                        RulesSummary(settings: game.settings, sentences: appSentences)
                        scoreboard
                        history
                    }
                }
                .padding(24)
            }
            .refreshable { await load() }
        }
    }

    private var ready: some View {
        ThemedScreen {
            ScrollView {
                VStack(spacing: 22) {
                    if let solve = game?.lastSolve(by: 1 - me) {
                        SolveCard(solve: solve, solver: opponent.capitalizedFirst, isMine: false)
                    }
                    Image(systemName: "envelope.open.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.glowLight)
                    Text(game?.appSentences == nil ? "\(opponent.capitalizedFirst) sent you a sentence"
                                                   : "A new sentence for you")
                        .font(.largeTitle.weight(.heavy))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    if let game {
                        Text("\(session.letterCount) letters, \(duration(game.settings.solveTime)) to make an anagram. The clock starts when you're ready, and keeps running if you leave.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.85))
                        RulesSummary(settings: game.settings, sentences: appSentences)
                    }
                    Button("I'm ready", action: startSolving)
                        .buttonStyle(CreamButtonStyle())
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func result(_ outcome: Outcome) -> some View {
        ThemedScreen {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: outcome.solved ? "checkmark.seal.fill" : "hourglass")
                        .font(.system(size: 56))
                        .foregroundStyle(outcome.solved ? .green : Theme.glowLight)
                    Text(outcome.solved ? "You did it! +\(outcome.points)" : "No anagram this time")
                        .font(.title.weight(.heavy))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    if let solve = game?.solves.last {
                        SolveCard(solve: solve, solver: "You", isMine: true)
                    }
                    PossibleAnagrams(solutions: solutions, solved: outcome.solved)
                    scoreboard
                    if game?.isOver == true {
                        Button("See who won") { withAnimation { phase = .over } }
                            .buttonStyle(CreamButtonStyle())
                    } else {
                        Button(game?.appSentences == nil ? "Write a sentence for \(opponent)"
                                                         : "Send \(opponent) a sentence", action: sendNext)
                            .buttonStyle(CreamButtonStyle())
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func making(failed: Bool) -> some View {
        ThemedScreen {
            VStack(spacing: 24) {
                if failed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.orange)
                    Text("No sentence for that choice")
                        .font(.title.weight(.heavy))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Button("Try again") { Task { await makeSentence() } }
                        .buttonStyle(CreamButtonStyle())
                } else {
                    ProgressView().controlSize(.large).tint(.white)
                    Text(game?.appSentences?.source == SentenceSource.news.rawValue
                         ? "Reading the news for \(opponent)…" : "Making a sentence for \(opponent)…")
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                }
            }
            .padding(32)
        }
    }

    private func busy(_ text: String) -> some View {
        ThemedScreen {
            VStack(spacing: 24) {
                ProgressView().controlSize(.large).tint(.white)
                Text(text)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
            }
            .padding(32)
        }
    }

    private var over: some View {
        ThemedScreen {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.yellow)
                        .symbolEffect(.bounce, options: .repeat(2))
                    Text(verdict)
                        .font(.largeTitle.weight(.heavy))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    scoreboard
                    history
                }
                .padding(24)
            }
        }
    }

    private var verdict: String {
        guard let game else { return "Game over" }
        if snapshot?.opponentQuit == true { return "\(opponent.capitalizedFirst) left: you win!" }
        if !game.isOver { return "Game over" }
        return switch game.winner {
        case me: "You win!"
        case nil: "It's a draw!"
        default: "\(opponent.capitalizedFirst) wins!"
        }
    }

    private var scoreboard: some View {
        HStack(spacing: 32) {
            ForEach(0..<OnlineDuel.playerCount, id: \.self) { i in
                VStack {
                    Text(name(i)).font(.headline).foregroundStyle(Theme.glowLight).lineLimit(1)
                    Text("\(game?.scores[i] ?? 0)").font(.system(size: 44, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
        }
        .padding()
        .background(Theme.navyDeep.opacity(0.9), in: .rect(cornerRadius: 18, style: .continuous))
    }

    /// Every sentence so far, the latest first.
    @ViewBuilder private var history: some View {
        if let game, !game.solves.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("SO FAR")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.glowLight)
                ForEach(Array(game.solves.enumerated().reversed()), id: \.offset) { _, solve in
                    SolveCard(solve: solve, solver: name(solve.solver), isMine: solve.solver == me, plain: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.navyDeep.opacity(0.9), in: .rect(cornerRadius: 18, style: .continuous))
        }
    }

    private var appSentences: AppSentences? {
        guard let choice = game?.appSentences else { return nil }
        return AppSentences(level: SentenceBank.Level(rawValue: choice.level) ?? .medium,
                            source: SentenceSource(rawValue: choice.source) ?? .classic, language: choice.language)
    }

    private func failed(_ message: String) -> some View {
        ThemedScreen {
            VStack(spacing: 20) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
                Text("Couldn't load the game")
                    .font(.title.weight(.heavy))
                    .foregroundStyle(.white)
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.8))
                Button("Try again") { Task { await load() } }
                    .buttonStyle(CreamButtonStyle())
            }
            .padding(32)
        }
    }
}

/// A sentence and what its solver made of it.
private struct SolveCard: View {
    let solve: OnlineDuel.Solve
    let solver: String
    let isMine: Bool
    var plain = false

    var body: some View {
        VStack(alignment: plain ? .leading : .center, spacing: 6) {
            Text(headline)
                .font(plain ? .subheadline.weight(.semibold) : .headline)
                .foregroundStyle(solve.solved ? Theme.glowLight : .white.opacity(0.7))
            Text(solve.sentence.text.lowercased()).font(.headline).foregroundStyle(Theme.cream)
            if let credit = solve.sentence.credit, !plain {
                Text(credit)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
            }
            if solve.solved {
                Image(systemName: "arrow.down").foregroundStyle(Theme.cream)
                ForEach(Array(solve.answer.enumerated()), id: \.offset) { _, word in
                    HStack(spacing: 8) {
                        Text(word.text.lowercased()).font(.headline).foregroundStyle(Theme.cream)
                        Text(languageName(word.language) ?? "").font(.subheadline).foregroundStyle(Theme.glowLight)
                    }
                }
                if let bonus = solve.bonus, !plain {
                    Label(bonus, systemImage: "sparkles").font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                }
                if let reading = solve.reading, !plain {
                    Text(reading)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: plain ? .leading : .center)
        .padding(plain ? 0 : 16)
        .background(plain ? .clear : Theme.navyDeep.opacity(0.9), in: .rect(cornerRadius: 18, style: .continuous))
    }

    private var headline: String {
        let subject = isMine ? "You" : solver
        return solve.solved ? "\(subject) made an anagram: +\(solve.points)"
                            : "\(subject) couldn't make an anagram"
    }
}

private extension String {
    /// "your opponent" → "Your opponent"; names stay as they are.
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
