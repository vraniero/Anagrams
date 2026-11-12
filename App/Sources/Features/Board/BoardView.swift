import SwiftUI
import AnagramEngine
import AnagramModels

/// The sentence on top; tap or drag its blocks down to build the anagram, then Check.
/// Tap a block below (or drag it back up) to return it. Drag blocks below to reorder them.
///
/// Dragging is a plain drag gesture (no long press, nothing scrolls): the block follows the
/// finger and lands where it's released.
///
/// The two cards share the room by what they hold (`BoardFit`): one tile size for both, as
/// big as lets every tile show without scrolling. As letters move down the sentence card
/// shrinks and the anagram card grows. Punctuation and accents open from a key on the
/// anagram card.
struct BoardView: View {
    @Environment(GameSession.self) private var session

    /// The game modes put a timer and scores here.
    var header: AnyView? = nil
    /// Bottom-left button; training's is "New sentence".
    var leading: BoardAction? = nil
    /// What Check does; training shows the verdict.
    var onCheck: (() async -> Void)? = nil
    /// Off in multiplayer games: no hints while competing.
    var allowsSuggestions = true

    private struct Drag: Equatable {
        let block: LetterBlock
        var location: CGPoint
    }

    @State private var drag: Drag?
    @AppStorage(Options.suggestionsKey) private var suggestionsOn = true
    @State private var showsSuggestions = false
    @State private var suggestions: [Suggestion]?  // nil while looking
    @Namespace private var tiles  // a block moving between tray and anagram flies across
    @State private var frames: [AnyHashable: CGRect] = [:]  // areas, words and blocks, in "board" space
    @State private var area: CGSize = .zero  // room for the two cards
    @State private var showsMarks = false
    private let space = "board"

    var body: some View {
        @Bindable var session = session
        ZStack {
            IconBackground()
            VStack(spacing: 12) {
                if let header {
                    header
                        .background(Theme.navyDeep.opacity(0.88), in: .rect(cornerRadius: 22, style: .continuous))
                        .fixedSize(horizontal: false, vertical: true)
                }
                // the room left is measured on an empty space, so the cards sized from it
                // can't change it back
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { area = $0 }
                    .overlay(alignment: .top) { cards }
                controls
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .coordinateSpace(.named(space))
            .overlay { floatingBlock }
        }
        .environment(\.colorScheme, .dark)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: session.board)
        .sheet(item: $session.verdict) { verdict in
            VerdictView(verdict: verdict)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsSuggestions) {
            SuggestionsView(suggestions: suggestions) { picked in
                showsSuggestions = false
                withAnimation(Self.move) { session.board.arrange(picked.words) }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private enum Area: Hashable { case tray, candidate }

    /// Tile size and card heights for what's on the board now.
    private var fit: BoardFit.Result {
        let board = session.board
        let unused = Set(board.tray.map(\.id))
        let trayWords = board.source.words.map { $0.blocks.filter { unused.contains($0.id) }.count }.filter { $0 > 0 }
        var words = board.words.map(\.blocks.count)
        if words.isEmpty { words = [0] }
        words[words.count - 1] += 1  // the cursor slot
        return BoardFit.layout(tray: trayWords, candidate: words, in: area)
    }

    /// The sentence card, the arrow, and the anagram card, sized by `fit`.
    private var cards: some View {
        let fit = fit
        return VStack(spacing: BoardFit.cardSpacing) {
            card(tray, height: fit.tray)
                .boardCard(highlighted: false)
                .measure(Area.tray, into: $frames, space: space)
            Image(systemName: "chevron.compact.down")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.glowLight.opacity(0.6))
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity)
                .frame(height: BoardFit.arrowHeight)
                .overlay(alignment: .trailing) { marksKey }
            card(candidate, height: fit.candidate)
                .boardCard(highlighted: isOverCandidate)
                .measure(Area.candidate, into: $frames, space: space)
        }
        .environment(\.blockSize, fit.size)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(Self.move, value: fit)
    }

    /// A card's tiles, centred. They're sized to fit; only a sentence too long even for
    /// the smallest tiles scrolls.
    private func card(_ content: some View, height: CGFloat) -> some View {
        ScrollView {
            content
                .padding(BoardFit.padding)
                .frame(maxWidth: .infinity, minHeight: height)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    /// How blocks move: a little bounce when they land.
    static let move = Animation.spring(duration: 0.5, bounce: 0.3)

    private var isOverCandidate: Bool {
        drag.map { frames[Area.candidate]?.contains($0.location) == true } ?? false
    }

    // MARK: areas

    /// The letters of the sentence still to use, word by word; used ones leave no gap.
    @ViewBuilder private var tray: some View {
        let unused = Set(session.board.tray.map(\.id))
        let words = session.board.source.words.filter { $0.blocks.contains { unused.contains($0.id) } }
        if words.isEmpty {
            Label("All letters used", systemImage: "checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.glowLight.opacity(0.8))
        } else {
            FlowLayout(spacing: BlockMetrics.wordSpacing, lineSpacing: BoardFit.lineSpacing) {
                ForEach(words) { word in
                    WordBlocks {
                        ForEach(word.blocks.filter { unused.contains($0.id) }) { block in
                            movable(block) { session.board.place(block.id) }
                        }
                    }
                }
            }
            .animation(Self.move, value: session.board)
        }
    }

    /// The words being built. The last word (tinted) is where tapped blocks go.
    private var candidate: some View {
        let words = session.board.words
        return FlowLayout(spacing: BlockMetrics.wordSpacing, lineSpacing: BoardFit.lineSpacing) {
            ForEach(Array(words.enumerated()), id: \.element.id) { w, word in
                WordBlocks {
                    ForEach(word.blocks) { block in
                        movable(block) { session.board.remove(block.id) }
                            .measure(block.id, into: $frames, space: space)
                    }
                    if w == words.count - 1 {
                        EmptySlotView()  // the cursor: where the next block goes
                    }
                }
                .padding(BoardFit.wordPadding)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(w == words.count - 1 ? Theme.glow.opacity(0.14) : .clear)
                )
                .measure(word.id, into: $frames, space: space)
            }
        }
        .animation(Self.move, value: session.board)
    }

    /// A block that moves on tap and can be dragged anywhere on the board.
    private func movable(_ block: LetterBlock, onTap: @escaping () -> Void) -> some View {
        LetterBlockView(block: block)
            .opacity(drag?.block.id == block.id ? 0.25 : 1)
            // the same block in the tray and below shares an id, so a tap makes it fly over;
            // while dragged it drops out of the pair: it lands where the finger lets go
            .matchedGeometryEffect(id: drag?.block.id == block.id ? AnyHashable("dragged") : AnyHashable(block.id),
                                   in: tiles)
            .transition(.landing)
            .onTapGesture { withAnimation(Self.move) { onTap() } }
            // before the card's scrolling: a drag that starts on a tile moves the tile
            .highPriorityGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(space))
                    .onChanged { value in drag = Drag(block: block, location: value.location) }
                    .onEnded { value in
                        drop(block.id, at: value.location)
                        drag = nil
                    }
            )
    }

    @ViewBuilder private var floatingBlock: some View {
        if let drag {
            LetterBlockView(block: drag.block)
                .modifier(Lifted(amount: 1))
                .position(drag.location)
                .allowsHitTesting(false)
        }
    }

    // MARK: dropping

    private func drop(_ id: LetterBlock.ID, at point: CGPoint) {
        withAnimation(Self.move) {
            guard frames[Area.candidate]?.contains(point) == true else {
                session.board.remove(id)  // anywhere above the line: back to the tray
                return
            }
            let words = session.board.words
            if let w = words.indices.first(where: { frames[words[$0].id]?.insetBy(dx: -8, dy: -8).contains(point) == true }) {
                session.board.place(id, inWord: w, at: insertionIndex(in: words[w], at: point, moving: id))
            } else {
                session.board.place(id)  // elsewhere below: the end of the current word
            }
        }
    }

    /// How many of the word's blocks (not counting the one being moved) come before the point,
    /// reading line by line, left to right.
    private func insertionIndex(in word: Word, at point: CGPoint, moving id: LetterBlock.ID) -> Int {
        let slack = BlockMetrics.gap / 2
        return word.blocks.filter { $0.id != id }.filter { block in
            guard let f = frames[block.id] else { return false }
            let earlierLine = f.maxY + slack < point.y
            let sameLine = f.minY - slack...f.maxY + slack ~= point.y
            return earlierLine || (sameLine && f.midX < point.x)
        }.count
    }

    // MARK: controls

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Button("Space", systemImage: "space") { session.board.newWord() }
                    .disabled(session.board.words.last?.blocks.isEmpty ?? true)
                Spacer()
                if suggestionsOn && allowsSuggestions {
                    Button("Suggest", systemImage: "lightbulb", action: suggest)
                    Spacer()
                }
                Button("Clear", systemImage: "arrow.uturn.backward") {
                    withAnimation(Self.move) { session.board.clear() }
                }
                .disabled(session.board.candidate.words.isEmpty)
            }
            .buttonStyle(.bordered)
            .tint(Theme.glowLight)

            HStack(alignment: .center) {
                let leading = leading ?? BoardAction(title: "New sentence", symbol: "arrow.counterclockwise") { session.restart() }
                Button(leading.title, systemImage: leading.symbol, action: leading.action)
                    .buttonStyle(.bordered)
                    .tint(Theme.glowLight)
                Spacer()
                Button {
                    Task {
                        if let onCheck { await onCheck() } else { await session.check() }
                    }
                } label: {
                    if session.isChecking {
                        ProgressView().tint(.white).frame(minWidth: 90)
                    } else {
                        Label("Check", systemImage: "checkmark.seal.fill")
                    }
                }
                .buttonStyle(Raised3DButtonStyle())
                .disabled(session.board.candidate.words.isEmpty || session.isChecking)
            }
        }
    }
}

extension BoardView {
    /// The key on the anagram card that opens punctuation and accents.
    private var marksKey: some View {
        Button {
            showsMarks = true
        } label: {
            Text(",!?´")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .keycap(on: showsMarks)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Punctuation and accents")
        .popover(isPresented: $showsMarks, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
            VStack(spacing: 8) {
                marks
                accents
            }
            .padding(12)
            .frame(width: 340)
            .presentationCompactAdaptation(.popover)
            .presentationBackground(Theme.navyDeep)
            .environment(\.colorScheme, .dark)
        }
    }

    /// Punctuation marks: as many as you like, they don't count as letters.
    private var marks: some View {
        HStack(spacing: 6) {
            ForEach(Word.marks, id: \.self) { mark in
                Button {
                    withAnimation(Self.move) { session.board.addMark(mark) }
                } label: {
                    Text(String(mark))
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .keycap(on: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(String(mark))")
            }
        }
    }

    /// Accents, free like punctuation: on the anagram's last letter, tap again to take off.
    private var accents: some View {
        HStack(spacing: 6) {
            ForEach(AnagramBoard.accents, id: \.self) { accent in
                let on = session.board.hasAccent(accent)
                Button {
                    withAnimation(.snappy) { session.board.toggleAccent(accent) }
                } label: {
                    Text("\u{25CC}" + String(accent))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(.white)
                        .keycap(on: on)
                }
                .buttonStyle(.plain)
                .disabled(!session.board.canAccent(accent))
                .opacity(session.board.canAccent(accent) ? 1 : 0.35)
                .accessibilityLabel(Self.accentNames[accent] ?? "Accent")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    static let accentNames: [Character: String] = [
        "\u{301}": "Acute accent", "\u{300}": "Grave accent", "\u{302}": "Circumflex",
        "\u{308}": "Diaeresis", "\u{303}": "Tilde", "\u{327}": "Cedilla",
    ]

    private func suggest() {
        suggestions = nil
        showsSuggestions = true
        Task { suggestions = await session.suggestions() }
    }
}

struct BoardAction {
    let title: String
    let symbol: String
    let action: () -> Void
}

private extension View {
    /// A dark glass card with a glow edge, like the typing screen's; brighter while a block
    /// is dragged over it.
    func boardCard(highlighted: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return background(Theme.navyDeep.opacity(highlighted ? 0.95 : 0.88), in: shape)
            .overlay {
                shape.strokeBorder(Theme.glow.opacity(highlighted ? 0.9 : 0.35), lineWidth: highlighted ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: Theme.glow.opacity(0.35), radius: highlighted ? 18 : 0)
            .animation(.easeInOut(duration: 0.2), value: highlighted)
    }

    /// A small dark key for punctuation and accents; lit when it's on.
    func keycap(on: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return background(on ? AnyShapeStyle(Theme.glow) : AnyShapeStyle(Theme.navyDeep.opacity(0.85)), in: shape)
            .overlay(shape.strokeBorder(.white.opacity(on ? 0.5 : 0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 0, y: 2)
    }

    /// Records this view's frame in the named coordinate space.
    func measure(_ key: AnyHashable, into frames: Binding<[AnyHashable: CGRect]>, space: String) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { frames.wrappedValue[key] = $0 }
    }
}

/// Sizes the board: one tile size for both cards, the biggest that lets every tile show,
/// and each card's height from the tiles it holds. Mirrors `FlowLayout`/`WordBlocks`.
enum BoardFit {
    struct Result: Equatable {
        var size: CGFloat
        var tray: CGFloat
        var candidate: CGFloat
    }

    static let padding: CGFloat = 16
    static let lineSpacing: CGFloat = 10
    static let wordPadding: CGFloat = 4
    static let cardSpacing: CGFloat = 6
    static let arrowHeight: CGFloat = 30
    static let smallest: CGFloat = 20
    /// The empty sentence card ("All letters used").
    static let emptyTray: CGFloat = 48

    /// `tray`, `candidate`: letters per word (the anagram's words with their padding).
    static func layout(tray: [Int], candidate: [Int], in area: CGSize) -> Result {
        guard area.width > 0, area.height > 0 else {
            return Result(size: BlockMetrics.maxSize, tray: 120, candidate: 160)
        }
        let width = area.width - 2 * padding
        let room = area.height - arrowHeight - 2 * cardSpacing
        var size = BlockMetrics.maxSize
        func needs(_ s: CGFloat) -> (CGFloat, CGFloat) {
            let t = tray.isEmpty ? emptyTray : height(tray, size: s, width: width, pad: 0) + 2 * padding
            // the anagram card: at least room for a line more, to drop tiles on
            let c = height(candidate, size: s, width: width, pad: wordPadding) + 2 * padding + s
            return (t, c)
        }
        var (t, c) = needs(size)
        while t + c > room && size > smallest {
            size -= 1
            (t, c) = needs(size)
        }
        let trayHeight = min(t, max(emptyTray, room - c))
        return Result(size: size, tray: trayHeight, candidate: max(room - trayHeight, 0))
    }

    /// The height of words of `letters` tiles, wrapped into `width` like the board does.
    static func height(_ letters: [Int], size s: CGFloat, width: CGFloat, pad: CGFloat) -> CGFloat {
        let gap = BlockMetrics.gap
        var rows: [CGFloat] = []  // row heights
        var rowWidth: CGFloat = 0
        for n in letters where n > 0 {
            let perLine = max(1, Int((width - 2 * pad + gap) / (s + gap)))
            let lines = (n + perLine - 1) / perLine
            let w = CGFloat(min(n, perLine)) * (s + gap) - gap + 2 * pad
            let h = CGFloat(lines) * (s + gap) - gap + 2 * pad
            if rows.isEmpty || rowWidth + BlockMetrics.wordSpacing + w > width {
                rows.append(h)
                rowWidth = w
            } else {
                rows[rows.count - 1] = max(rows[rows.count - 1], h)
                rowWidth += BlockMetrics.wordSpacing + w
            }
        }
        guard !rows.isEmpty else { return 0 }
        return rows.reduce(0, +) + lineSpacing * CGFloat(rows.count - 1)
    }
}
