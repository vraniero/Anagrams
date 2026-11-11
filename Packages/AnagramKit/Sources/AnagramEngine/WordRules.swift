import Foundation

/// Words that don't count in an anagram, even when a dictionary has them: single letters,
/// and acronyms or abbreviations ("nasa", "tv", "km").
public enum WordRules {
    /// Whether `word` may be used as a word of an anagram in `language` (nil: any).
    public static func isAllowed(_ word: String, language: String?) -> Bool {
        let key = fold(word)
        guard key.count >= 2 else { return false }
        return !isAcronym(key, language: language)
    }

    /// Spell checkers take these as words: acronyms and abbreviations with vowels. Words
    /// with no vowel at all ("tv", "dvd", "km", "mr") are caught without a list.
    static let acronyms: Set<String> = [
        "acli", "afp", "ai", "aids", "aka", "anpi", "ansa", "ap", "asap", "atm", "bmw", "ca", "ceo", "cfr",
        "cgil", "cia", "cio", "co", "coni", "cto", "diy", "dna", "dott", "ecc", "ee", "eg", "eta", "etc",
        "eu", "faq", "fbi", "fiat", "fifa", "fmi", "fyi", "gmo", "ia", "ibid", "ibm", "id", "ie", "imf",
        "imo", "inc", "ing", "inps", "ipo", "iq", "ira", "isis", "istat", "iva", "jr", "ko", "lol", "ltd",
        "nasa", "nato", "nba", "nfl", "ngo", "nhl", "ny", "nyc", "ocse", "oecd", "ogm", "ok", "okay", "omg",
        "oms", "ong", "onu", "pag", "pr", "prof", "rai", "sig", "sos", "sr", "sra", "tel", "tg", "uci", "ue",
        "uefa", "ufo", "uk", "un", "unesco", "unicef", "usa", "usb", "uu", "vip", "who", "wifi",
    ]

    /// Ones that are also ordinary words in a language ("nato" is "born" in Italian).
    static let realWords: [String: Set<String>] = [
        "it": ["nato", "ansa", "usa", "un", "ira", "eta", "coni", "ai", "ia", "tel", "co", "pag"],
        "es": ["usa", "un", "sos", "ira", "eta", "ca", "ee", "uu"],
        "fr": ["usa", "un", "eu", "ca", "ai", "ia", "ira", "ie"],
        "pt": ["eu", "usa", "ia", "ira", "eta", "ca", "ee", "co"],
        "en": ["aids", "fiat", "who", "aka", "eta", "id", "ie", "eg", "imo", "ai"],
        "de": ["eta", "ca"],
        "nl": ["eta", "co", "ie"],
        "sv": ["ko", "sig", "ny", "eta", "ia", "ap", "eu"],
        "da": ["sig", "ny", "eta"],
    ]

    /// Folded to plain lowercase letters: "Città!" → "citta".
    static func fold(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter(\.isLetter)
    }

    static func isAcronym(_ key: String, language: String?) -> Bool {
        let latin = key.unicodeScalars.allSatisfy { $0.value < 0x250 }
        if latin, !key.contains(where: { "aeiouyı".contains($0) }) { return true }
        guard acronyms.contains(key) else { return false }
        guard let language else { return true }
        return realWords[language]?.contains(key) != true
    }
}
