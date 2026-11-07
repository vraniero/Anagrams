import Testing
import AnagramEngine

/// The real system dictionaries (coverage depends on the device; these are common ones).
@MainActor
struct TextCheckerValidatorTests {
    let validator = TextCheckerValidator()

    @Test func findsWordsInSeveralLanguages() async {
        #expect(await validator.language(of: "silent", preferring: ["en"]) == "en")
        #expect(await validator.language(of: "amore", preferring: ["it"]) == "it")
        #expect(await validator.language(of: "Haus", preferring: ["de"]) == "de")
        #expect(await validator.language(of: "дом", preferring: []) == "ru")
        #expect(await validator.language(of: "corazón", preferring: ["es"]) == "es")
        #expect(await validator.language(of: "corazón", preferring: []) != nil)
    }

    @Test func shortAndLongWords() async {
        #expect(await validator.language(of: "a", preferring: ["en"]) == "en")
        #expect(await validator.language(of: "è", preferring: ["it"]) == "it")
        #expect(await validator.language(of: "il", preferring: ["it"]) == "it")
        #expect(await validator.language(of: "internazionale", preferring: ["it"]) == "it")
        #expect(await validator.language(of: "Donaudampfschiff", preferring: ["de"]) == "de")
    }

    /// Names and abbreviations are capitalized in the dictionaries ("Oa", "Ao"): not words.
    @Test func capitalizedOnlyEntriesAreNotWords() async {
        for word in ["oa", "ao"] {
            let found = await validator.language(of: word, preferring: ["it"])
            #expect(found != "it", "\(word) found in \(found ?? "")")
        }
        #expect(await validator.language(of: "haus", preferring: []) == "de")
    }

    @Test func rejectsNonWords() async {
        for word in ["xqzvtk", "ltsnie", "aeomr", "жщъыйц"] {
            let found = await validator.language(of: word, preferring: [])
            #expect(found == nil, "\(word) found in \(found ?? "")")
        }
    }
}
