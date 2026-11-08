import SwiftUI

/// The colours of the app icon: a deep navy night, glowing blue arrows, cream tiles.
enum Theme {
    static let navyDeep = Color(red: 0.03, green: 0.08, blue: 0.22)
    static let navy = Color(red: 0.07, green: 0.18, blue: 0.45)
    static let glow = Color(red: 0.30, green: 0.62, blue: 1.0)
    static let glowLight = Color(red: 0.60, green: 0.84, blue: 1.0)
    static let cream = Color(red: 0.97, green: 0.92, blue: 0.82)
    static let creamShade = Color(red: 0.80, green: 0.71, blue: 0.55)
    static let ink = Color(red: 0.07, green: 0.07, blue: 0.10)

    static var night: LinearGradient {
        LinearGradient(colors: [navy, navyDeep], startPoint: .top, endPoint: .bottom)
    }
}

/// A cream letter tile like the icon's: a lit face on a darker side, with a soft shadow.
struct CreamTile: View {
    let letter: Character
    var size: CGFloat = 56

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
        let depth = size * 0.08
        ZStack(alignment: .top) {
            shape
                .fill(Theme.creamShade)
                .shadow(color: .black.opacity(0.45), radius: size * 0.12, y: size * 0.08)
            shape
                .fill(LinearGradient(colors: [.white.mix(with: Theme.cream, by: 0.6), Theme.cream],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    Text(String(letter))
                        .font(.system(size: size * 0.58, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                .frame(height: size - depth)
        }
        .frame(width: size, height: size)
    }
}

/// A raised button, like a big tile: a lit face on a darker side, which sinks when pressed.
struct Raised3DButtonStyle: ButtonStyle {
    var color: Color = Theme.glow
    @Environment(\.isEnabled) private var isEnabled

    private let depth: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let tint = isEnabled ? color : Color(white: 0.45)
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        configuration.label
            .font(.title3.weight(.heavy))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.65))
            .shadow(color: .black.opacity(0.3), radius: 0, y: -1)
            .padding(.horizontal, 34)
            .padding(.vertical, 15)
            .background {
                shape
                    .fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.3), tint],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0)],
                                                               startPoint: .top, endPoint: .center),
                                                lineWidth: 1))
            }
            .offset(y: pressed ? depth - 1 : 0)
            .background {
                // the side: stays put while the face sinks onto it
                shape
                    .fill(tint.mix(with: .black, by: 0.45))
                    .offset(y: depth)
                    .shadow(color: .black.opacity(isEnabled ? 0.4 : 0.15), radius: 8, y: depth + 4)
            }
            .padding(.bottom, depth)
            .animation(.spring(duration: 0.18), value: pressed)
            .sensoryFeedback(.impact(weight: .medium), trigger: pressed) { _, new in new }
    }
}

/// -still: the moving backgrounds hold still (UI tests: a busy simulator draws them on the CPU,
/// and the tests then can't read the screen in time).
enum Motion {
    static let isStill = CommandLine.arguments.contains("-still")
}
