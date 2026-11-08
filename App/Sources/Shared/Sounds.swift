import AVFoundation

/// The countdown's ticks, synthesized: short tones with a quick decay. Playback only: the
/// app never records anything.
@MainActor
final class Sounds {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

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

    private lazy var tickBuffer = tick(880)          // A5
    private lazy var urgentTickBuffer = tick(1318.5) // E6: the last seconds

    /// One second less; `urgent` for the very last ones (higher).
    func playTick(urgent: Bool) { play(urgent ? urgentTickBuffer : tickBuffer) }

    /// -mute: no sounds (UI tests: a simulator's failing audio blocks the app for seconds).
    private static let isMuted = CommandLine.arguments.contains("-mute")

    private func play(_ buffer: AVAudioPCMBuffer?) {
        guard let buffer, !Self.isMuted else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            guard setUp() else { return }
            if !engine.isRunning { try engine.start() }
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            if !player.isPlaying { player.play() }
        } catch {
            // no sound is no harm
        }
    }

    /// A short wooden "tock": a tone that dies away in a tenth of a second.
    private func tick(_ frequency: Double) -> AVAudioPCMBuffer? {
        let seconds = 0.1
        let count = AVAudioFrameCount(seconds * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = count
        for i in 0..<Int(count) {
            let t = Double(i) / format.sampleRate
            let attack = min(t / 0.002, 1)
            let v = attack * exp(-45 * t) * (sin(2 * .pi * frequency * t) + 0.3 * sin(2 * .pi * frequency * 2.01 * t))
            samples[i] = Float(0.5 * v * min(1, (seconds - t) / 0.01))
        }
        return buffer
    }
}
