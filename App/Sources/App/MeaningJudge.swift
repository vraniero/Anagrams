import Foundation
import AnagramEngine
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Asks Apple Intelligence's on-device model whether an anagram means something. Private
/// and offline; nothing when the model isn't there (older iPhone, Apple Intelligence off,
/// model still downloading, a language it doesn't support).
struct OnDeviceMeaningChecker: MeaningChecker, SentenceProofreader {
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

    /// A short sentence in `language`, about the news in `headline`, of about `letters` letters.
    func sentence(inspiredBy headline: String, language: String, letters: ClosedRange<Int>) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), SystemLanguageModel.default.isAvailable {
            return await Inspiration.write(about: headline, language: language, letters: letters)
        }
        #endif
        return nil
    }

    func corrected(_ sentence: String, languages: [String]) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), SystemLanguageModel.default.isAvailable {
            return await Proofreader.correct(sentence, languages: languages)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
private func englishLanguageNames(_ codes: [String]) -> String {
    let english = Locale(identifier: "en")
    var names: [String] = []
    for code in codes {
        let name = english.localizedString(forLanguageCode: code) ?? code
        if !names.contains(name) { names.append(name) }
    }
    return names.joined(separator: ", ")
}

@available(iOS 26, *)
@Generable
private struct Proofreading {
    @Guide(description: "The sentence with its spelling and grammar mistakes fixed, changing as little as possible, in the same language. Identical to the original if it is already correct")
    var corrected: String
    @Guide(description: "At most 12 words in English: the mistake, or 'Correct.'")
    var problem: String
}

@available(iOS 26, *)
@Generable
private struct Inspired {
    @Guide(description: "The short sentence, in the requested language, with no quotes")
    var sentence: String
}

/// A short sentence for a word game, about a news headline.
@available(iOS 26, *)
private enum Inspiration {
    static func write(about headline: String, language: String, letters: ClosedRange<Int>) async -> String? {
        let name = englishLanguageNames([language])
        let words = letters.upperBound <= 8 ? "one word" : letters.upperBound <= 14 ? "two or three words" : "a short sentence"
        let session = LanguageModelSession(instructions: """
            You write very short, correct, natural \(name) phrases for a word game, inspired by a news headline. \
            Use common words. No names of people, no numbers, no quotes. Write only in \(name).
            """)
        do {
            let response = try await session.respond(
                to: "Headline: \(headline)\nWrite \(words) in \(name) about it, \(letters.lowerBound) to \(letters.upperBound) letters in total.",
                generating: Inspired.self,
                options: GenerationOptions(temperature: 0.7))
            return response.content.sentence.trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”«».!"))
        } catch {
            return nil
        }
    }
}

/// Spelling and grammar of the starting sentence. Its verdict is the corrected text: the
/// sentence is right when nothing but capitals, punctuation and accents changed.
@available(iOS 26, *)
private enum Proofreader {
    static let instructions = """
        You proofread sentences that players type into a word game. Check spelling and grammar only, in the \
        sentence's own language (or languages). Ignore capitalization and punctuation: a missing capital letter, \
        full stop, comma or accent mark is NOT a mistake. Do not judge style, meaning or whether the sentence is \
        interesting. Short sentences and phrases (a title, "good morning", "silent night") are fine. Never \
        translate.
        """

    static func correct(_ sentence: String, languages: [String]) async -> String? {
        let session = LanguageModelSession(instructions: instructions)
        let languageLine = languages.isEmpty ? "" : "\nLanguage: \(englishLanguageNames(languages))"
        do {
            let response = try await session.respond(to: "Sentence: \(sentence)\(languageLine)",
                                                     generating: Proofreading.self,
                                                     options: GenerationOptions(sampling: .greedy))
            return response.content.corrected
        } catch {
            return nil
        }
    }
}

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
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(
                to: "Phrase: \(phrase)\nLanguages of its words: \(englishLanguageNames(languages))",
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
