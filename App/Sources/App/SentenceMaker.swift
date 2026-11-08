import Foundation

/// Where a sentence the app makes comes from.
enum SentenceSource: String, CaseIterable, Identifiable {
    /// The app's own sentences (sentences.json).
    case classic
    /// Last week's newspaper headlines: a headline (or part of one) that fits the level, or a
    /// short sentence Apple Intelligence writes inspired by one.
    case news

    var id: String { rawValue }
    var title: String { self == .classic ? "Classic" : "Newspapers" }
}

/// A sentence the app made, and the headline behind it (newspapers).
struct MadeSentence: Equatable {
    let text: String
    let language: String
    var headline: String? = nil
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

    static func make(_ level: SentenceBank.Level, source: SentenceSource, language: String?,
                     avoiding last: String? = nil) async -> MadeSentence? {
        // -givenSentence "text": always that one (UI tests)
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-givenSentence"), i + 1 < args.count {
            return MadeSentence(text: args[i + 1], language: language ?? "en")
        }
        if source == .news, let made = await fromNews(level, language: language ?? newsLanguage, avoiding: last) {
            return made
        }
        guard let classic = SentenceBank.random(level, language: language, avoiding: last) else { return nil }
        return MadeSentence(text: classic.text, language: classic.lang, isFallback: source == .news)
    }

    /// The device's language if there's news in it, else English.
    static var newsLanguage: String {
        let code = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
        return NewsHeadlines.feeds[code] != nil ? code : "en"
    }

    private static func fromNews(_ level: SentenceBank.Level, language: String, avoiding last: String?) async -> MadeSentence? {
        guard let headlines = try? await NewsHeadlines.shared.headlines(language: language), !headlines.isEmpty else {
            return nil
        }
        let range = letters(level)
        let shuffled = headlines.shuffled()
        // 1. straight from a headline: a word (easy), or a part of one, or a whole short one
        for headline in shuffled {
            let pieces = level == .easy ? words(of: headline, language: language) : parts(of: headline)
            if let piece = pieces.shuffled().first(where: { range.contains(letterCount($0)) && $0 != last }) {
                return MadeSentence(text: piece, language: language, headline: headline)
            }
        }
        // 2. inspired by one: Apple Intelligence writes a short sentence about it
        for headline in shuffled.prefix(3) {
            if let sentence = await OnDeviceMeaningChecker().sentence(inspiredBy: headline, language: language,
                                                                      letters: range),
               range.contains(letterCount(sentence)) {
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
