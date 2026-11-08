import SwiftUI
import AnagramModels

enum BlockMetrics {
    static let maxSize: CGFloat = 44
    static let minSize: CGFloat = 26
    static let gap: CGFloat = 4
    static let wordSpacing: CGFloat = 14

    /// The biggest block that fits the longest word on one line of `width`.
    static func size(longestWord: Int, width: CGFloat, maxSize: CGFloat = maxSize) -> CGFloat {
        guard longestWord > 0, width > 0 else { return maxSize }
        let fit = (width - gap * CGFloat(longestWord - 1)) / CGFloat(longestWord)
        return min(maxSize, max(minSize, fit.rounded(.down)))
    }

    /// Smaller blocks for long sentences, so the board still fits on screen.
    static func maxSize(letters: Int) -> CGFloat {
        switch letters {
        case ..<28: maxSize
        case ..<45: 38
        default: 32
        }
    }
}

extension EnvironmentValues {
    @Entry var blockSize: CGFloat = BlockMetrics.maxSize
}

/// A letter tile with some depth: a lit, slightly domed face sitting on a darker side,
/// casting a soft shadow. It still takes exactly `size` × `size` so layouts don't change.
struct LetterBlockView: View {
    let block: LetterBlock
    @Environment(\.blockSize) private var size

    private var depth: CGFloat { max(3, size * 0.1) }
    private var radius: CGFloat { size * 0.22 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // punctuation marks the player adds are slate tiles, letters blue
        let tile = block.character.isLetter ? Color.accentColor : Color(red: 0.42, green: 0.47, blue: 0.56)
        ZStack(alignment: .top) {
            // the side of the tile, peeking out below the face
            shape
                .fill(tile.mix(with: .black, by: 0.4))
                .shadow(color: .black.opacity(0.3), radius: size * 0.08, y: size * 0.06)
            // the face: lit from above
            shape
                .fill(LinearGradient(colors: [tile.mix(with: .white, by: 0.35), tile],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0)],
                                                      startPoint: .top, endPoint: .center),
                                       lineWidth: 1)
                )
                .overlay {
                    Text(String(block.character).uppercased())
                        .font(.system(size: size * 0.52, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 0, y: -0.75)  // pressed into the face
                        .minimumScaleFactor(0.5)
                }
                .frame(height: size - depth)
        }
        .frame(width: size, height: size)
        .contentShape(.rect)
    }
}

/// How far a block is off the board: 0 at rest, 1 picked up (bigger, tipped toward you, with
/// a longer shadow). Landing animates it from 1 to 0.
struct Lifted: ViewModifier {
    var amount: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(1 + 0.22 * amount)
            .rotation3DEffect(.degrees(-28 * amount), axis: (x: 1, y: 0, z: 0), perspective: 0.7)
            .shadow(color: .black.opacity(0.25 * amount), radius: 10 * amount, y: 8 * amount)
    }
}

extension AnyTransition {
    /// A block arriving from above: it lands tipped and lifted, and settles flat.
    static var landing: AnyTransition {
        .asymmetric(insertion: .modifier(active: Lifted(amount: 1), identity: Lifted(amount: 0)),
                    removal: .opacity)
    }
}

/// Where a block was before it moved down, or where the next one goes.
struct EmptySlotView: View {
    @Environment(\.blockSize) private var size

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.2)
            .strokeBorder(.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(width: size, height: size)
    }
}

/// The blocks of one word, wrapping onto a second line only if it can't fit even at the
/// smallest block size.
struct WordBlocks<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        FlowLayout(spacing: BlockMetrics.gap, lineSpacing: BlockMetrics.gap) { content }
    }
}

/// Measures the width it's given and sizes the blocks inside to fit the longest word.
struct FittingBlocks<Content: View>: View {
    let longestWord: Int
    var maxSize: CGFloat = BlockMetrics.maxSize
    @ViewBuilder var content: Content
    @State private var width: CGFloat = 0

    var body: some View {
        content
            .environment(\.blockSize, BlockMetrics.size(longestWord: longestWord, width: width, maxSize: maxSize))
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// A phrase as wrapping lines of letter blocks (the sentence being written).
struct PhraseBlocksView: View {
    let phrase: Phrase

    var body: some View {
        FittingBlocks(longestWord: phrase.words.map(\.blocks.count).max() ?? 0) {
            FlowLayout(spacing: BlockMetrics.wordSpacing) {
                ForEach(phrase.words) { word in
                    WordBlocks { ForEach(word.blocks) { LetterBlockView(block: $0).transition(.landing) } }
                }
            }
        }
        .animation(.spring, value: phrase)
    }
}
