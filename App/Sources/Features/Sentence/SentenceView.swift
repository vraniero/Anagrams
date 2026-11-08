import SwiftUI
import AnagramEngine

/// Where the sentence comes from: typed (its letters land as tiles), read with the camera,
/// or given by the app at a chosen difficulty. Nothing is ever recorded.
struct SentenceView: View {
    @Environment(GameSession.self) private var session
    /// What to do, shown on top (the game modes: whose turn it is).
    var prompt: String? = nil
    /// Training: the app can give a sentence too. Multiplayer: typed or read with the camera.
    var givesSentences = true
    /// Multiplayer: the longest sentence allowed, in letters. Typing stops there.
    var maxLetters: Int? = nil
    /// Multiplayer: the sentence must pass the spelling and grammar check to be set.
    var requiresCorrectSentence = false
    @State private var typed = ""
    @FocusState private var isTyping: Bool
    @State private var showsCamera = false
    @State private var lastGiven: String?
    @AppStorage(Options.sentenceLanguageKey) private var sentenceLanguage = ""
    @AppStorage(Options.sentenceSourceKey) private var sentenceSource = SentenceSource.classic.rawValue
    @State private var isMaking = false
    /// The news behind the sentence the app gave (newspapers), or why there's none.
    @State private var made: MadeSentence?

    var body: some View {
        ZStack {
            IconBackground()
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 18) {
                        if let prompt {
                            Text(prompt)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        composer
                        if let made, session.source.text.filter(\.isLetter) == made.text.filter(\.isLetter) {
                            Group {
                                if let headline = made.headline {
                                    Label("Inspired by: \(headline)", systemImage: "newspaper")
                                } else if made.isFallback {
                                    Label("Couldn't read the news, so here's one of the app's sentences.",
                                          systemImage: "wifi.exclamationmark")
                                }
                            }
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        }
                        if !session.source.words.isEmpty {
                            SentenceReviewNote(review: session.review,
                                               isChecking: session.isReviewing || session.review == nil,
                                               isRequired: requiresCorrectSentence) { replace(with: $0) }
                        }
                        sources
                        Button {
                            isTyping = false
                            session.makeAnagram()
                        } label: {
                            Label("Make anagram", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(Raised3DButtonStyle())
                        .disabled(session.source.words.isEmpty || isTooLong
                                  || (requiresCorrectSentence && session.review?.isCorrect != true))
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .environment(\.colorScheme, .dark)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            session.letterLimit = maxLetters
            typed = session.draft
        }
        // typing: every change goes straight into the sentence (and is clipped at the limit)
        .onChange(of: typed) { _, text in
            withAnimation(.spring(duration: 0.35)) { session.setDraft(text) }
            if session.draft != text { typed = session.draft }
        }
        .onChange(of: session.draft) { _, draft in
            if typed != draft { typed = draft }
        }
        .task(id: session.source.text) {
            // proofread once the sentence stops changing
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await session.reviewSentence()
        }
        .sheet(isPresented: $showsCamera) {
            TextScannerView { replace(with: $0) }
                .environment(\.colorScheme, .light)
        }
    }

    /// The sentence as tiles, in a big card: tap it to type, and the letters land as tiles.
    private var composer: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return VStack(spacing: 16) {
            Group {
                if session.source.words.isEmpty {
                    HStack(spacing: 10) {
                        Caret(isOn: isTyping)
                        Text("Tap here to type a sentence")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, minHeight: 90)
                } else {
                    PhraseBlocksView(phrase: session.source)
                        .frame(minHeight: 90)
                }
            }
            .allowsHitTesting(false)

            HStack(spacing: 12) {
                if let left = session.lettersLeft {
                    LettersLeft(left: left)
                }
                Text(session.source.languageCodes.compactMap(languageName).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .allowsHitTesting(false)
                Spacer(minLength: 0)
                if !session.source.words.isEmpty {
                    Button("Clear sentence", systemImage: "xmark.circle.fill") {
                        withAnimation { session.clearSentence() }
                    }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 200)
        // the real text field, invisible, under the tiles: tapping the card types
        .background {
            TextField("Sentence", text: $typed)
                .focused($isTyping)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { isTyping = false }
                .foregroundStyle(.clear)
                .tint(.clear)
                .opacity(0.02)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Sentence")
        }
        .background(Theme.navyDeep.opacity(0.88), in: shape)
        .overlay {
            shape.strokeBorder(Theme.glow.opacity(isTyping ? 0.9 : 0.35), lineWidth: isTyping ? 2 : 1)
                .allowsHitTesting(false)
        }
        .contentShape(shape)
        .onTapGesture { isTyping = true }  // anywhere on the card: type
        .shadow(color: Theme.glow.opacity(0.35), radius: isTyping ? 18 : 0)
        .animation(.easeInOut(duration: 0.25), value: isTyping)
        .padding(.horizontal)
    }

    /// A new sentence to edit (read by the camera, or the proofreader's fix): it's typed in.
    private func replace(with text: String) {
        withAnimation {
            session.clearSentence()
            typed = text
        }
    }

    /// The camera, or a sentence from the app.
    private var sources: some View {
        HStack(spacing: 12) {
            if TextScannerView.isAvailable {
                Button("Camera", systemImage: "text.viewfinder") {
                    isTyping = false
                    showsCamera = true
                }
            }
            if givesSentences { giveMenu }
        }
        .buttonStyle(.bordered)
        .tint(Theme.glowLight)
    }

    /// A sentence from the app, at a chosen difficulty.
    private var giveMenu: some View {
        Menu {
            Picker("Language", selection: $sentenceLanguage) {
                Text("Any language").tag("")
                ForEach(SentenceBank.languages, id: \.self) { code in
                    Text(languageName(code) ?? code).tag(code)
                }
            }
            .pickerStyle(.menu)
            Picker("Sentence from", selection: $sentenceSource) {
                ForEach(SentenceSource.allCases) { Label($0.title, systemImage: $0 == .news ? "newspaper" : "text.book.closed").tag($0.rawValue) }
            }
            .pickerStyle(.menu)
            Section("Difficulty") {
                ForEach(SentenceBank.Level.allCases) { level in
                    Button {
                        give(level)
                    } label: {
                        Text(level.title)
                        Text(level.detail)
                    }
                }
            }
        } label: {
            if isMaking {
                Label(sentenceSource == SentenceSource.news.rawValue ? "Reading the news…" : "Making…", systemImage: "hourglass")
            } else {
                Label("Give me a sentence", systemImage: "dice")
            }
        }
        .disabled(isMaking)
    }

    private var isTooLong: Bool {
        maxLetters.map { session.letterCount > $0 } ?? false
    }

    private func give(_ level: SentenceBank.Level) {
        isTyping = false
        isMaking = true
        Task {
            defer { isMaking = false }
            guard let sentence = await SentenceMaker.make(level, source: SentenceSource(rawValue: sentenceSource) ?? .classic,
                                                          language: sentenceLanguage.isEmpty ? nil : sentenceLanguage,
                                                          avoiding: lastGiven, maxLetters: maxLetters) else { return }
            lastGiven = sentence.text
            if maxLetters != nil {
                replace(with: sentence.text)  // typed in: editable, and within the limit
            } else {
                withAnimation { session.startOver(with: sentence.text, language: sentence.language) }
            }
            made = sentence
        }
    }
}

/// Letters still allowed, counting down as you type; at 0 nothing more goes in.
private struct LettersLeft: View {
    let left: Int

    var body: some View {
        Text(left == 0 ? "No letters left" : left == 1 ? "1 letter left" : "\(left) letters left")
            .font(.subheadline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(left == 0 ? Color.orange : left <= 3 ? Theme.cream : Theme.glowLight)
            .contentTransition(.numericText(value: Double(left)))
            .animation(.snappy, value: left)
            .sensoryFeedback(.warning, trigger: left) { old, new in new == 0 && old > 0 }
    }
}

/// A blinking text cursor, while typing.
private struct Caret: View {
    let isOn: Bool
    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Theme.glowLight)
            .frame(width: 3, height: 30)
            .opacity(isOn && visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever()) { visible = false }
            }
    }
}

/// The spelling and grammar check of the sentence: fine, or what to fix (with the fix to
/// take in one tap).
private struct SentenceReviewNote: View {
    let review: SentenceReview?
    let isChecking: Bool
    /// Multiplayer: say it has to be fixed.
    let isRequired: Bool
    let use: (String) -> Void

    var body: some View {
        VStack(spacing: 6) {
            if let review, !isChecking || review.isCorrect {
                if review.isCorrect {
                    Label("Spelling and grammar look right", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Label(isRequired ? "Fix the sentence before passing the phone" : "This sentence may have a mistake",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    if let suggestion = review.suggestion {
                        Text("Did you mean “\(suggestion)”?")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                        Button("Use it") { use(suggestion) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    } else if !review.unknownWords.isEmpty {
                        Text("Not in any dictionary: \(review.unknownWords.joined(separator: ", "))")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                    }
                }
            } else {
                Label { Text("Checking spelling and grammar…") } icon: { ProgressView().controlSize(.small) }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 10)
        .padding(.horizontal)
        .animation(.snappy, value: review)
    }
}
