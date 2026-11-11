# Anagrams

An iOS app for making anagrams in any language. A sentence becomes letter tiles; you rearrange
them into new words and the app checks the result. The app never records audio.

## Playing

**Getting a sentence**

- **Type** one: every letter lands as a tile as you type.
- **Read** one with the camera (Live Text, on-device).
- Let the app **give** you one at Easy, Medium or Hard. It comes from the app's own sentences
  or from **last week's newspaper headlines**.

**Building the anagram**

- Tap or drag tiles down to build new words; **Space** starts the next word.
- Punctuation marks and accents are free to add.
- Single letters ("a", "è") and acronyms or abbreviations ("nasa", "tv", "km") don't count
  as words, even when a dictionary has them.
- **Suggest** shows possible anagrams.
- **Check** says yes or no, shows the language of each word, and tells you whether the phrase
  means something.

**Modes**

- **Training**: as above, at your own pace.
- **Against the clock**: pick a level and the app gives you the sentence. You get 90 seconds
  to make as many words as you can.
- **Multiplayer** (2 to 4 players on one phone): chosen before the game starts, either each
  player writes a sentence for the next one to solve, or the app writes every sentence and
  the players take turns solving. Time, rounds, longest sentence, languages and scoring are
  set up front too.

The app never gives the same sentence twice: it remembers every one it has given. When its
own sentences for a choice run out, it turns to the news.

Everything runs on the phone:

- **Word checks**: the iOS spell-checker dictionaries, about 40 languages, offline.
- **Suggestions**: bundled word lists.
- **Grammar, meaning and newspaper-inspired sentences**: Apple Intelligence (Foundation
  Models), when the iPhone has it. Without it, those features step aside.
- **Newspapers**: the only network use, fetching Google News' public RSS feed.

## Getting started

### Prerequisites

- macOS with **Xcode** selected as the active developer directory:
  `sudo xcode-select -s /Applications/Xcode.app`. To run on an iPhone, Xcode must support the
  phone's iOS version (`xcodebuild -showsdks`).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

### Run in the simulator

```sh
xcodegen generate          # creates Anagrams.xcodeproj from project.yml; rerun after pulling
open Anagrams.xcodeproj
```

Choose the **Anagrams** scheme and an iPhone simulator, then press **⌘R**.

Optional launch arguments (Scheme → Run → Arguments):

| Argument | Effect |
|---|---|
| `-demoText "a sentence"` | start Training with that sentence |
| `-demo` | start with "Listen, Roma è" |
| `-givenSentence "text"` | the app always gives this sentence |
| `-meaning yes\|no`, `-grammar ok\|wrong` | fixed answers instead of Apple Intelligence |
| `-mute` | no countdown ticks |

### Run on an iPhone

**One-time setup**

1. **Pair the phone with the Mac**: connect it by cable, unlock it, and tap **Trust**.
2. **Turn on Developer Mode**: Settings → Privacy & Security → Developer Mode → on → Restart.
3. **Add your Apple ID to Xcode**: Xcode → Settings → Accounts → **+**, then Manage Certificates
   → **+** → Apple Development.
4. **Set your team** in `project.yml` (`DEVELOPMENT_TEAM`, currently `9P2NQ693B3`), then run
   `xcodegen generate`.
5. After the first install, **trust the developer** on the phone: Settings → General →
   VPN & Device Management.

**Every time**

```sh
xcodegen generate
xcrun devicectl list devices            # the phone's identifier
xcodebuild -project Anagrams.xcodeproj -scheme Anagrams -destination 'id=<identifier>' \
  -configuration Release -derivedDataPath build-device -allowProvisioningUpdates build
xcrun devicectl device install app --device <identifier> \
  build-device/Build/Products/Release-iphoneos/Anagrams.app
xcrun devicectl device process launch --device <identifier> com.ranierovirgilio.anagrams
```

### Run the tests

```sh
(cd Packages/AnagramKit && swift test)              # package logic on the Mac
xcodebuild test -project Anagrams.xcodeproj -scheme Anagrams \
  -destination 'platform=iOS Simulator,name=iPhone 17'   # everything, in the simulator
```

If you get *Unable to find a device matching…*, pick a simulator from
`xcrun simctl list devices available`, or pass `-destination 'id=<udid>'`.

UI tests are slow when the Mac is busy. If Spotlight is indexing the build folders, add an
empty `.metadata_never_index` file to `build-sim/` and `build-device/`.

## Troubleshooting

- **"The developer disk image could not be mounted"**: the phone's iOS is newer than your Xcode.
  If several versions are installed, use `export DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer`.
- **"invalid code signature … not been explicitly trusted"**: trust the developer on the phone
  (one-time setup, step 5).
- **Launch fails with "Locked"**: the app is installed; unlock the phone and open it.

## Project layout

```
App/
  Sources/
    App/            App entry, GameSession (writing → building), options, sentence maker,
                    Apple Intelligence checks, suggestions
    Features/       Home, Sentence (typing, camera), Board, Game (clock, multiplayer), Help
    Shared/         Tiles, theme, sounds (countdown ticks)
  Resources/        Assets, word lists, sentences
  Tests/  UITests/
Packages/AnagramKit/
  Sources/
    AnagramModels/  LetterBlock, Word, Phrase, AnagramBoard
    AnagramEngine/  Anagram checking, multilingual word validation, solver, game rules,
                    language detection
  Tests/
docs/               Architecture notes
.github/            CI, issue & PR templates
project.yml         XcodeGen project spec
```
