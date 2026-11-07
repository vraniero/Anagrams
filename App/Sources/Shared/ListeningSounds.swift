import AVFoundation

/// Two short chimes: rising when the app starts listening, falling when it stops.
/// Synthesized (adapted from Etymon's Chimes): soft tones with a quick decay.
@MainActor
final class ListeningSounds {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private lazy var startBuffer = notes([523.25, 783.99])  // C5 → G5
    private lazy var stopBuffer = notes([783.99, 523.25])   // G5 → C5

    /// How long a chime lasts: audio heard meanwhile isn't sent, so it isn't taken for speech.
    static let duration = 0.45

    private var isSetUp = false

    /// Wired up on first use, not at init: a device without audio output then never touches it.
    private func setUp() -> Bool {
        if isSetUp { return true }
        guard engine.outputNode.outputFormat(forBus: 0).sampleRate > 0 else { return false }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.5
        isSetUp = true
        return true
    }

    func playStart() { play(startBuffer) }
    func playStop() { play(stopBuffer) }

    private func play(_ buffer: AVAudioPCMBuffer?) {
        guard let buffer else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            if session.category != .playAndRecord {
                try session.setCategory(.playback, options: [.mixWithOthers])
            }
            try session.setActive(true)
            guard setUp() else { return }
            if !engine.isRunning { try engine.start() }
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            if !player.isPlaying { player.play() }
        } catch {
            // no sound is no harm
        }
    }

    /// Notes one after another, each a soft tone with a little octave shimmer.
    private func notes(_ frequencies: [Double]) -> AVAudioPCMBuffer? {
        let step = 0.13
        let seconds = Self.duration
        let count = AVAudioFrameCount(seconds * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = count
        for i in 0..<Int(count) {
            let t = Double(i) / format.sampleRate
            var v = 0.0
            for (n, f) in frequencies.enumerated() {
                let u = t - Double(n) * step
                guard u >= 0 else { continue }
                let attack = min(u / 0.01, 1)
                v += attack * exp(-9 * u) * (sin(2 * .pi * f * u) + 0.25 * sin(4 * .pi * f * u))
            }
            let fadeOut = min(1, (seconds - t) / 0.04)
            samples[i] = Float(0.4 * v * fadeOut)
        }
        return buffer
    }
}
