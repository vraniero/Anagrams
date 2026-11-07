import Foundation

/// Plays scripted utterances: for the simulator, previews and UI tests without a backend.
/// Use with the `-demo` launch argument.
public final class DemoTranscriber: SpeechTranscriber, @unchecked Sendable {
    private let script: [Utterance]
    private let delay: Duration
    private var task: Task<Void, Never>?

    public init(script: [Utterance] = DemoTranscriber.sample, delay: Duration = .milliseconds(800)) {
        self.script = script
        self.delay = delay
    }

    public static let sample = [
        Utterance(id: 1, lang: "en", start: 0, end: 1, text: "Listen,"),
        Utterance(id: 2, lang: "it", start: 1.5, end: 3, text: "Roma è"),
    ]

    public func start() async throws -> AsyncThrowingStream<TranscriptEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<TranscriptEvent, Error>.makeStream()
        let script = script, delay = delay
        task = Task {
            continuation.yield(.ready)
            for utterance in script {
                // like the server: heard, then (a moment later) its words
                continuation.yield(.transcribing)
                try? await Task.sleep(for: delay)
                if Task.isCancelled { break }
                continuation.yield(.utterance(utterance))
            }
            continuation.finish()
        }
        return stream
    }

    public func finish() { task?.cancel() }
    public func cancel() { task?.cancel() }
}
