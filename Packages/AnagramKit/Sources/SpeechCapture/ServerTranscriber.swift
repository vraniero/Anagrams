#if os(iOS)
import AVFoundation
import Foundation

/// Streams the microphone to the backend's `/listen` (Whisper on the Mac, see backend/)
/// and hands back each utterance with the language it was spoken in.
/// Ported from Etymon's ConversationStream.
public final class ServerTranscriber: SpeechTranscriber, @unchecked Sendable {
    public enum TranscriberError: LocalizedError {
        case denied, noMicrophone, badURL, serverLost(String)
        public var errorDescription: String? {
            switch self {
            case .denied: "Microphone access is off: allow it in Settings."
            case .noMicrophone: "No microphone available."
            case .badURL: "The server address isn't valid."
            case .serverLost(let reason): "Lost the server: \(reason)"
            }
        }
    }

    public static let sampleRate = 16_000.0
    private let baseURL: URL
    private let engine = AVAudioEngine()
    private let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate,
                                       channels: 1, interleaved: true)!
    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?
    private var converter: AVAudioConverter?
    private var continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation?
    /// Audio is only sent from this moment: after the server is ready and the start chime
    /// has played, so the chime isn't transcribed.
    private var sendFrom: Date = .distantFuture
    private let holdAfterReady: TimeInterval

    /// `holdAfterReady`: seconds of audio not sent once the server is ready (a start sound).
    public init(baseURL: URL = ServerSettings.baseURL, holdAfterReady: TimeInterval = 0) {
        self.baseURL = baseURL
        self.holdAfterReady = holdAfterReady
    }

    public func start() async throws -> AsyncThrowingStream<TranscriptEvent, Error> {
        guard await AVAudioApplication.requestRecordPermission() else { throw TranscriberError.denied }
        guard let url = ServerSettings.listenURL(base: baseURL) else { throw TranscriberError.badURL }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw TranscriberError.noMicrophone }

        let (stream, continuation) = AsyncThrowingStream<TranscriptEvent, Error>.makeStream()
        let task = URLSession.shared.webSocketTask(with: url)
        lock.withLock {
            self.task = task
            self.continuation = continuation
            sendFrom = .distantFuture
            converter = AVAudioConverter(from: format, to: target)
        }
        continuation.onTermination = { [weak self] _ in self?.cancel() }
        task.resume()
        receive(task)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.send(buffer)
        }
        engine.prepare()
        try engine.start()
        return stream
    }

    public func finish() {
        stopMicrophone()
        command(["type": "finish"])  // the server answers "done" once everything is transcribed
    }

    public func cancel() {
        stopMicrophone()
        let (task, continuation) = lock.withLock { () -> (URLSessionWebSocketTask?, AsyncThrowingStream<TranscriptEvent, Error>.Continuation?) in
            defer { self.task = nil; self.continuation = nil }
            return (self.task, self.continuation)
        }
        task?.cancel(with: .goingAway, reason: nil)
        continuation?.finish()
    }

    private func stopMicrophone() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        lock.withLock { converter = nil }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func command(_ body: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let text = String(data: data, encoding: .utf8) else { return }
        lock.withLock { task }?.send(.string(text)) { _ in }
    }

    // MARK: audio out

    private func send(_ buffer: AVAudioPCMBuffer) {
        let (task, converter, sendFrom) = lock.withLock { (self.task, self.converter, self.sendFrom) }
        guard let task, let converter, Date() >= sendFrom else { return }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        nonisolated(unsafe) var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let samples = out.int16ChannelData else { return }
        task.send(.data(Data(bytes: samples[0], count: Int(out.frameLength) * 2))) { _ in }
    }

    // MARK: events in

    private func receive(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self, self.lock.withLock({ self.task === task }) else { return }
            switch result {
            case .success(let message):
                let data: Data? = switch message {
                case .string(let text): text.data(using: .utf8)
                case .data(let bytes): bytes
                @unknown default: nil
                }
                switch data.flatMap(Self.decode) {
                case .event(let event):
                    if event == .ready {
                        self.lock.withLock { self.sendFrom = Date().addingTimeInterval(self.holdAfterReady) }
                    }
                    self.yield(event)
                case .done: self.cancel(); return
                case nil: break
                }
                self.receive(task)
            case .failure(let error):
                let continuation = self.lock.withLock { self.continuation }
                continuation?.finish(throwing: TranscriberError.serverLost(error.localizedDescription))
                self.cancel()
            }
        }
    }

    private func yield(_ event: TranscriptEvent) {
        _ = lock.withLock { continuation }?.yield(event)
    }

    enum Message: Equatable { case event(TranscriptEvent), done }

    static func decode(_ data: Data) -> Message? {
        struct Kind: Decodable { let type: String }
        let decoder = JSONDecoder()
        guard let kind = try? decoder.decode(Kind.self, from: data) else { return nil }
        switch kind.type {
        case "ready": return .event(.ready)
        case "speech": return .event(.speechStarted)
        case "silence": return .event(.speechEnded)
        case "transcribing": return .event(.transcribing)
        case "discarded": return .event(.discarded)
        case "utterance": return (try? decoder.decode(Utterance.self, from: data)).map { .event(.utterance($0)) }
        case "done": return .done
        default: return nil
        }
    }
}
#endif
