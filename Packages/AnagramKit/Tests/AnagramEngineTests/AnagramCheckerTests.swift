import Testing
import AnagramModels
@testable import AnagramEngine

struct AnagramCheckerTests {
    let checker = AnagramChecker()

    @Test func classicEnglish() {
        #expect(checker.isAnagram(Phrase(text: "silent"), of: Phrase(text: "listen")))
    }

    @Test func ignoresSpacesCaseAndAccents() {
        #expect(checker.isAnagram(Phrase(text: "Roma è"), of: Phrase(text: "amore")))
    }

    @Test func rejectsDifferentLetters() {
        #expect(!checker.isAnagram(Phrase(text: "hello"), of: Phrase(text: "world")))
    }

    @Test func rejectsIdenticalPhrase() {
        #expect(!checker.isAnagram(Phrase(text: "listen"), of: Phrase(text: "listen")))
    }
}
