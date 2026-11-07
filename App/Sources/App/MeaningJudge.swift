import Foundation
import AnagramEngine
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Asks Apple Intelligence's on-device model whether an anagram means something. Private
/// and offline; nothing when the model isn't there (older iPhone, Apple Intelligence off,
/// model still downloading, a language it doesn't support).
struct OnDeviceMeaningChecker: MeaningChecker {
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) { return SystemLanguageModel.default.isAvailable }
        #endif
        return false
    }

    func meaning(of phrase: String, languages: [String]) async -> Meaning? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), SystemLanguageModel.default.isAvailable {
            return await Referee.judge(phrase, languages: languages)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable
private struct Judgement {
    @Guide(description: "Exactly the same words, in the order a native speaker would naturally say them. Nothing added or removed")
    var natural: String
    @Guide(description: "At most 12 words in English: what the phrase means, or why it doesn't make sense")
    var reading: String
    @Guide(description: "true only if the phrase, read in the given order, has a coherent meaning")
    var makesSense: Bool
}

@available(iOS 26, *)
private enum Referee {
    static let instructions = """
        You are the referee of an anagram game. Players rearrange the letters of a sentence into new words, \
        so their words are real but often just thrown together. Decide whether the player's words, read in \
        the given order, form a phrase that means something.

        First write the same words in their natural order: would a native speaker put them in the order given? \
        Articles, prepositions and adjectives must sit where the language puts them (Italian "il mare blu", \
        not "mare il blu"; English "the sun rises", not "sun the rises"). Then say what the phrase means.

        It makes sense if it is a grammatical sentence, even a very short one ("they see", "a dog barks"), or \
        a meaningful phrase such as a noun phrase, a title or a headline ("dirty room", "silent night"), or a \
        poetic line a reader can still understand. A missing article or punctuation is fine. Words may come \
        from different languages: judge the mix as a multilingual reader would ("the gato sleeps" makes sense).

        It does not make sense if it is a list of unrelated words ("cat dog tree", "lens tin"), word salad, \
        or words in an order the language doesn't allow ("barks a dog").

        Write in English.
        """

    static func judge(_ phrase: String, languages: [String]) async -> Meaning? {
        let english = Locale(identifier: "en")
        let names = languages.reduce(into: [String]()) { names, code in
            let name = english.localizedString(forLanguageCode: code) ?? code
            if !names.contains(name) { names.append(name) }
        }
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(
                to: "Phrase: \(phrase)\nLanguages of its words: \(names.joined(separator: ", "))",
                generating: Judgement.self,
                options: GenerationOptions(sampling: .greedy))
            let judgement = response.content
            // the model happily accepts a phrase it silently reorders: same words, other order = no
            if judgement.makesSense, Meaning.isReordering(judgement.natural, of: phrase) {
                return Meaning(makesSense: false, reading: "Close, but the words are out of order: “\(judgement.natural)”.")
            }
            return Meaning(makesSense: judgement.makesSense, reading: judgement.reading)
        } catch {
            return nil  // refused, unsupported language, model busy: no bonus, no penalty
        }
    }
}
#endif
