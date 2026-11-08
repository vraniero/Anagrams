import SwiftUI
import AnagramEngine

/// Where the sentence comes from: said (live, as letter blocks), typed, read with the camera,
/// or given by the app at a chosen difficulty. "Make anagram" stops listening.
struct ListeningView: View {
    @Environment(GameSession.self) private var session
    /// What to do, shown on top (the game modes: whose turn it is).
    var prompt: String? = nil
    /// Training: the sentence can be said, and the app can give one. The games: typed or
    /// read with the camera only.
    var voice = true
    /// Multiplayer: the longest sentence allowed, in letters.
    var maxLetters: Int? = nil
    /// Multiplayer: the sentence must pass the spelling and grammar check to be set.
    var requiresCorrectSentence = false
    @State private var typed = ""
    @FocusState private var isTyping: Bool
    @State private var showsCamera = false
    @State private var lastGiven: String?
    @AppStorage(Options.sentenceLanguageKey) private var sentenceLanguage = ""

    var body: some View {
        VStack(spacing: 16) {
            if let prompt {
                Text(prompt)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            if voice {
                status
                    .frame(height: 72)
            }
            ScrollView {
                PhraseBlocksView(phrase: session.source, isWorking: session.isProcessing)
                    .padding(.horizontal)
                if !session.source.words.isEmpty {
                    HStack(spacing: 12) {
                        Text(session.source.languageCodes.compactMap(languageName).joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Clear sentence", systemImage: "xmark.circle.fill") {
                            withAnimation { session.clearSentence() }
                        }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
                if !session.source.words.isEmpty {
                    SentenceReviewNote(review: session.review, isChecking: session.isReviewing || session.review == nil,
                                       isRequired: requiresCorrectSentence) { suggestion in
                        withAnimation { session.startOver(with: suggestion, language: session.source.languageCodes.first) }
                    }
                }
                if let maxLetters { LetterLimit(count: session.letterCount, max: maxLetters) }
            }
            .scrollDismissesKeyboard(.interactively)

            typing
            sources
            Button("Make anagram") {
                isTyping = false
                session.makeAnagram()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(session.source.words.isEmpty || isTooLong
                      || (requiresCorrectSentence && session.review?.isCorrect != true))
        }
        .padding(.vertical)
        .onAppear { if voice { session.startListening() } }
        .task(id: session.source.text) {
            // proofread once the sentence stops changing
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await session.reviewSentence()
        }
        .sheet(isPresented: $showsCamera) {
            TextScannerView { text in
                withAnimation { session.startOver(with: text) }
            }
        }
    }

    /// A field to type the sentence (or add to what was said).
    private var typing: some View {
        HStack {
            TextField(voice ? "…or type a sentence" : "Type a sentence", text: $typed)
                .focused($isTyping)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .onSubmit(add)
            Button("Add", systemImage: "arrow.up.circle.fill", action: add)
                .labelStyle(.iconOnly)
                .font(.title2)
                .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.6), in: .capsule)
        .padding(.horizontal)
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
            if voice { giveMenu }
        }
        .buttonStyle(.bordered)
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
            Label("Give me a sentence", systemImage: "dice")
        }
    }

    private var isTooLong: Bool {
        maxLetters.map { session.letterCount > $0 } ?? false
    }

    private func give(_ level: SentenceBank.Level) {
        guard let sentence = SentenceBank.random(level, language: sentenceLanguage.isEmpty ? nil : sentenceLanguage,
                                                 avoiding: lastGiven) else { return }
        lastGiven = sentence.text
        withAnimation { session.startOver(with: sentence.text, language: sentence.lang) }
    }

    private func add() {
        withAnimation { session.type(typed) }
        typed = ""
    }

    @ViewBuilder private var status: some View {
        if let error = session.error {
            VStack {
                Text(error).foregroundStyle(.red).multilineTextAlignment(.center)
                Button("Try again") { session.startListening() }
            }
            .padding(.horizontal)
        } else if session.isConnecting {
            ProgressView("Connecting…")
        } else {
            VStack(spacing: 6) {
                Group {
                    if session.isTalking {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                    } else if session.isProcessing {
                        Image(systemName: "ellipsis.bubble")
                            .symbolEffect(.pulse, options: .repeating)
                    } else {
                        Image(systemName: session.isListening ? "mic" : "mic.slash")
                    }
                }
                .font(.largeTitle)
                .foregroundStyle(session.isTalking || session.isProcessing ? Color.accentColor : .primary)
                .frame(height: 40)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.default, value: statusText)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var statusText: String {
        if session.isTalking { return "Listening…" }
        if session.isProcessing { return "Got it, writing down your words…" }
        return session.isListening ? "Speak in any language" : "Not listening"
    }
}

/// "12 of 20 letters", red with a hint when the sentence is too long.
private struct LetterLimit: View {
    let count: Int
    let max: Int

    var body: some View {
        let over = count > max
        VStack(spacing: 4) {
            Text(count == 0 ? "Up to \(max) letters" : "\(count) of \(max) letters")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(over ? Color.red : .secondary)
                .contentTransition(.numericText(value: Double(count)))
                .animation(.snappy, value: count)
            if over {
                Text("Too long by \(count - max). Clear it and write a shorter one.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 10)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
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
