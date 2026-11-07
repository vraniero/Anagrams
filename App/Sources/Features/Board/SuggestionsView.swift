import SwiftUI
import AnagramEngine

/// Possible anagrams of the sentence; tap one to lay it out on the board.
struct SuggestionsView: View {
    /// nil while still looking.
    let suggestions: [Suggestion]?
    let use: (Suggestion) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let suggestions, suggestions.isEmpty {
                    ContentUnavailableView("No anagrams found", systemImage: "lightbulb.slash",
                                           description: Text("Try rearranging it yourself, or a shorter sentence."))
                } else if let suggestions {
                    List(suggestions) { suggestion in
                        Button {
                            use(suggestion)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(suggestion.text.lowercased())
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(zip(suggestion.words, suggestion.languages)
                                    .map { "\($0.0.lowercased()): \(languageName($0.1) ?? $0.1)" }
                                    .joined(separator: " · "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 14) {
                        WorkingTiles()
                        Text("Looking for anagrams…").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Suggestions")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
