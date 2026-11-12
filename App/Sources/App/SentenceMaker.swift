import Foundation

/// Where a sentence the app makes comes from.
enum SentenceSource: String, CaseIterable, Identifiable {
    /// The app's own sentences (sentences.json).
    case classic
    /// Last week's newspaper headlines: a headline (or part of one) that fits the level, or a
    /// short sentence Apple Intelligence writes inspired by one.
    case news
    /// Real lines of classic authors (literature.json): a word, a part, or the whole line.
    case literature

    var id: String { rawValue }
    var title: String {
        switch self {
        case .classic: "Classic"
        case .news: "Newspapers"
        case .literature: "Literature"
        }
    }
    var icon: String {
        switch self {
        case .classic: "text.book.closed"
        case .news: "newspaper"
        case .literature: "books.vertical"
        }
    }
    var detail: String {
        switch self {
        case .classic: "The app's own sentences."
        case .news: "From last week's newspaper headlines, or inspired by one."
        case .literature: "From real lines of classic authors: a word of the line, a part of it, or all of it."
        }
    }
}

/// A sentence the app made, and the headline (newspapers) or line (literature) behind it.
struct MadeSentence: Equatable {
    let text: String
    let language: String
    var headline: String? = nil
    var quote: LiteraryQuote? = nil
    /// The news couldn't be read: this is a classic sentence instead.
    var isFallback = false
}

/// Makes a sentence to anagram at a level, from the app's own sentences or the news.
@MainActor
enum SentenceMaker {
    /// Letters per level, as in the app's own sentences.
    static func letters(_ level: SentenceBank.Level) -> ClosedRange<Int> {
        switch level {
        case .easy: 4...8
        case .medium: 6...14
        case .hard: 12...30
        }
    }

    /// Letters for the level, within `maxLetters` (Multiplayer's longest sentence).
    static func letters(_ level: SentenceBank.Level, maxLetters: Int?) -> ClosedRange<Int> {
        let range = letters(level)
        guard let maxLetters else { return range }
        let upper = max(1, min(range.upperBound, maxLetters))
        return min(range.lowerBound, upper)...upper
    }

    /// A sentence never given before (see `SentenceHistory`). When the app's own sentences
    /// for that choice have all been given, it turns to the news; only if that fails too
    /// does it repeat the one given longest ago.
    static func make(_ level: SentenceBank.Level, source: SentenceSource, language: String?,
                     maxLetters: Int? = nil) async -> MadeSentence? {
        // -givenSentence "text": always that one (UI tests)
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-givenSentence"), i + 1 < args.count {
            return MadeSentence(text: args[i + 1], language: language ?? "en")
        }
        guard let made = await pick(level, source: source, language: language, maxLetters: maxLetters) else {
            return nil
        }
        SentenceHistory.remember(made.text)
        return made
    }

    private static func pick(_ level: SentenceBank.Level, source: SentenceSource, language: String?,
                             maxLetters: Int?) async -> MadeSentence? {
        let range = letters(level, maxLetters: maxLetters)
        if source == .news, let made = await fromNews(level, range: range, language: language ?? newsLanguage) {
            return made
        }
        // literature: a new piece of a line, else the one given longest ago
        if source == .literature,
           let made = Literature.make(level, range: range, language: language, fresh: true)
            ?? Literature.make(level, range: range, language: language, fresh: false) {
            return made
        }
        if let classic = SentenceBank.random(level, language: language, maxLetters: maxLetters, fresh: true) {
            return MadeSentence(text: classic.text, language: classic.lang, isFallback: source == .news)
        }
        // all of the app's own given already: a new one from the news
        if source == .classic,
           let made = await fromNews(level, range: range, language: language ?? newsLanguage) {
            return made
        }
        guard let oldest = SentenceBank.random(level, language: language, maxLetters: maxLetters, fresh: false)
        else { return nil }
        return MadeSentence(text: oldest.text, language: oldest.lang, isFallback: source == .news)
    }

    /// The device's language if there's news in it, else English.
    static var newsLanguage: String {
        let code = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
        return NewsHeadlines.feeds[code] != nil ? code : "en"
    }

    private static func fromNews(_ level: SentenceBank.Level, range: ClosedRange<Int>,
                                 language: String) async -> MadeSentence? {
        guard let headlines = try? await NewsHeadlines.shared.headlines(language: language), !headlines.isEmpty else {
            return nil
        }
        let shuffled = headlines.shuffled()
        // 1. straight from a headline: a word (easy), or a part of one, or a whole short one
        for headline in shuffled {
            let pieces = level == .easy ? words(of: headline, language: language) : parts(of: headline)
            if let piece = pieces.shuffled().first(where: { range.contains(letterCount($0)) && !SentenceHistory.wasGiven($0) }) {
                return MadeSentence(text: piece, language: language, headline: headline)
            }
        }
        // 2. inspired by one: Apple Intelligence writes a short sentence about it
        for headline in shuffled.prefix(3) {
            if let sentence = await OnDeviceMeaningChecker().sentence(inspiredBy: headline, language: language,
                                                                      letters: range),
               range.contains(letterCount(sentence)), !SentenceHistory.wasGiven(sentence) {
                return MadeSentence(text: sentence, language: language, headline: headline)
            }
        }
        return nil
    }

    static func letterCount(_ text: String) -> Int { text.filter(\.isLetter).count }

    /// Clauses of a headline ("Rome: the sun is back, finally" → "Rome", "the sun is back",
    /// "finally", and the whole), trimmed of quotes and stray punctuation.
    static func parts(of headline: String) -> [String] {
        let separators = CharacterSet(charactersIn: ":;,.!?|–—()[]")
        let clauses = headline.components(separatedBy: separators)
        return ([headline] + clauses).map(clean).filter { !$0.isEmpty }
    }

    /// Words of a headline good for "one word": lowercase ones (not names), German nouns too.
    static func words(of headline: String, language: String) -> [String] {
        clean(headline).split(whereSeparator: { !$0.isLetter }).map(String.init).filter { word in
            guard let first = word.first else { return false }
            return first.isLowercase || language == "de"
        }
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”‘’«»-–—:,.;"))
            .replacingOccurrences(of: "  ", with: " ")
    }
}

/// Every sentence the app has given, kept across launches, so it never gives the same one
/// twice (compared on letters and spaces only: case, accents and punctuation ignored).
@MainActor
enum SentenceHistory {
    static let key = "sentences.given"
    private static let limit = 5000

    /// Oldest first.
    private static var given: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.suffix(limit)), forKey: key) }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0 == " " }
            .split(separator: " ").joined(separator: " ")
    }

    static func wasGiven(_ text: String) -> Bool { given.contains(fold(text)) }

    static func remember(_ text: String) {
        let folded = fold(text)
        given = given.filter { $0 != folded } + [folded]
    }

    /// How long ago it was given: 0 never, then bigger the more recent.
    static func recency(_ text: String) -> Int {
        let list = given
        return list.lastIndex(of: fold(text)).map { $0 + 1 } ?? 0
    }

    static func forget() { UserDefaults.standard.removeObject(forKey: key) }
}

/// Headlines from the last seven days, per language, from Google News' RSS feeds (top
/// stories of the country's papers). Kept for an hour.
actor NewsHeadlines {
    static let shared = NewsHeadlines()

    /// language → (hl, gl, ceid) for news.google.com/rss
    static let feeds: [String: (String, String, String)] = [
        "en": ("en-GB", "GB", "GB:en"), "it": ("it", "IT", "IT:it"), "es": ("es", "ES", "ES:es"),
        "fr": ("fr", "FR", "FR:fr"), "de": ("de", "DE", "DE:de"), "pt": ("pt-PT", "PT", "PT:pt-150"),
        "nl": ("nl", "NL", "NL:nl"),
    ]

    private var cache: [String: (fetched: Date, titles: [String])] = [:]

    func headlines(language: String) async throws -> [String] {
        if let cached = cache[language], cached.fetched.timeIntervalSinceNow > -3600 { return cached.titles }
        guard let (hl, gl, ceid) = Self.feeds[language],
              let url = URL(string: "https://news.google.com/rss?hl=\(hl)&gl=\(gl)&ceid=\(ceid)") else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Anagrams", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        let weekAgo = Date.now.addingTimeInterval(-7 * 24 * 3600)
        let titles = RSSTitles.parse(data)
            .filter { ($0.date ?? .now) >= weekAgo }
            .map { Self.withoutSource($0.title) }
            .filter { !$0.isEmpty }
        cache[language] = (.now, titles)
        return titles
    }

    /// "The sun is back - The Guardian" → "The sun is back".
    static func withoutSource(_ title: String) -> String {
        guard let range = title.range(of: " - ", options: .backwards) else { return title }
        return String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
    }
}

/// The items of an RSS feed: title and publication date.
final class RSSTitles: NSObject, XMLParserDelegate {
    struct Item { var title = ""; var date: Date? }

    private var items: [Item] = []
    private var current: Item?
    private var text = ""

    static func parse(_ data: Data) -> [Item] {
        let delegate = RSSTitles()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if name == "item" { current = Item() }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "title": current?.title = value
        case "pubDate": current?.date = Self.dateFormat.date(from: value)
        case "item": if let current { items.append(current) }; current = nil
        default: break
        }
    }
}
