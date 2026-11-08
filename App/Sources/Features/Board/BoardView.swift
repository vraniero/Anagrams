import SwiftUI
import AnagramEngine
import AnagramModels

/// The sentence on top; tap or drag its blocks down to build the anagram, then Check.
/// Tap a block below (or drag it back up) to return it. Drag blocks below to reorder them.
///
/// Dragging is a plain drag gesture (no long press, nothing scrolls): the block follows the
/// finger and lands where it's released.
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
    private let space = "board"

    var body: some View {
        @Bindable var session = session
        FittingBlocks(longestWord: session.board.source.words.map(\.blocks.count).max() ?? 0) {
            VStack(spacing: 0) {
                if let header {
                    header
                    Divider()
                }
                tray
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .measure(Area.tray, into: $frames, space: space)

                Divider()

                candidate
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.opacity(isOverCandidate ? 0.12 : 0.05))
                    .measure(Area.candidate, into: $frames, space: space)

                marks
                    .padding(.horizontal)
                    .padding(.top, 10)
                accents
                    .padding(.horizontal)
                    .padding(.top, 6)

                controls
                    .padding()
            }
            .coordinateSpace(.named(space))
            .overlay { floatingBlock }
        }
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

    /// How blocks move: a little bounce when they land.
    static let move = Animation.spring(duration: 0.5, bounce: 0.3)

    private var isOverCandidate: Bool {
        drag.map { frames[Area.candidate]?.contains($0.location) == true } ?? false
    }

    // MARK: areas

    /// The spoken sentence; used blocks leave an empty slot.
    private var tray: some View {
        let unused = Set(session.board.tray.map(\.id))
        return FlowLayout(spacing: BlockMetrics.wordSpacing) {
            ForEach(session.board.source.words) { word in
                WordBlocks {
                    ForEach(word.blocks) { block in
                        if unused.contains(block.id) {
                            movable(block) { session.board.place(block.id) }
                        } else {
                            EmptySlotView()
                        }
                    }
                }
            }
            if session.isProcessing {
                WorkingTiles()  // words said just before "Make anagram", still coming
            }
        }
    }

    /// The words being built. The last word (tinted) is where tapped blocks go.
    private var candidate: some View {
        let words = session.board.words
        return FlowLayout(spacing: BlockMetrics.wordSpacing) {
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
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(w == words.count - 1 ? Color.accentColor.opacity(0.08) : .clear)
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
            .gesture(
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
        VStack(spacing: 12) {
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

            HStack {
                let leading = leading ?? BoardAction(title: "New sentence", symbol: "mic") { session.restart() }
                Button(leading.title, systemImage: leading.symbol, action: leading.action)
                    .buttonStyle(.bordered)
                Spacer()
                Button {
                    Task {
                        if let onCheck { await onCheck() } else { await session.check() }
                    }
                } label: {
                    if session.isChecking { ProgressView() } else { Label("Check", systemImage: "checkmark.seal") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.board.candidate.words.isEmpty || session.isChecking)
            }
        }
    }
}

extension BoardView {
    /// Punctuation marks: as many as you like, they don't count as letters.
    private var marks: some View {
        HStack(spacing: 6) {
            ForEach(Word.marks, id: \.self) { mark in
                Button {
                    withAnimation(Self.move) { session.board.addMark(mark) }
                } label: {
                    Text(String(mark))
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Color(red: 0.42, green: 0.47, blue: 0.56).opacity(0.15),
                                    in: .rect(cornerRadius: 8, style: .continuous))
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
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(on ? Color.accentColor : Color.accentColor.opacity(0.12),
                                    in: .rect(cornerRadius: 8, style: .continuous))
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
    /// Records this view's frame in the named coordinate space.
    func measure(_ key: AnyHashable, into frames: Binding<[AnyHashable: CGRect]>, space: String) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { frames.wrappedValue[key] = $0 }
    }
}
