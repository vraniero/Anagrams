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
    /// Whether the starting sentence is spelled and put together correctly.
    /// For the sentence as it is now (nil while it's being checked, or never was).
    var review: SentenceReview? { reviewedText == source.text ? lastReview : nil }
    private var lastReview: SentenceReview?
    private var reviewedText: String?
    private(set) var isReviewing = false
    private var reviewID = 0
    private(set) var isChecking = false
    private(set) var isListening = false
    private(set) var isConnecting = false  // the backend loads Whisper on first connection
    private(set) var isTalking = false
    /// Stretches of speech heard and still being turned into words.
    private(set) var pending = 0
    var isProcessing: Bool { pending > 0 }
    /// Letters in the sentence (spaces and punctuation don't count).
    var letterCount: Int { source.words.reduce(0) { $0 + $1.blocks.filter(\.character.isLetter).count } }
    private(set) var error: String?
    /// A game's own language rule, chosen before it started; otherwise the Options one.
    var sameLanguageRule: Bool?
    private var sameLanguage: Bool { sameLanguageRule ?? Options.sameLanguage }

    private let transcriber: any SpeechTranscriber
    private let judge: AnagramJudge
    private let validator: any WordValidator
    private let suggester = Suggester()
    private let meaningChecker: any MeaningChecker
    private let proofreader: any SentenceProofreader
    private let sounds = ListeningSounds()
    private var listenTask: Task<Void, Never>?
    private var generation = 0  // bumped by restart: a stale listening task changes nothing

    init(transcriber: (any SpeechTranscriber)? = nil, validator: (any WordValidator)? = nil,
         meaningChecker: (any MeaningChecker & SentenceProofreader)? = nil) {
        let checker = meaningChecker ?? Self.defaultMeaningChecker()
        self.meaningChecker = checker
        self.proofreader = checker
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

    private static func defaultMeaningChecker() -> any MeaningChecker & SentenceProofreader {
        // -meaning yes|no, -grammar ok|wrong: fixed answers (UI tests; the real model's wording varies)
        let args = CommandLine.arguments
        func value(_ name: String) -> String? {
            args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        }
        let meaning = value("-meaning"), grammar = value("-grammar")
        if meaning != nil || grammar != nil {
            return FixedMeaningChecker(makesSense: meaning.map { $0 == "yes" }, grammarOK: grammar.map { $0 == "ok" })
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return FixedMeaningChecker(makesSense: nil, grammarOK: nil)
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

    /// Proofreads the starting sentence: Apple Intelligence for spelling and grammar, or
    /// the dictionaries for spelling alone when it isn't there. Call again when it changes.
    func reviewSentence() async {
        reviewID += 1
        let id = reviewID
        let text = source.text
        let words = source.words.map(\.lookupText).filter { !$0.isEmpty }
        guard !words.isEmpty else {
            lastReview = nil
            isReviewing = false
            return
        }
        isReviewing = true
        var result: SentenceReview?
        if proofreader.isAvailable, let corrected = await proofreader.corrected(text, languages: source.languageCodes) {
            result = .comparing(corrected: corrected, to: text)
        }
        if result == nil {
            var unknown: [String] = []
            for word in words where await validator.language(of: word, preferring: source.languageCodes) == nil {
                unknown.append(word)
            }
            result = SentenceReview(isCorrect: unknown.isEmpty, unknownWords: unknown)
        }
        guard id == reviewID else { return }  // the sentence changed meanwhile
        lastReview = result
        reviewedText = text
        isReviewing = false
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
        lastReview = nil
        reviewID += 1
        isReviewing = false
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

/// Always the same answers (nil: can't check).
struct FixedMeaningChecker: MeaningChecker, SentenceProofreader {
    let makesSense: Bool?
    let grammarOK: Bool?
    var isAvailable: Bool { makesSense != nil || grammarOK != nil }

    func corrected(_ sentence: String, languages: [String]) async -> String? {
        guard let grammarOK else { return nil }
        try? await Task.sleep(for: .milliseconds(200))
        return grammarOK ? sentence : "Corrected: " + sentence
    }

    func meaning(of phrase: String, languages: [String]) async -> Meaning? {
        guard let makesSense else { return nil }
        try? await Task.sleep(for: .milliseconds(300))
        return Meaning(makesSense: makesSense, reading: makesSense ? "It reads as a real phrase." : "Just words side by side.")
    }
}
