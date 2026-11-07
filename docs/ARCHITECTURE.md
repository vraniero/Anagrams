# Architecture

## Flow

1. **Listening**: `ServerTranscriber` streams the microphone (16 kHz mono PCM) to the backend's
   `WS /listen`. Each utterance comes back with its text and language. `GameSession` appends it
   to the source `Phrase`, and each `Word` keeps its `languageCode`.
2. **Make anagram**: `finish()` stops the microphone at once and sends `{"type":"finish"}`. The
   backend transcribes any audio still pending, ignores anything after it, and replies
   `{"type":"done"}`. The source phrase is then frozen.
3. **Building**: the user drags the blocks down to build the candidate phrase.
4. **Checking**: `AnagramChecker` confirms both phrases use the same letters (case, spaces and
   diacritics are ignored). A `WordValidator` checks that each word exists in *any* language.
   The answer is an `AnagramVerdict`: yes or no, plus the invalid words.

## `/listen` protocol

| Direction | Message |
|---|---|
| in  | binary frames: 16 kHz mono PCM, int16 little-endian |
| in  | `{"type":"finish"}`: transcribe what's pending, then send `done` |
| in  | `{"type":"reset"}`: start a new sentence |
| out | `{"type":"ready"}`: Whisper loaded |
| out | `{"type":"speech","start":s}` / `{"type":"silence","end":s}` |
| out | `{"type":"utterance","id":n,"lang":"it","start":s,"end":s,"text":"…"}` |
| out | `{"type":"done"}` |

Utterances are cut by an energy-based voice-activity detector: 0.7 s pause, 12 s maximum,
0.4 s minimum, and an adaptive noise floor. Whisper detects the language for each utterance.

## Modules

| Module          | Location                          | Responsibility                                  |
|-----------------|-----------------------------------|-------------------------------------------------|
| `Anagrams` app  | `App/Sources`                     | SwiftUI screens, drag & drop, `GameSession`     |
| `AnagramModels` | `Packages/AnagramKit/Sources/...` | `LetterBlock`, `Word`, `Phrase`                 |
| `SpeechCapture` | `Packages/AnagramKit/Sources/...` | `SpeechTranscriber` protocol, server/demo implementations, `ServerSettings` |
| `AnagramEngine` | `Packages/AnagramKit/Sources/...` | Letter matching, multilingual word validation   |
| backend         | `backend/`                        | Whisper speech-to-text and language detection   |

## Origin

The speech pipeline is ported from **Etymon** (`~/Developer/Etymon`): `backend/listen.py` and
`ios/Etymon/ConversationStream.swift`. Etymon also separates speakers (ECAPA voice embeddings).
Anagrams has one speaker, so that part was dropped.

## Open questions

- **Shipping without a Mac.** The backend has to run on a Mac on the same network, which is fine
  for development but not for the App Store. `SpeechTranscriber` is a protocol, so an
  on-device implementation (Whisper via CoreML/WhisperKit, or Apple's speech APIs plus
  `LanguageDetector`) or a hosted server can replace `ServerTranscriber` without other changes.
- **Dictionary for word validation.** `UITextChecker` covers only the device's languages.
  Etymon's pipeline already downloads per-language Wiktionary dumps from kaikki.org. The same
  data could produce a compact multilingual word list, either bundled with the app or served by
  a backend `/check` endpoint.
