import SwiftUI
import AnagramEngine

/// Game → choose a mode.
struct GameModesView: View {
    var body: some View {
        ThemedScreen {
            VStack(spacing: 14) {
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { CreamTile(letter: Array("PLAY")[$0], size: 54) }
                }
                .padding(.bottom, 24)
                MenuLink(.clock, title: "Against the clock",
                         subtitle: "\(Int(ClockRound.duration)) seconds: as many words as you can", symbol: "timer")
                MenuLink(.duel, title: "Multiplayer",
                         subtitle: "2 to 4 players: write a sentence, the next one makes the anagram",
                         symbol: "person.3.fill")
            }
            .padding(.horizontal, 24)
        }
        .navigationTitle("Game")
    }
}

/// The icon's moving night sky behind some content, with a light navigation bar.
struct ThemedScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            IconBackground()
            content
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

/// A big cream button, like a tile.
struct CreamButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.bold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(Theme.cream, in: .capsule)
            .shadow(color: .black.opacity(0.35), radius: 6, y: 4)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// Seconds left, counting down by itself, and a bar that empties. The last seconds tick
/// out loud, higher for the final few.
struct Countdown: View {
    let start: Date
    let end: Date
    @State private var sounds = ListeningSounds()

    static let tickingSeconds = 15
    static let urgentSeconds = 5

    var body: some View {
        VStack(spacing: 6) {
            Label {
                Text(timerInterval: min(Date.now, end)...end, countsDown: true)
                    .monospacedDigit()
            } icon: {
                Image(systemName: "timer")
            }
            .font(.title2.weight(.bold))
            ProgressView(timerInterval: start...end, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(Theme.glow)
        }
        .task(id: end) { await tick() }
    }

    /// A tick as each of the last seconds begins (15, 14, … 1 left); stops when the
    /// countdown goes away (time's up, solved, stopped).
    private func tick() async {
        for left in stride(from: Self.tickingSeconds, through: 1, by: -1) {
            let wait = end.addingTimeInterval(-Double(left)).timeIntervalSinceNow
            if wait < -0.25 { continue }  // already past (joined late)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            sounds.playTick(urgent: left <= Self.urgentSeconds)
        }
    }
}

/// Points as a number that rolls when it changes.
struct ScoreLabel: View {
    let name: String?
    let points: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if let name { Text(name).font(.caption).foregroundStyle(.secondary) }
            Text("\(points)")
                .font(.title2.weight(.heavy))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(points)))
                .animation(.snappy, value: points)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name ?? "Score") \(points) points")
    }
}

func languageName(_ code: String?) -> String? {
    code.flatMap { Locale.current.localizedString(forLanguageCode: $0)?.capitalized ?? $0.uppercased() }
}

/// "English", or "Italian + English" for words in several languages.
func languageNames(_ codes: [String]) -> String {
    var seen = Set<String>()
    return codes.filter { seen.insert($0).inserted }.compactMap(languageName).joined(separator: " + ")
}
