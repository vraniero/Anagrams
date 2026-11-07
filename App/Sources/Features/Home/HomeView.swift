import SwiftUI

enum Destination: Hashable { case training, game, help, clock, duel }

/// The first screen: the title in cream tiles inside the circling arrows, over the moving
/// night sky, and the menu.
struct HomeView: View {
    var body: some View {
        ZStack {
            IconBackground()
            VStack(spacing: 0) {
                Spacer(minLength: 20)
                AnimatedTitle()
                Spacer(minLength: 20)
                VStack(spacing: 14) {
                    MenuLink(.training, title: "Training", subtitle: "Say or type a sentence, make it an anagram",
                             symbol: "graduationcap.fill")
                    MenuLink(.game, title: "Game", subtitle: "Against the clock, or two players", symbol: "gamecontroller.fill")
                    MenuLink(.help, title: "Help", subtitle: "How it works", symbol: "questionmark.circle.fill")
                }
                .padding(.horizontal, 24)
                ListeningMic()
                    .padding(.vertical, 24)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// "ANA / GRAMS" as tiles that drop in one after another, then sway like the icon's.
private struct AnimatedTitle: View {
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let rows = [Array("ANA"), Array("GRAMS")]
    private let tilt: [Double] = [-5, 3, -3, 4, -4, 2, -2, 5]

    var body: some View {
        ZStack {
            CirclingArrows()
                .frame(width: 330, height: 250)
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                VStack(spacing: 4) {
                    ForEach(rows.indices, id: \.self) { row in
                        HStack(spacing: 4) {
                            ForEach(rows[row].indices, id: \.self) { col in
                                let n = row * 3 + col
                                CreamTile(letter: rows[row][col], size: 58)
                                    .rotationEffect(.degrees(tilt[n] + (reduceMotion ? 0 : 1.5 * sin(t * 1.1 + Double(n)))))
                                    .offset(y: reduceMotion ? 0 : 2.5 * sin(t * 1.4 + Double(n) * 0.7))
                                    .offset(y: landed ? 0 : -500)
                                    .animation(.spring(duration: 0.7, bounce: 0.35).delay(Double(n) * 0.07), value: landed)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Anagrams")
        .accessibilityAddTraits(.isHeader)
        .onAppear { landed = true }
    }
}

/// The microphone from the bottom of the icon, its sound waves pulsing.
private struct ListeningMic: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wave.3.left")
                .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
            Image(systemName: "mic.fill")
                .foregroundStyle(Theme.cream)
            Image(systemName: "wave.3.right")
                .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
        }
        .font(.system(size: 34))
        .foregroundStyle(Theme.glow)
        .accessibilityHidden(true)
    }
}

struct MenuLink: View {
    let destination: Destination
    let title: String
    let subtitle: String
    let symbol: String

    init(_ destination: Destination, title: String, subtitle: String, symbol: String) {
        self.destination = destination
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
    }

    var body: some View {
        NavigationLink(value: destination) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 48, height: 48)
                    .background(Theme.cream, in: .rect(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title3.weight(.bold))
                    Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.glowLight)
            }
            .foregroundStyle(.white)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.navyDeep.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [Theme.glowLight.opacity(0.8), Theme.glow.opacity(0.2)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing),
                                          lineWidth: 1.5)
                    )
                    .shadow(color: Theme.glow.opacity(0.35), radius: 12)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

/// Sinks a little under the finger.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}
