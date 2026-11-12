import Foundation

/// A real line from a classic, in its original language (literature.json).
struct LiteraryQuote: Decodable, Equatable {
    let lang: String
    let text: String
    let author: String
    let work: String

    /// "William Shakespeare, Hamlet"
    var credit: String { "\(author), \(work)" }
}

/// Sentences taken from real lines of classic authors: a word of the line (easy), a part of it
/// (medium), or the whole line when it fits (hard).
@MainActor
enum Literature {
    static let all: [LiteraryQuote] = {
        guard let url = Bundle.main.url(forResource: "literature", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([LiteraryQuote].self, from: data)) ?? []
    }()

    /// A piece of a line within `range` letters. `fresh`: only one never given before (nil
    /// when they all were); otherwise the one given longest ago.
    static func make(_ level: SentenceBank.Level, range: ClosedRange<Int>, language: String?,
                     fresh: Bool) -> MadeSentence? {
        let candidates = all
            .filter { language == nil || $0.lang == language }
            .flatMap { quote in
                pieces(of: quote, level: level)
                    .filter { range.contains(SentenceMaker.letterCount($0)) }
                    .map { (text: $0, quote: quote) }
            }
        let chosen = fresh
            ? candidates.filter { !SentenceHistory.wasGiven($0.text) }.randomElement()
            : candidates.min { SentenceHistory.recency($0.text) < SentenceHistory.recency($1.text) }
        return chosen.map { MadeSentence(text: $0.text, language: $0.quote.lang, quote: $0.quote) }
    }

    /// Words of the line (easy, not names); the whole line and its clauses; and for medium also
    /// two or three words in a row ("nostra vita"), not starting or ending on a tiny word.
    static func pieces(of quote: LiteraryQuote, level: SentenceBank.Level) -> [String] {
        switch level {
        case .easy: return SentenceMaker.words(of: quote.text, language: quote.lang)
        case .hard: return SentenceMaker.parts(of: quote.text)
        case .medium:
            let clauses = SentenceMaker.parts(of: quote.text)
            let runs = clauses.flatMap { clause -> [String] in
                let words = clause.split(separator: " ").map(String.init)
                return (2...3).flatMap { size in
                    words.count < size ? [] : (0...(words.count - size)).compactMap { start in
                        let run = words[start..<(start + size)]
                        guard let first = run.first, let last = run.last,
                              SentenceMaker.letterCount(first) >= 3, SentenceMaker.letterCount(last) >= 3
                        else { return nil }
                        return run.joined(separator: " ")
                    }
                }
            }
            return Array(Set(clauses + runs))
        }
    }
}
