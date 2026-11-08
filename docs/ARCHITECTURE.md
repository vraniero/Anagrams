# Architecture

## Flow

1. **Writing**: the sentence is typed, read by the camera (VisionKit Live Text), or made by
   `SentenceMaker`, from `sentences.json` or last week's Google News headlines.
   `SentenceHistory` (UserDefaults) remembers every sentence given, so none is given twice.
   - `GameSession.setDraft` turns typing into the source `Phrase` as you type. Tiles that
     didn't change keep their identity, and a letter limit can stop input.
   - Each `Word` keeps the `languageCode` that `LanguageDetector` found for it.
   - The sentence is proofread by Apple Intelligence, or by the dictionaries when it isn't
     available.
2. **Make anagram**: the source phrase is frozen and laid out on an `AnagramBoard`.
3. **Building**: the user taps or drags tiles down.
   - Punctuation marks and accents are free.
   - A tile moved down loses its accent; it comes back in the tray.
4. **Checking**: `AnagramJudge` returns an `AnagramVerdict`.
   - Both phrases must use the same letters (case, spaces and accents ignored).
   - Each word must exist in some language (`WordValidator`: `UITextChecker` on device).
   - Optionally, all the words must share one language.
   - Apple Intelligence then says whether a correct anagram of two or more words means
     something (`Meaning`). The games use it for a bonus.

The app has no audio input. Its only sound is the synthesized countdown tick, played back
only.

## Modules

| Module          | Location                          | Responsibility                                  |
|-----------------|-----------------------------------|-------------------------------------------------|
| `Anagrams` app  | `App/Sources`                     | SwiftUI screens, drag & drop, `GameSession`, Apple Intelligence checks, sentence maker |
| `AnagramModels` | `Packages/AnagramKit/Sources/...` | `LetterBlock`, `Word`, `Phrase`, `AnagramBoard` |
| `AnagramEngine` | `Packages/AnagramKit/Sources/...` | Letter matching, word validation, solver, game rules (`ClockRound`, `Duel`), `LanguageDetector` |

## Network

The only request is to `news.google.com/rss`, when a sentence is asked for from newspapers.
Headlines are kept for an hour.

## Open questions

- **Dictionary coverage.** `UITextChecker` covers only the device's languages. Per-language
  Wiktionary data (kaikki.org) could produce a compact multilingual word list bundled with the
  app.
