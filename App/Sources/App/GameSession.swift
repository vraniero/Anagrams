import Foundation
import Observation
import AnagramEngine
import AnagramModels

/// Drives the flow: writing the sentence (typed, read by the camera, or given by the app) →
/// building and checking an anagram. No audio: nothing is ever recorded.
@MainActor
@Observable
final class GameSession {
    enum Stage { case writing, building }

    var stage: Stage = .writing
    /// The starting sentence. Frozen after "Make anagram".
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
    /// What's being typed: already the sentence's last words, so its tiles show as you type.
    private(set) var draft = ""
    private var draftWords: [Word] = []
    /// Multiplayer: the most letters the sentence may have; typing stops there.
    var letterLimit: Int?
    /// Letters still allowed (nil: no limit).
    var lettersLeft: Int? { letterLimit.map { max(0, $0 - letterCount) } }
    /// Letters in the sentence (spaces and punctuation don't count).
    var letterCount: Int { source.words.reduce(0) { $0 + $1.blocks.filter(\.character.isLetter).count } }
    /// A game's own language rule, chosen before it started; otherwise the Options one.
    var sameLanguageRule: Bool?
    private var sameLanguage: Bool { sameLanguageRule ?? Options.sameLanguage }

    private let judge: AnagramJudge
    private let validator: any WordValidator
    private let suggester = Suggester()
    private let meaningChecker: any MeaningChecker
    private let proofreader: any SentenceProofreader

    init(validator: (any WordValidator)? = nil, meaningChecker: (any MeaningChecker & SentenceProofreader)? = nil) {
        let checker = meaningChecker ?? Self.defaultMeaningChecker()
        self.meaningChecker = checker
        self.proofreader = checker
        let validator = validator ?? Self.defaultValidator()
        self.validator = validator
        self.judge = AnagramJudge(validator: validator)
        startWithDemoSentence()
    }

    /// UI tests: -demoText "a sentence" starts with that sentence; -demo with "Listen, Roma è".
    private func startWithDemoSentence() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-demoText"), i + 1 < args.count {
            type(args[i + 1])
        } else if args.contains("-demo") {
            type("Listen,", language: "en")
            type("Roma è", language: "it")
        }
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

    /// The sentence is ready: on to the board.
    func makeAnagram() {
        keepDraft()
        board = AnagramBoard(source: source)
        stage = .building
    }

    /// The text being typed changed: its words replace the previous draft's at the end of the
    /// sentence. Letters beyond the limit aren't taken. Tiles that didn't change keep their
    /// identity, so only the new ones land.
    func setDraft(_ text: String) {
        let previous = Set(draftWords.map(\.id))
        source.words.removeAll { previous.contains($0.id) }
        var text = text
        if let letterLimit {
            let room = max(0, letterLimit - letterCount)
            // at the limit nothing more goes in: cut right after the last letter allowed
            var seen = 0
            if room == 0 {
                text = ""
            } else {
                for i in text.indices where text[i].isLetter {
                    seen += 1
                    if seen == room {
                        text = String(text[...i])
                        break
                    }
                }
            }
        }
        let language = LanguageDetector().dominantLanguage(of: text).map { String($0.prefix(2)) }
        let oldBlocks = draftWords.flatMap(\.blocks)
        var k = 0
        var same = true
        var words: [Word] = []
        for part in text.split(whereSeparator: \.isWhitespace) {
            var blocks: [LetterBlock] = []
            for ch in part where ch.isLetter {
                if same, k < oldBlocks.count, oldBlocks[k].character == ch {
                    blocks.append(oldBlocks[k])
                } else {
                    same = false
                    blocks.append(LetterBlock(character: ch))
                }
                k += 1
            }
            guard !blocks.isEmpty else { continue }
            let id = words.count < draftWords.count ? draftWords[words.count].id : UUID()
            words.append(Word(id: id, blocks: blocks, languageCode: language))
        }
        draftWords = words
        source.words += words
        draft = text
    }

    /// The typed words stay in the sentence; typing starts afresh after them.
    private func keepDraft() {
        draftWords = []
        draft = ""
    }

    /// Text added to the sentence. The language comes from the text itself (two-letter code).
    func type(_ text: String, language: String? = nil) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let language = language ?? LanguageDetector().dominantLanguage(of: text).map { String($0.prefix(2)) }
        source.append(text: text, languageCode: language)
    }

    /// A new starting sentence (read by the camera, or given by the app), replacing what's there.
    func startOver(with text: String, language: String? = nil) {
        keepDraft()
        source = Phrase()
        type(text, language: language)
    }

    /// Starts the sentence over without leaving the sentence screen.
    func clearSentence() {
        keepDraft()
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
        source = Phrase()
        board = AnagramBoard()
        verdict = nil
        meaning = nil
        keepDraft()
        lastReview = nil
        reviewID += 1
        isReviewing = false
        stage = .writing
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
