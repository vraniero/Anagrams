import Testing
import AnagramEngine
@testable import Anagrams

@MainActor
struct GameSessionTests {
    /// A session with a small dictionary and, optionally, a sentence already written.
    func makeSession(_ sentences: [(String, String)] = [("Listen", "en"), ("Roma è", "it")]) -> GameSession {
        let session = GameSession(validator: WordListValidator(["en": ["listen", "silent"], "it": ["amore", "roma"]]))
        for (text, language) in sentences { session.type(text, language: language) }
        return session
    }

    @Test func sentencesBecomeBlocksInTheirLanguage() {
        let session = makeSession()
        #expect(session.stage == .writing)
        #expect(session.source.text == "Listen Roma è")
        #expect(session.source.languageCodes == ["en", "it"])
    }

    @Test func buildAndCheckAnAnagram() async throws {
        let session = makeSession([("Listen", "en")])
        session.makeAnagram()
        #expect(session.stage == .building)
        for ch in "silent" {
            session.board.place(session.board.tray.first { $0.character.lowercased() == String(ch) }!.id)
        }
        await session.check()
        #expect(session.verdict?.isValid == true)
        #expect(session.verdict?.words.first?.language == "en")
    }

    @Test func typedSentencesAreAddedWithTheirLanguage() async throws {
        let session = makeSession([])
        session.type("  ")
        #expect(session.source.words.isEmpty)
        session.type("Il gatto dorme sul divano tutto il giorno")
        #expect(session.source.words.count == 8)
        #expect(session.source.languageCodes == ["it"])
        session.clearSentence()
        #expect(session.source.words.isEmpty)
    }

    @Test func typingShowsTilesAtOnceAndStopsAtTheLimit() async throws {
        let session = makeSession([])
        session.letterLimit = 10
        session.setDraft("The cat")
        #expect(session.source.words.map(\.text) == ["The", "cat"])
        #expect(session.lettersLeft == 4)
        let firstTile = session.source.words[0].blocks[0].id
        session.setDraft("The cat sleep on the sofa")   // only 10 letters go in, nothing after
        #expect(session.draft == "The cat slee")
        #expect(session.lettersLeft == 0)
        #expect(session.source.words[0].blocks[0].id == firstTile)  // tiles already there stay
        session.setDraft("The cat slee ")               // at the limit not even a space
        #expect(session.draft == "The cat slee")
        session.setDraft("The cat")                     // deleting gives letters back
        #expect(session.lettersLeft == 4 && session.source.words.count == 2)
    }

    @Test func restartClearsEverything() async throws {
        let session = makeSession()
        session.makeAnagram()
        session.restart()
        #expect(session.stage == .writing && session.source.words.isEmpty && session.board.tray.isEmpty)
    }
}
