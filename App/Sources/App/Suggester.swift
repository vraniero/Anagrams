import Foundation
import AnagramEngine
import AnagramModels

/// Finds possible anagrams with the bundled word lists, then keeps only those whose words
/// the device's dictionaries accept (the lists have names and typos in them).
@MainActor
final class Suggester {
    private var solver: AnagramSolver?
    private var known: [String: Bool] = [:]  // "it|amore" -> a word

    func suggest(for source: Phrase, sameLanguage: Bool, validator: any WordValidator) async -> [Suggestion] {
        let text = source.text
        guard !text.isEmpty else { return [] }
        let solver = await loadedSolver()
        let preferring = source.languageCodes
        let raw = await Task.detached(priority: .userInitiated) {
            // no single letters or acronyms
            let candidates = solver.candidates(for: text).filter {
                $0.rank < 20_000 && WordRules.isAllowed($0.word, language: $0.language)
            }
            return solver.solve(text, candidates: candidates, sameLanguage: sameLanguage,
                                preferring: preferring, limit: 80, timeLimit: .seconds(2))
        }.value
        var result: [Suggestion] = []
        for suggestion in raw {
            var ok = true
            for (word, language) in zip(suggestion.words, suggestion.languages) where ok {
                ok = await isWord(word, language, validator)
            }
            if ok { result.append(suggestion) }
            if result.count == 10 { break }
        }
        return result
    }

    private func isWord(_ word: String, _ language: String, _ validator: any WordValidator) async -> Bool {
        guard WordRules.isAllowed(word, language: language) else { return false }
        let key = "\(language)|\(word)"
        if let known = known[key] { return known }
        let ok = await validator.isWord(word, in: language)
        known[key] = ok
        return ok
    }

    private func loadedSolver() async -> AnagramSolver {
        if let solver { return solver }
        let loaded = await Task.detached(priority: .userInitiated) {
            var lexicons: [String: [String]] = [:]
            for url in Bundle.main.urls(forResourcesWithExtension: "txt", subdirectory: nil) ?? []
            where url.lastPathComponent.hasPrefix("lexicon-") {
                let language = String(url.deletingPathExtension().lastPathComponent.dropFirst("lexicon-".count))
                lexicons[language] = (try? String(contentsOf: url, encoding: .utf8))?
                    .split(separator: "\n").map(String.init) ?? []
            }
            return AnagramSolver(lexicons: lexicons)
        }.value
        solver = loaded
        return loaded
    }
}

/// Sentences the app gives to anagram, by difficulty.
struct SentenceBank {
    enum Level: String, CaseIterable, Identifiable {
        case easy, medium, hard
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var detail: String {
            switch self {
            case .easy: "One word"
            case .medium: "A few words"
            case .hard: "A whole sentence"
            }
        }
    }

    struct Sentence: Decodable, Equatable {
        let level: String
        let lang: String
        let text: String
    }

    static let all: [Sentence] = {
        guard let url = Bundle.main.url(forResource: "sentences", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Sentence].self, from: data)) ?? []
    }()

    /// Languages with the app's own sentences or lines of literature (Classic falls back to the
    /// news in a language it has none of).
    @MainActor
    static var languages: [String] { Array(Set(all.map(\.lang) + Literature.all.map(\.lang))).sorted() }

    /// A random sentence of that level (in that language, if given).
    /// `fresh`: only one never given before (nil when they all were); otherwise the one
    /// given longest ago.
    @MainActor
    static func random(_ level: Level, language: String?, maxLetters: Int? = nil, fresh: Bool = true) -> Sentence? {
        var pool = all.filter { $0.level == level.rawValue && (language == nil || $0.lang == language) }
        if let maxLetters {
            let fitting = pool.filter { $0.text.filter(\.isLetter).count <= maxLetters }
            // nothing at that level fits: the longest that does, from any level
            pool = fitting.isEmpty
                ? all.filter { (language == nil || $0.lang == language) && $0.text.filter(\.isLetter).count <= maxLetters }
                : fitting
        }
        if fresh { return pool.filter { !SentenceHistory.wasGiven($0.text) }.randomElement() }
        return pool.min { SentenceHistory.recency($0.text) < SentenceHistory.recency($1.text) }
    }
}
