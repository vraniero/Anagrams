import Foundation
import Testing
import AnagramModels
@testable import SpeechCapture

struct PhraseBuildingTests {
    @Test func utterancesAppendWithTheirLanguageAndDropPunctuation() {
        var phrase = Phrase()
        phrase.append(text: "Listen, — now!", languageCode: "en")
        phrase.append(text: "Roma è", languageCode: "it")
        #expect(phrase.text == "Listen now Roma è")
        #expect(phrase.words.map(\.languageCode) == ["en", "en", "it", "it"])
        #expect(phrase.languageCodes == ["en", "it"])
    }
}

struct ServerSettingsTests {
    @Test func listenURLSwitchesToWebSocketScheme() {
        #expect(ServerSettings.listenURL(base: URL(string: "http://192.168.1.2:8000")!)?.absoluteString
                == "ws://192.168.1.2:8000/listen")
        #expect(ServerSettings.listenURL(base: URL(string: "https://example.com")!)?.absoluteString
                == "wss://example.com/listen")
    }
}

#if os(iOS)
struct ServerMessageTests {
    func decode(_ json: String) -> ServerTranscriber.Message? {
        ServerTranscriber.decode(Data(json.utf8))
    }

    @Test func decodesTheListenProtocol() {
        #expect(decode(#"{"type":"ready"}"#) == .event(.ready))
        #expect(decode(#"{"type":"speech","start":1.2}"#) == .event(.speechStarted))
        #expect(decode(#"{"type":"silence","end":2.4}"#) == .event(.speechEnded))
        #expect(decode(#"{"type":"done"}"#) == .done)
        #expect(decode(#"{"type":"transcribing","start":1.2}"#) == .event(.transcribing))
        #expect(decode(#"{"type":"discarded","start":1.2}"#) == .event(.discarded))
        #expect(decode(#"{"type":"utterance","id":3,"lang":"it","start":1.0,"end":2.5,"text":"Roma è"}"#)
                == .event(.utterance(Utterance(id: 3, lang: "it", start: 1, end: 2.5, text: "Roma è"))))
        #expect(decode(#"{"type":"unknown"}"#) == nil)
    }
}
#endif
