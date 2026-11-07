import SwiftUI
import AnagramEngine

extension AnagramVerdict: @retroactive Identifiable {
    public var id: String { words.map(\.text).joined(separator: " ") + "\(problems)" }
}

/// Yes or no, with each word and the language it was found in.
struct VerdictView: View {
    let verdict: AnagramVerdict
    @Environment(\.dismiss) private var dismiss
    @Environment(GameSession.self) private var session

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: verdict.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(verdict.isValid ? .green : .red)
            Text(verdict.isValid ? "Yes! It's an anagram." : "Not yet")
                .font(.title.bold())

            if verdict.isValid { MeaningNote(meaning: session.meaning, isChecking: session.isCheckingMeaning) }

            ForEach(Array(verdict.problems.enumerated()), id: \.offset) { _, problem in
                Text(message(problem)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(verdict.words.enumerated()), id: \.offset) { _, word in
                    HStack {
                        Text(word.text.lowercased()).font(.title3.weight(.semibold))
                        Spacer()
                        if let language = word.language {
                            Text(name(of: language)).foregroundStyle(.secondary)
                            Image(systemName: "checkmark").foregroundStyle(.green)
                        } else {
                            Text("not a word").foregroundStyle(.secondary)
                            Image(systemName: "xmark").foregroundStyle(.red)
                        }
                    }
                }
            }
            .padding()
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))

            Button(verdict.isValid ? "Done" : "Keep trying") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func message(_ problem: AnagramVerdict.Problem) -> String {
        switch problem {
        case .lettersDiffer: "Use every letter exactly once."
        case .mixedLanguages: "All the words must be in the same language."
        case .sameAsSource: "That's the original sentence: rearrange the letters."
        case .unknownWords(let words):
            words.count == 1 ? "“\(words[0])” isn't a word in any language I know."
                             : "Some words aren't words in any language I know."
        }
    }

    private func name(of code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code
    }
}

/// Whether the anagram means something, as Apple Intelligence reads it.
struct MeaningNote: View {
    let meaning: Meaning?
    let isChecking: Bool

    var body: some View {
        Group {
            if isChecking {
                Label { Text("Checking the meaning…") } icon: { ProgressView() }
                    .foregroundStyle(.secondary)
            } else if let meaning {
                VStack(spacing: 4) {
                    Label(meaning.makesSense ? "It makes sense!" : "Real words, but no meaning together",
                          systemImage: meaning.makesSense ? "sparkles" : "text.word.spacing")
                        .font(.headline)
                        .foregroundStyle(meaning.makesSense ? Color.orange : .secondary)
                    Text(meaning.reading)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .animation(.snappy, value: isChecking)
        .accessibilityElement(children: .combine)
    }
}
