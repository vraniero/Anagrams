import SwiftUI

/// The rules you can choose, in the navigation bar of every mode.
struct OptionsMenu: View {
    @AppStorage(Options.sameLanguageKey) private var sameLanguage = false
    @AppStorage(Options.suggestionsKey) private var suggestions = true
    @AppStorage(Options.swearBonusKey) private var swearBonus = false

    var body: some View {
        Menu {
            Toggle(isOn: $sameLanguage) {
                Label("Words in one language", systemImage: "character.book.closed")
                Text("Otherwise each word may be in a different language")
            }
            Toggle(isOn: $suggestions) {
                Label("Suggestions", systemImage: "lightbulb")
                Text("Show possible anagrams when asked")
            }
            Toggle(isOn: $swearBonus) {
                Label("Swear words bonus", systemImage: "exclamationmark.bubble")
                Text("Swear words score double, a rude anagram triple")
            }
        } label: {
            Label("Options", systemImage: "slider.horizontal.3")
        }
        .accessibilityIdentifier("Options")
    }
}
