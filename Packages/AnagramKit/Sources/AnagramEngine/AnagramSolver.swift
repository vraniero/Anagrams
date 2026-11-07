import Foundation

/// A possible anagram: words that use exactly the sentence's letters.
public struct Suggestion: Hashable, Sendable, Identifiable {
    public let words: [String]
    /// The language of each word.
    public let languages: [String]
    public var text: String { words.joined(separator: " ") }
    public var id: String { text + languages.joined() }
}

/// Finds anagrams of a sentence from word lists (most frequent words first).
///
/// Two steps, so the caller can weed out list junk in between (names, typos) with the same
/// dictionaries the checks use: `candidates` (the words that fit in the letters), then
/// `solve` (combinations of them that use every letter).
public struct AnagramSolver: Sendable {
    public struct Candidate: Hashable, Sendable {
        public let word: String
        public let language: String
        /// Position in the frequency list: lower is more common.
        public let rank: Int
        let key: String  // normalized letters
    }

    struct Entry: Sendable {
        let word: String
        let key: String
        let rank: Int
    }

    private let lexicons: [String: [Entry]]
    private let checker = AnagramChecker()

    /// `lexicons`: words per language code, most frequent first.
    public init(lexicons: [String: [String]]) {
        let checker = AnagramChecker()
        self.lexicons = lexicons.mapValues { words in
            words.enumerated().map { Entry(word: $0.element, key: checker.normalized($0.element), rank: $0.offset) }
        }
    }

    public var languages: [String] { lexicons.keys.sorted() }

    /// Words (in the given languages, or all) whose letters are all in `text`'s.
    public func candidates(for text: String, languages: [String]? = nil) -> [Candidate] {
        let available = checker.letterCounts(text)
        var result: [Candidate] = []
        for language in languages ?? self.languages {
            for entry in lexicons[language] ?? [] where !entry.key.isEmpty && entry.key.count <= available.values.reduce(0, +) {
                var counts = available
                var fits = true
                for ch in entry.key {
                    guard let n = counts[ch], n > 0 else { fits = false; break }
                    counts[ch] = n - 1
                }
                if fits { result.append(Candidate(word: entry.word, language: language, rank: entry.rank, key: entry.key)) }
            }
        }
        return result
    }

    /// Up to `limit` anagrams of `text` from `candidates`: fewest and most common words first.
    /// The sentence itself (same words, in any order) isn't one. Stops after `timeLimit`.
    public func solve(_ text: String, candidates: [Candidate], sameLanguage: Bool,
                      preferring: [String] = [], limit: Int = 12, maxWords: Int = 5,
                      timeLimit: Duration = .seconds(2)) -> [Suggestion] {
        let deadline = ContinuousClock.now.advanced(by: timeLimit)
        let source = checker.normalized(text)
        let sourceWords = text.split(whereSeparator: \.isWhitespace).map { checker.normalized(String($0)) }.sorted()
        var found: [Suggestion] = []
        var seen = Set<[String]>()

        let groups: [[Candidate]]
        if sameLanguage {
            let order = preferring + Set(candidates.map(\.language)).sorted().filter { !preferring.contains($0) }
            groups = order.map { lang in candidates.filter { $0.language == lang } }.filter { !$0.isEmpty }
        } else {
            // one entry per spelling, in the preferred language when it's in several
            var best: [String: Candidate] = [:]
            for c in candidates {
                if let old = best[c.key] {
                    let rankOld = preferring.firstIndex(of: old.language) ?? Int.max
                    let rankNew = preferring.firstIndex(of: c.language) ?? Int.max
                    if rankNew < rankOld || (rankNew == rankOld && c.rank < old.rank) { best[c.key] = c }
                } else {
                    best[c.key] = c
                }
            }
            groups = [Array(best.values)]
        }

        for group in groups {
            var search = Search(source: source, candidates: group, maxWords: maxWords, deadline: deadline,
                                budget: limit * 20)
            for words in search.run() {
                let keys = words.map(\.key)
                let sortedKeys = keys.sorted()
                guard sortedKeys != sourceWords, seen.insert(sortedKeys).inserted else { continue }
                found.append(Suggestion(words: words.map(\.word), languages: words.map(\.language)))
            }
            if ContinuousClock.now >= deadline { break }
        }
        // the sentence's languages first, then fewest words, then the most common ones
        let rank = Dictionary(candidates.map { ("\($0.language)|\($0.word)", $0.rank) }, uniquingKeysWith: min)
        func cost(_ s: Suggestion) -> Int {
            zip(s.words, s.languages).reduce(0) { $0 + (rank["\($1.1)|\($1.0)"] ?? 50_000) }
        }
        func foreign(_ s: Suggestion) -> Int {
            preferring.isEmpty ? 0 : s.languages.filter { !preferring.contains($0) }.count
        }
        return Array(found.sorted { a, b in
            if foreign(a) != foreign(b) { return foreign(a) < foreign(b) }
            if a.words.count != b.words.count { return a.words.count < b.words.count }
            return cost(a) < cost(b)
        }.prefix(limit))
    }
}

/// Depth-first search: the rarest letter left must be in the next word, so only words
/// containing it are tried; longer words first, so short answers come early.
private struct Search {
    let letters: [Character]
    let words: [(candidate: AnagramSolver.Candidate, counts: [Int])]
    let containing: [[Int]]  // per letter: words that have it, longest first
    let maxWords: Int
    let deadline: ContinuousClock.Instant
    let budget: Int
    var results: [[AnagramSolver.Candidate]] = []
    var steps = 0
    var timedOut = false

    init(source: String, candidates: [AnagramSolver.Candidate], maxWords: Int, deadline: ContinuousClock.Instant, budget: Int) {
        let letters = Array(Set(source)).sorted()
        let index = Dictionary(uniqueKeysWithValues: letters.enumerated().map { ($1, $0) })
        self.letters = letters
        self.maxWords = maxWords
        self.deadline = deadline
        self.budget = budget
        let sorted = candidates.sorted { $0.key.count != $1.key.count ? $0.key.count > $1.key.count : $0.rank < $1.rank }
        words = sorted.map { c in
            var counts = Array(repeating: 0, count: letters.count)
            for ch in c.key { counts[index[ch]!] += 1 }
            return (c, counts)
        }
        var containing = Array(repeating: [Int](), count: letters.count)
        for (w, entry) in words.enumerated() {
            for (l, n) in entry.counts.enumerated() where n > 0 { containing[l].append(w) }
        }
        self.containing = containing
        var remaining = Array(repeating: 0, count: letters.count)
        for ch in source { remaining[index[ch]!] += 1 }
        self.remaining = remaining
    }

    private var remaining: [Int]
    private var chosen: [Int] = []

    mutating func run() -> [[AnagramSolver.Candidate]] {
        step()
        return results
    }

    private mutating func step() {
        steps += 1
        if steps % 512 == 0 && ContinuousClock.now >= deadline { timedOut = true }
        guard results.count < budget, !timedOut else { return }
        // the letter left with the fewest words to cover it
        var pivot = -1
        for l in remaining.indices where remaining[l] > 0 {
            if pivot < 0 || containing[l].count < containing[pivot].count { pivot = l }
        }
        if pivot < 0 {
            results.append(chosen.map { words[$0].candidate })
            return
        }
        guard chosen.count < maxWords else { return }
        for w in containing[pivot] {
            let counts = words[w].counts
            guard counts.indices.allSatisfy({ counts[$0] <= remaining[$0] }) else { continue }
            for i in counts.indices { remaining[i] -= counts[i] }
            chosen.append(w)
            step()
            chosen.removeLast()
            for i in counts.indices { remaining[i] += counts[i] }
            if results.count >= budget || timedOut { return }
        }
    }
}
