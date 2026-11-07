import Testing
import AnagramEngine
import SpeechCapture
@testable import Anagrams

@MainActor
struct GameSessionTests {
    func listened(_ script: [Utterance] = DemoTranscriber.sample) async throws -> GameSession {
        let session = GameSession(transcriber: DemoTranscriber(script: script, delay: .milliseconds(1)),
                                  validator: WordListValidator(["en": ["listen", "silent"], "it": ["amore", "roma"]]))
        session.startListening()
        for _ in 0..<200 where session.isListening { try await Task.sleep(for: .milliseconds(5)) }
        return session
    }

    @Test func utterancesBecomeBlocksInTheirLanguage() async throws {
        let session = try await listened()
        #expect(session.stage == .listening)
        #expect(session.source.text == "Listen Roma è")
        #expect(session.source.languageCodes == ["en", "it"])
    }

    @Test func buildAndCheckAnAnagram() async throws {
        let session = try await listened([Utterance(id: 1, lang: "en", start: 0, end: 1, text: "Listen")])
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
        let session = try await listened([])
        session.type("  ")
        #expect(session.source.words.isEmpty)
        session.type("Il gatto dorme sul divano tutto il giorno")
        #expect(session.source.words.count == 8)
        #expect(session.source.languageCodes == ["it"])
        session.clearSentence()
        #expect(session.source.words.isEmpty)
    }

    @Test func restartClearsEverything() async throws {
        let session = try await listened()
        session.makeAnagram()
        session.restart()
        #expect(session.stage == .listening && session.source.words.isEmpty && session.board.tray.isEmpty)
    }
}
