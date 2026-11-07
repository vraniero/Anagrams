# Anagrams

An iOS app that turns your speech into letter blocks you can rearrange into anagrams, in any language.

1. Speak. The app detects the language and writes your sentence as letter blocks. You can
   switch languages mid-sentence.
2. Tap **Make anagram**. Listening stops. What you already said is still added, but nothing after.
3. Tap or drag blocks down to build a new phrase. Tap **Space** to start the next word. Tap a
   block below (or drag it back up) to return it, and drag blocks below to reorder them.
4. Tap **Check**. The app says yes or no and shows the language each word was found in. Words
   may come from any language. It also tells you if letters are left over, if you rebuilt the
   original sentence, or which words aren't words anywhere.

Words are checked offline with the iOS spell-checker dictionaries (about 40 languages), and the
languages you spoke are tried first.

## How it works

Speech recognition and language detection run on a **Mac backend** (`backend/`). It runs
Whisper large-v3-turbo through `mlx-whisper`, a setup ported from the Etymon project. The
phone streams 16 kHz microphone audio over a WebSocket. The backend cuts the audio into
utterances at pauses and sends back each one's text and language. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Getting started

### Prerequisites

- macOS on **Apple Silicon** (for the backend), with **Xcode** selected as the active
  developer directory: `sudo xcode-select -s /Applications/Xcode.app`. To run on an iPhone,
  Xcode must support the phone's iOS version. Check with `xcodebuild -showsdks`.
- **Python 3.11+**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

### 1. Run the backend

Set it up once:

```sh
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt -r requirements-speech.txt
```

Run it in its own terminal and leave it running (**Ctrl+C** stops it):

```sh
cd backend
.venv/bin/uvicorn app:app --host 0.0.0.0 --port 8000 --no-access-log
```

- The first time the phone connects, Whisper downloads (about 1.6 GB) and loads. The app shows
  *Connecting…* until it's ready.
- `--host 0.0.0.0` makes the backend reachable from an iPhone on the same Wi-Fi.
- The terminal prints each utterance heard, with its language: `[it] Roma è`.
- Check that it's up: `curl localhost:8000/health`.
- Optional: `ANAGRAMS_LANGUAGES=it,en,fr` limits the accepted languages. An utterance detected
  as anything else (usually a misdetection) is transcribed again in the language heard last.

Stop it with Ctrl+C, or with `pkill -f "uvicorn app:app"`. If port 8000 is still taken, run
`kill $(lsof -ti tcp:8000)`.

### 2. Run the app in the simulator

```sh
xcodegen generate          # creates Anagrams.xcodeproj from project.yml; rerun after pulling
open Anagrams.xcodeproj
```

Choose the **Anagrams** scheme and an iPhone simulator, then press **⌘R**. The simulator
reaches the backend at `http://localhost:8000`.

**No backend?** Add the `-demo` launch argument (Scheme → Run → Arguments). The app then plays
a scripted multilingual sentence.

### 3. Run the app on an iPhone

**One-time setup**

1. **Pair the phone with the Mac**: connect it by cable, unlock it, and tap **Trust**.
2. **Turn on Developer Mode**: Settings → Privacy & Security → Developer Mode → on → Restart.
3. **Add your Apple ID to Xcode**: Xcode → Settings → Accounts → **+**, then Manage Certificates
   → **+** → Apple Development.
4. **Set your team** in `project.yml` (`DEVELOPMENT_TEAM`, currently `9P2NQ693B3`), then run
   `xcodegen generate`.
5. After the first install, **trust the developer** on the phone: Settings → General →
   VPN & Device Management.
6. On first launch, allow **microphone** and **local network** access. Without local network
   access, the app cannot reach the Mac.

**Every time**

1. Start the backend with `--host 0.0.0.0`.
2. Put the phone and the Mac on the **same Wi-Fi**. Find the Mac's address with `ipconfig getifaddr en0`.
3. Build and launch, passing the server address. The app remembers it:

   ```sh
   xcodegen generate
   xcrun devicectl list devices            # the phone's identifier
   xcodebuild -project Anagrams.xcodeproj -scheme Anagrams -destination 'id=<identifier>' \
     -configuration Release -derivedDataPath build-device -allowProvisioningUpdates build
   xcrun devicectl device install app --device <identifier> \
     build-device/Build/Products/Release-iphoneos/Anagrams.app
   xcrun devicectl device process launch --device <identifier> --terminate-existing \
     com.ranierovirgilio.anagrams -api http://<Mac address>:8000
   ```

   From Xcode instead, add `-api http://<Mac address>:8000` under Scheme → Run → Arguments.

### 4. Run the tests

```sh
(cd backend && .venv/bin/pytest -q)                 # backend (Whisper is faked)
(cd Packages/AnagramKit && swift test)              # package logic on the Mac
xcodebuild test -project Anagrams.xcodeproj -scheme Anagrams \
  -destination 'platform=iOS Simulator,name=iPhone 17'   # everything, in the simulator
```

If you get *Unable to find a device matching…*, pick a simulator you have from
`xcrun simctl list devices available`, or pass `-destination 'id=<udid>'`.

## Troubleshooting

- **"Lost the server" / stuck on Connecting…**: the backend isn't running, or the server address
  is wrong (simulator: `http://localhost:8000`).
- **The phone can't reach the backend**: check that both are on the same Wi-Fi, the backend was
  started with `--host 0.0.0.0`, and local network access is allowed (Settings → Privacy &
  Security → Local Network). The Mac's IP can change after a restart. Test with
  `curl http://<Mac address>:8000/health`.
- **"The developer disk image could not be mounted"**: the phone's iOS is newer than your Xcode.
  If several versions are installed, use `export DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer`.
- **"invalid code signature … not been explicitly trusted"**: trust the developer on the phone
  (one-time setup, step 5).

## Project layout

```
App/
  Sources/
    App/            App entry, GameSession (listening → building → result), RootView
    Features/       Listening, Board, Result screens
    Shared/         Reusable UI components
  Resources/        Assets, localized strings
  Tests/  UITests/
Packages/AnagramKit/
  Sources/
    AnagramModels/  LetterBlock, Word, Phrase
    SpeechCapture/  ServerTranscriber (mic → backend), DemoTranscriber, LanguageDetector
    AnagramEngine/  Anagram checking + multilingual word validation
  Tests/
backend/            FastAPI + Whisper: WS /listen (speech → text + language)
docs/               Architecture notes
.github/            CI (backend + iOS), issue & PR templates
project.yml         XcodeGen project spec
```
