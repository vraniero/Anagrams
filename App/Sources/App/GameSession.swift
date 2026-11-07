import Foundation
import Observation
import AnagramEngine
import AnagramModels
import SpeechCapture

/// Drives the flow: listening → building and checking an anagram.
@MainActor
@Observable
final class GameSession {
    enum Stage { case listening, building }

    var stage: Stage = .listening
    /// The spoken sentence. Frozen after "Make anagram" (except speech still being transcribed).
    private(set) var source = Phrase()
    var board = AnagramBoard()
    var verdict: AnagramVerdict?
    /// Whether the last valid anagram means something (training shows it under the verdict).
    private(set) var meaning: Meaning?
    private(set) var isCheckingMeaning = false
    var canCheckMeaning: Bool { meaningChecker.isAvailable }
    private(set) var isChecking = false
    private(set) var isListening = false
    private(set) var isConnecting = false  // the backend loads Whisper on first connection
    private(set) var isTalking = false
    /// Stretches of speech heard and still being turned into words.
    private(set) var pending = 0
    var isProcessing: Bool { pending > 0 }
    private(set) var error: String?
    /// A game's own language rule, chosen before it started; otherwise the Options one.
    var sameLanguageRule: Bool?
    private var sameLanguage: Bool { sameLanguageRule ?? Options.sameLanguage }

    private let transcriber: any SpeechTranscriber
    private let judge: AnagramJudge
    private let validator: any WordValidator
    private let suggester = Suggester()
    private let meaningChecker: any MeaningChecker
    private let sounds = ListeningSounds()
    private var listenTask: Task<Void, Never>?
    private var generation = 0  // bumped by restart: a stale listening task changes nothing

    init(transcriber: (any SpeechTranscriber)? = nil, validator: (any WordValidator)? = nil,
         meaningChecker: (any MeaningChecker)? = nil) {
        self.meaningChecker = meaningChecker ?? Self.defaultMeaningChecker()
        self.transcriber = transcriber ?? Self.defaultTranscriber()
        let validator = validator ?? Self.defaultValidator()
        self.validator = validator
        self.judge = AnagramJudge(validator: validator)
    }

    private static func defaultTranscriber() -> any SpeechTranscriber {
        // hosting unit tests: no microphone (the tests bring their own transcriber)
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return DemoTranscriber(script: [])
        }
        // -demoText "some sentence": play that sentence instead of listening
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-demoText"), i + 1 < args.count {
            return DemoTranscriber(script: [Utterance(id: 1, lang: nil, start: 0, end: 1, text: args[i + 1])])
        }
        #if os(iOS)
        if !args.contains("-demo") {
            return ServerTranscriber(holdAfterReady: ListeningSounds.duration + 0.1)
        }
        #endif
        return DemoTranscriber()
    }

    private static func defaultMeaningChecker() -> any MeaningChecker {
        // -meaning "yes" or "no": a fixed answer (UI tests; the real model's wording varies)
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-meaning"), i + 1 < args.count {
            return FixedMeaningChecker(makesSense: args[i + 1] == "yes")
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return FixedMeaningChecker(makesSense: nil)
        }
        return OnDeviceMeaningChecker()
    }

    private static func defaultValidator() -> any WordValidator {
        #if canImport(UIKit)
        TextCheckerValidator()
        #else
        WordListValidator([:])
        #endif
    }

    func startListening() {
        guard !isListening else { return }
        generation += 1
        let current = generation
        error = nil
        isListening = true
        isConnecting = true
        listenTask = Task {
            do {
                for try await event in try await transcriber.start() {
                    guard current == generation else { return }
                    handle(event)
                }
            } catch {
                if current == generation { self.error = error.localizedDescription }
            }
            guard current == generation else { return }
            isListening = false
            isConnecting = false
            isTalking = false
            pending = 0
        }
    }

    /// Stops listening: what was already said is still added, nothing said afterwards.
    func makeAnagram() {
        if isListening {
            transcriber.finish()
            sounds.playStop()
        }
        isTalking = false
        board = AnagramBoard(source: source)
        stage = .building
    }

    /// Typed instead of (or as well as) said: added like a heard utterance. The language
    /// comes from the text itself (two-letter code, like Whisper's).
    func type(_ text: String, language: String? = nil) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let language = language ?? LanguageDetector().dominantLanguage(of: text).map { String($0.prefix(2)) }
        source.append(text: text, languageCode: language)
    }

    /// A new starting sentence (read by the camera, or given by the app), replacing what's there.
    func startOver(with text: String, language: String? = nil) {
        source = Phrase()
        type(text, language: language)
    }

    /// Starts the sentence over without leaving the listening screen (a misheard word).
    func clearSentence() {
        source = Phrase()
    }

    /// Shows the verdict on the board (training), then whether it means something.
    func check() async {
        meaning = nil
        let verdict = await evaluate()
        self.verdict = verdict
        meaning = await meaning(of: verdict)
    }

    /// Whether a correct anagram of two or more words means something; nil if it isn't
    /// one, or it can't be told on this iPhone.
    func meaning(of verdict: AnagramVerdict) async -> Meaning? {
        guard Meaning.applies(to: verdict), meaningChecker.isAvailable else { return nil }
        isCheckingMeaning = true
        defer { isCheckingMeaning = false }
        return await meaningChecker.meaning(of: board.candidate.text,
                                            languages: verdict.words.compactMap(\.language))
    }

    /// Judges the anagram being built, without showing anything (the game modes decide).
    func evaluate() async -> AnagramVerdict {
        isChecking = true
        defer { isChecking = false }
        return await judge.judge(board.candidate, source: source, sameLanguage: sameLanguage)
    }

    /// Possible anagrams of the sentence (words checked with the same dictionaries as Check).
    func suggestions() async -> [Suggestion] {
        await suggester.suggest(for: source, sameLanguage: sameLanguage, validator: validator)
    }

    func restart() {
        generation += 1
        transcriber.cancel()
        listenTask?.cancel()
        isListening = false
        isConnecting = false
        isTalking = false
        pending = 0
        source = Phrase()
        board = AnagramBoard()
        verdict = nil
        meaning = nil
        stage = .listening
    }

    private func handle(_ event: TranscriptEvent) {
        switch event {
        case .ready:
            isConnecting = false
            sounds.playStart()
        case .speechStarted: isTalking = stage == .listening
        case .speechEnded: isTalking = false
        case .transcribing: pending += 1
        case .discarded: pending = max(0, pending - 1)
        case .utterance(let u):
            isConnecting = false
            pending = max(0, pending - 1)
            source.append(text: u.text, languageCode: u.lang)
            if stage == .building { board.updateSource(source) }
        }
    }
}

/// Always the same answer (nil: can't check).
struct FixedMeaningChecker: MeaningChecker {
    let makesSense: Bool?
    var isAvailable: Bool { makesSense != nil }

    func meaning(of phrase: String, languages: [String]) async -> Meaning? {
        guard let makesSense else { return nil }
        try? await Task.sleep(for: .milliseconds(300))
        return Meaning(makesSense: makesSense, reading: makesSense ? "It reads as a real phrase." : "Just words side by side.")
    }
}
