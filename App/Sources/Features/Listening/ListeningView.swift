import SwiftUI

/// Where the sentence comes from: said (live, as letter blocks), typed, read with the camera,
/// or given by the app at a chosen difficulty. "Make anagram" stops listening.
struct ListeningView: View {
    @Environment(GameSession.self) private var session
    /// What to do, shown on top (the game modes: whose turn it is).
    var prompt: String? = nil
    /// Training: the sentence can be said, and the app can give one. The games: typed or
    /// read with the camera only.
    var voice = true
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
            .disabled(session.source.words.isEmpty)
        }
        .padding(.vertical)
        .onAppear { if voice { session.startListening() } }
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
