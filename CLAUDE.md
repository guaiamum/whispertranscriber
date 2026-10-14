# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A sandboxed macOS menu bar agent (`LSUIElement`, SwiftUI `MenuBarExtra` in `.window` style) that records the microphone and transcribes on-device with [FluidAudio](https://github.com/FluidInference/FluidAudio) (Parakeet TDT v3 ASR, Silero VAD, speaker diarization). The finished transcript goes to the clipboard and can optionally be pasted into the frontmost app. It is a plain Xcode project with no Package.swift. FluidAudio is its only SwiftPM dependency. Requires Xcode 26.0.1+.

## Targets

- **WhisperTranscriber**: copies the `hf` folder reference into `Resources/hf` so the Core ML models ship inside the app.
- **WhisperTranscriberLite**: has no resources, so it downloads models on first launch. Its `lite-Info.plist` appends `Lite` to `PRODUCT_BUNDLE_IDENTIFIER`, which makes the real bundle ID `com.joaoanes.WhisperTranscriberLiteLite`. Use that ID with `defaults`, `tccutil`, and when looking up its sandbox container.
- **WhisperTranscriberTests**: hosted in `WhisperTranscriber.app`, so building the tests builds the full target.

Both apps compile the same file-system-synchronized `WhisperTranscriber/` folder, and the code has no `#if` switches between them. A new `.swift` file dropped into that folder joins both targets with no `project.pbxproj` edit. The only behavioral difference is at runtime: `ParakeetModelLoader` looks in the bundle first.

The `hf` folder reference is `../../Documents/hf` **relative to the repo root**. It means `~/Documents/hf` only when the repo sits two levels below home. The in-repo `hf/` directory isn't used by the build. If the folder is missing, the full target and the tests fail in the resource copy phase. Create an empty one (`mkdir -p ../../Documents/hf` from the repo root, as CI does) when you don't need bundled models.

## Commands

```bash
# Build (CI-style, unsigned). Swap the scheme for WhisperTranscriberLite.
xcodebuild -project WhisperTranscriber.xcodeproj -scheme WhisperTranscriber -configuration Release \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

# Local runnable build without the project's signing team (DEVELOPMENT_TEAM 3QYF6TV64Q): sign ad hoc
xcodebuild -project WhisperTranscriber.xcodeproj -scheme WhisperTranscriberLite -configuration Debug \
  -derivedDataPath <dir> CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual build

# All tests
xcodebuild test -project WhisperTranscriber.xcodeproj -scheme WhisperTranscriber -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

# One class or one test: add
  -only-testing:WhisperTranscriberTests/TextCleanupTests
  -only-testing:WhisperTranscriberTests/TextCleanupTests/<testMethodName>
```

If `xcode-select -p` points at CommandLineTools, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. No linter or formatter is configured.

Every ad-hoc rebuild invalidates the Accessibility grant that auto-paste needs, so you have to grant it again. The app also has to run from a stable location such as `~/Applications`, not DerivedData, to show up in the Accessibility list.

The version lives in `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.pbxproj`, repeated in every target's Debug and Release configs. Bump all of them together.

## Architecture

**Entry point.** `WhisperTranscriberApp.swift` hosts the `MenuBarExtra`. Its icon comes from `RecorderActivity` (`symbolName`/`tint` in `RecorderActivity+Appearance.swift`) and is tinted manually, because the menu bar renders template images in one color. `AppDelegate` holds a `ProcessInfo` activity and disables automatic termination so macOS doesn't reap the agent. It also sets up file logging and `CrashHandler` and registers the hotkey.

**Shared state.** Shared state lives in singletons: `RecorderViewModel.shared`, `SettingsManager.shared`, `RecordingsManager.shared`, `HotKeyManager.shared` and `AudioFade.shared`. The first three are `@MainActor` `ObservableObject`s. `RecorderViewModel.activity` derives one `RecorderActivity` from its flags, and the UI keys off it.

**Recording flow** (`RecorderViewModel`):
1. `HotKeyManager` registers a Carbon `RegisterEventHotKey` from a chord string: modifier glyphs `⌥⌃⇧⌘`, then the last letter or digit, or a `Space` suffix. It reports both press and release, so `hotkeyPressed`/`hotkeyReleased` can implement either toggle or hold-to-talk.
2. `AudioCapture` taps `AVAudioEngine` and resamples to 16 kHz mono `Float` with FluidAudio's `AudioConverter`. It writes a WAV to `Application Support/WhisperTranscriber/Recordings/recording_<epoch>.wav`, keeps all samples in memory, and in live mode also emits chunks as an `AsyncStream`.
3. Live mode (`followLivePreview`): streaming Silero VAD (`speechEndIndex`) finds end-of-speech boundaries. `LivePreviewAccumulator` claims each `[committed, boundary)` sample range, which is transcribed and appended to `livePreview`.
4. On stop, the live task drains, then a final pass runs over the whole recording: VAD `speechOnly`, an early exit if there is no speech, `transcribe` or `transcribeWithSpeakers`, `TextCleanup`, then the suffix. The result goes to the clipboard, optionally gets auto-pasted (a `CGEvent` ⌘V, which needs Accessibility), and lands in `RecordingsManager`. The final transcript replaces the live one.

**Engine seam.** `SpeechPipeline.swift` defines the `SpeechTranscribing` and `AudioCapturing` protocols. `ParakeetEngine` (an actor) and `AudioCapture` conform to them. `RecorderViewModel.init(engine:capture:prewarm:)` takes injected implementations. Tests use `FakeAudioCapture` and `ScriptedEngine` from `WhisperTranscriberTests/SpeechPipelineDoubles.swift` with `prewarm: false`, then `await recorder.finalizeTask?.value`.

**Models.** `ParakeetModelLoader` resolves each model in order:
1. the bundle (`Resources/hf/models/FluidInference/<folder>`)
2. `Application Support/WhisperTranscriber/Models/<folder>`
3. a FluidAudio download

Folder names are FluidAudio's cache names (the HF repo name without `-coreml`). Diarizer models load lazily the first time speaker detection is used.

**Settings.** Each setting is an `@AppStorage` property on `SettingsManager` and is surfaced as a `ToggleRow`/`SettingRow` in the popover (`WhisperTranscriberView.swift`). Changing the hotkey re-registers it through `RecorderViewModel.registerHotkey`.

**Records window.** `RecordsWindowController` is an AppKit window hosting `RecordsView`/`RecordsViewModel`. Re-transcription reloads the WAV with `AudioCapture.loadSamples`. Transcripts live only in `RecordingsManager.transcriptions`, which is in memory and not persisted across launches. Recording retention is enforced on every `scanForRecordings()`.

**Sandbox and paths.** The App Sandbox is on. Its entitlements are audio input, network client (for model downloads) and user-selected read-only. All "Application Support", "Library/Logs" and `UserDefaults` paths therefore resolve inside `~/Library/Containers/<bundle id>/Data/`.

## Conventions

- **Never log transcript text.** Log character counts instead, as in `"📝 Transcription (\(text.count) chars)"`. `Log.general/speech/recording/hotkey` write to OSLog with `.public` privacy *and* to `Library/Logs/WhisperTranscriber/app.log`, so anything logged is readable.
- Tests use XCTest against the real singletons and real `UserDefaults`. Save and restore any setting a test mutates in `setUp`/`tearDown`.
- `SpokenAudioIntegrationTests` synthesize speech with `say` and `afconvert` and run the real engine. They `XCTSkip` unless Parakeet models exist in the test host's `Application Support/WhisperTranscriber/Models`.
- CI (`.github/workflows/build.yml`, `macos-26`, Xcode 26.0.1) builds the full app, runs the tests, then builds Lite, all unsigned and with an empty `hf` directory.
