# Development

## Requirements

- macOS 26+, Apple Silicon
- Xcode Command Line Tools (`xcode-select --install`); full Xcode not needed
- Homebrew `ffmpeg` (`make deps`)
- `claude` and/or `codex` installed and logged in, to exercise summaries

## Make targets

| Command | Does |
|---|---|
| `make deps` | `brew install ffmpeg`, create `~/.config/murmur/.env` from `.env.example` |
| `make cert` | Create the local signing identity, once (`scripts/create-cert.sh`) |
| `make test` | `swift test` |
| `make build` | `scripts/build-app.sh` → `build/Murmur.app` |
| `make install` / `make update` | Build, quit the running app, replace `/Applications/Murmur.app`, relaunch |
| `make process FILE=<path>` | Run the pipeline on an audio file or `.recording-*` folder with the installed app |
| `make icons` | Regenerate brand SVGs, `Resources/AppIcon.icns` and menu bar PNGs |
| `make reset-permissions` | `tccutil reset` Microphone, ScreenCapture and SpeechRecognition for `local.murmur.app` |
| `make uninstall` | Remove the app (notes and settings stay) |
| `make clean` | Remove `.build` and `build` |

## The change loop

```bash
# edit Sources/Murmur/…
make test
make install
```

Murmur has no versions or releases: everyone builds from `main`. `CFBundleVersion` is the build timestamp, set automatically, so you can tell builds apart.

## How the app bundle is built

`scripts/build-app.sh`:

1. `swift build -c release --product Murmur`.
2. Assembles `build/Murmur.app/Contents/{MacOS,Resources}`: the binary, `AppIcon.icns`, the menu bar
   PNGs and `.env.example` (as `env.example`, the template used by Settings).
3. Fills `__BUILD__` (the build timestamp) in `Resources/Info.plist`.
4. Signs with the "Murmur Local Signing" identity (`--identifier local.murmur.app`), or ad-hoc with a
   warning if the identity doesn't exist.

`Info.plist` declares `LSUIElement` (menu bar only), `LSMinimumSystemVersion` 26.0, and the usage strings
for Microphone, Speech Recognition and Audio Capture.

## Why a local signing identity

macOS (TCC) ties Microphone / Screen & System Audio Recording permissions to the code signature's
designated requirement. Ad-hoc signatures change on every build, so permissions would be lost after every
update. `scripts/create-cert.sh` creates a self-signed code-signing certificate in a dedicated keychain
(`~/Library/Keychains/murmur-signing.keychain-db`, password from `scripts/signing.env`) and allows `codesign`
to use it without prompts. Every build signed with it keeps the same identity.

A dedicated keychain is used because importing into the login keychain made `codesign` fail with
`errSecInternalComponent` (the key's partition list needs the login password). Overrides: `SIGN_IDENTITY`,
`SIGN_KEYCHAIN`, `SIGN_KEYCHAIN_PASSWORD`.

## Tests

Swift Testing (`import Testing`) in `Tests/MurmurTests`, one suite per area:

| File | Covers |
|---|---|
| `ConfigTests` | `.env` parsing, quotes, `export`, empty values, defaults |
| `TranscriptTests` | Timestamps, rendering, paragraph merging, `TranscriptMerger` (labels, echo, ties) |
| `EngineSelectionTests` | Preferred engine first, fallback, not-installed filtering |
| `SummarizerTests` | Output parsing, Claude Code JSON errors, exact CLI arguments, prompt labels |
| `NoteTests` | Note rendering at each stage, durations |
| `PipelineTests` | Stamps, unique names, ffmpeg arguments, work folders, leftover recordings, track alignment |
| `HotKeyTests` | Shortcut parsing and display |
| `LiveTranscriptModelTests` | Live block updates |

What the tests don't cover (needs a manual run): ScreenCaptureKit capture, permission prompts, the live
window on screen, and real speech recognition. A quick end-to-end check without recording:

```bash
make build
NOTES_DIR=/tmp/murmur-test LANGUAGE=en-US build/Murmur.app/Contents/MacOS/Murmur --process /tmp/murmur-test/sample.m4a
```

For a labeled two-track test, put a `mic.caf` and a `system.caf` in `/tmp/murmur-test/.recording-2026-10-21-1400/`
and pass that folder instead.

**Known flake:** `swift test` occasionally fails to compile with *"plugin for module 'TestingMacros' not
found"*. It's an environment issue with the Command Line Tools toolchain; run it again.

## Common changes

| To change… | Edit |
|---|---|
| Summary format or instructions | `Summarizer.systemPrompt` (then update `SummarizerTests`) |
| Live chat instructions or default model | `MeetingChat.systemPrompt`, `MeetingChat.defaultClaudeCodeModel` (then `LiveChatModelTests`) |
| Engine command lines | `AgentCLI.claudeCodeArguments` / `codexArguments` |
| Note layout | `Note.render()` |
| Labels / echo removal | `TranscriptMerger` in `Transcript.swift` |
| Live window look | `LiveTranscriptWindow.swift` (SwiftUI view at the bottom) |
| Recording icon animation (speed, frame rate) | `RecordingIcon.period`, `framesPerSecond` |
| Menu items | `AppDelegate.buildMenu`; stateless actions in `AppActions.swift` |
| New setting | Add a property in `Config`, add the key to `knownKeys` if it should be overridable from the environment, document it in `.env.example` and [configuration.md](configuration.md) |
| Default shortcut | `HotKeySpec.defaultValue` and `.env.example` |
| Icons or colours | `brand/generate.py`, then `make icons` ([BRAND.md](../brand/BRAND.md)) |

## Code conventions

- No comments except a short doc comment where the *why* isn't obvious from the code.
- Keep files under ~300 lines and functions under ~50; split by responsibility.
- Pure logic as `static` functions with tests; side effects at the edges.
- Errors are logged with `Log.write` or shown to the user, never silently swallowed (best-effort temp
  cleanup is the exception).
- No third-party dependencies.
