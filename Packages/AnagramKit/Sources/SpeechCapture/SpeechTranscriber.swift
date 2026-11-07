import Foundation

/// Something heard: an utterance's text and the language it was spoken in.
public struct Utterance: Decodable, Equatable, Sendable {
    public let id: Int
    public let lang: String?
    public let start: Double
    public let end: Double
    public let text: String

    public init(id: Int, lang: String?, start: Double, end: Double, text: String) {
        self.id = id; self.lang = lang; self.start = start; self.end = end; self.text = text
    }
}

public enum TranscriptEvent: Equatable, Sendable {
    /// The recognizer is loaded and listening.
    case ready
    case speechStarted
    case speechEnded
    /// A stretch of speech is being transcribed: its words (or `.discarded`) will follow.
    case transcribing
    /// That stretch had no words in it after all (a cough, a door).
    case discarded
    case utterance(Utterance)
}

/// Streams live speech as utterances, each with its detected language.
public protocol SpeechTranscriber: AnyObject, Sendable {
    /// Starts listening. The stream ends after `finish()` once pending speech is transcribed,
    /// or throws if listening fails.
    func start() async throws -> AsyncThrowingStream<TranscriptEvent, Error>
    /// Stops the microphone; what was already said is still transcribed, nothing after it.
    func finish()
    /// Stops at once and drops anything pending.
    func cancel()
}
