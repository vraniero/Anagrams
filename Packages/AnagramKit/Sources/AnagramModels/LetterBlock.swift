import Foundation

/// A single draggable letter tile.
public struct LetterBlock: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let character: Character

    public init(id: UUID = UUID(), character: Character) {
        self.id = id
        self.character = character
    }
}
