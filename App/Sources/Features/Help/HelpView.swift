import SwiftUI

/// How the app works, on the icon's night background.
struct HelpView: View {
    private let steps: [(symbol: String, title: String, text: String)] = [
        ("mic.fill", "Choose a sentence",
         "Speak in any language: a chime tells you Anagrams is listening, shimmering tiles show it's writing down what you said, then every letter becomes a tile. You can also type, point the camera at something written, or tap Give me a sentence for one at Easy, Medium or Hard. In the games, type the sentence or read it with the camera."),
        ("arrow.down.circle.fill", "Make anagram",
         "Tap Make anagram when the sentence is ready. A second chime: listening stops, no more words come in."),
        ("hand.draw.fill", "Move the tiles down",
         "Tap a tile to add it to your anagram, or drag it exactly where you want it. Space starts a new word; tap a tile below to send it back. Punctuation marks are free: add as many as you like. Stuck? Suggest shows possible anagrams."),
        ("checkmark.seal.fill", "Check",
         "Use every letter, then Check. Each word is looked up in all the languages on your iPhone and shown with its language. In Options you can require all the words to be in one language, and turn suggestions off. In Multiplayer, the time, rounds, languages and scoring are chosen before the game starts."),
    ]

    var body: some View {
        ZStack {
            IconBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(steps.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 14) {
                            CreamTile(letter: Character(String(i + 1)), size: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Label(steps[i].title, systemImage: steps[i].symbol)
                                    .font(.headline)
                                    .foregroundStyle(Theme.glowLight)
                                Text(steps[i].text)
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.navyDeep.opacity(0.9), in: .rect(cornerRadius: 18, style: .continuous))
                    }
                    Text("Tip: an anagram has to differ from the sentence, and names don't count as words.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 4)
                    Text("Suggestions use word lists from FrequencyWords by Hermit Dave (OpenSubtitles data, CC BY-SA 4.0).")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 4)
                }
                .padding()
            }
        }
        .navigationTitle("Help")
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
