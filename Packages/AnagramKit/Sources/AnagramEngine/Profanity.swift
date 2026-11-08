import Foundation

/// Swear words, for the "swear words" bonus: common ones per language (the app's seven).
/// Matched whole, ignoring case and accents ("cabron" is "cabrón").
public enum Profanity {
    static let words: [String: Set<String>] = [
        "en": ["fuck", "fucking", "fucker", "shit", "shitty", "bitch", "bastard", "asshole", "arse", "ass",
               "damn", "crap", "dick", "piss", "pissed", "bollocks", "bugger", "wanker", "cunt", "prick",
               "twat", "slut", "whore", "cock", "tits", "bloody", "goddamn", "motherfucker", "jerk", "sod"],
        "it": ["cazzo", "cazzi", "cazzata", "merda", "stronzo", "stronza", "stronzi", "vaffanculo", "fanculo",
               "culo", "puttana", "troia", "minchia", "coglione", "coglioni", "porco", "porca", "fottuto",
               "fottere", "bastardo", "figa", "mignotta", "palle", "tette", "cagare", "sfigato", "cretino",
               "deficiente", "idiota", "zoccola"],
        "es": ["mierda", "joder", "jodido", "puta", "puto", "coño", "cabrón", "gilipollas", "cojones", "culo",
               "pendejo", "carajo", "hostia", "polla", "zorra", "imbécil", "capullo", "follar", "chingar",
               "pinche", "cabrona", "mamón", "idiota"],
        "fr": ["merde", "putain", "connard", "connasse", "conne", "con", "salope", "bordel", "chier", "enculé",
               "bite", "couille", "couilles", "foutre", "cul", "pute", "nique", "salaud", "chiant", "crétin",
               "emmerder", "branleur"],
        "de": ["scheiße", "scheisse", "arsch", "arschloch", "fick", "ficken", "verdammt", "hure", "schlampe",
               "wichser", "mist", "kacke", "fotze", "schwanz", "sau", "miststück", "depp", "idiot", "verpiss",
               "blödmann", "pisse"],
        "pt": ["merda", "porra", "caralho", "puta", "foda", "foder", "fodase", "cu", "cabrão", "buceta", "bosta",
               "piroca", "cacete", "otário", "babaca", "viado", "corno", "idiota"],
        "nl": ["kut", "klootzak", "shit", "kanker", "lul", "hoer", "godverdomme", "tering", "pik", "eikel",
               "verdomme", "kak", "trut", "sukkel", "zak", "stront", "tyfus", "kloot"],
    ]

    private static let folded: [String: Set<String>] = words.mapValues { Set($0.map(fold)) }
    private static let anyLanguage: Set<String> = folded.values.reduce(into: Set()) { $0.formUnion($1) }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter }
    }

    /// Whether `word` is a swear word, in `language` (or any of the seven when it's unknown).
    public static func isSwear(_ word: String, language: String?) -> Bool {
        let key = fold(word)
        guard !key.isEmpty else { return false }
        if let language, let list = folded[language] { return list.contains(key) }
        return anyLanguage.contains(key)
    }
}
