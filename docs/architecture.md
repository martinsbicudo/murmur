# Architecture

Murmur is a single Swift Package Manager executable (`Sources/Murmur`), wrapped into a signed
`.app` bundle by `scripts/build-app.sh`. It runs as a menu-bar-only app (`LSUIElement`, no Dock icon)
and also has a command-line mode (`--process`) that runs the same pipeline without the UI.

- Swift tools 6.2, Swift 5 language mode, minimum macOS 26 (needed for `SpeechAnalyzer`).
- Builds with the Xcode Command Line Tools only; full Xcode isn't needed.
- No third-party Swift packages. The only external tools are `ffmpeg` (Homebrew) and the
  `claude` / `codex` CLIs.

## End-to-end flow

```
⌃⌥⌘R / menu ──► AppDelegate.startRecording
                   │
                   ├─► AudioRecorder (ScreenCaptureKit SCStream)
                   │      ├─ .audio      ──► TrackWriter ──► .recording-<stamp>/system.caf   (Others)
                   │      └─ .microphone ──► TrackWriter ──► .recording-<stamp>/mic.caf      (You)
                   │      └─ every buffer also ──► LiveAudioRouter ──► LiveTranscriber (per speaker)
                   │                                                      └─► LiveTranscriptModel ──► LiveTranscriptWindow
⌃⌥⌘R again ──► AppDelegate.stopRecording
                   │  recorder.stop() → RecordedTracks; live.stop()
                   ▼
              NotePipeline.finish(tracks:startedAt:)
                   1. ffmpeg mixes the tracks       ──► ~/MeetingNotes/<stamp>.m4a
                   2. note written ("Transcribing…")──► ~/MeetingNotes/<stamp>.md
                   3. SpeechEngine.transcribeFile per track
                      TranscriptMerger.merge (labels + echo removal)
                   4. note rewritten with transcript ("Summarizing…")
                   5. Summarizer: claude -p  (or codex exec)
                   6. note rewritten with summary (or "Summary failed: …")
                   7. .recording-<stamp>/ deleted
                   ▼
              Notifier: "Meeting notes ready" (click opens the note)
```

`--process <path>` enters at `NotePipeline.process(path:)`. A `.recording-*` folder goes through
`finish` (with labels); any other path is treated as one mixed audio file and transcribed unlabeled.

## Components

| File | Responsibility |
|---|---|
| `main.swift` | Entry point. `--process <path>` runs the pipeline and prints progress; otherwise starts `NSApplication` with `AppDelegate`. |
| `AppDelegate.swift` | The state machine (`idle → starting → recording → stopping`), status-bar icon and timer, menu, global shortcut registration, start/stop sounds, background jobs (`runJob`). |
| `AppActions.swift` | Menu actions that don't touch recording state: open notes folder, open settings (creating `.env` from the bundled template), show log, pick a file to reprocess, find the latest note. |
| `AudioRecorder.swift` | Owns the `SCStream`. Routes `.audio` buffers to Others and `.microphone` buffers to You. `RecordedTracks` describes a finished or leftover track folder. |
| `TrackWriter.swift` | Writes one source to a `.caf`, padding silence so tracks stay aligned to a shared clock. |
| `LiveSession.swift` | Starts/stops live recognition for each speaker; `LiveAudioRouter` hands capture buffers to the right `LiveTranscriber`. |
| `LiveTranscriber.swift` | Streams one source into a `SpeechAnalyzer` (converting the audio format) and reports volatile/final text. |
| `LiveTranscriptModel.swift` | `@Observable` view model: turns live updates into speaker blocks. |
| `LiveTranscriptWindow.swift` | Floating non-activating `NSPanel` with the SwiftUI live view. |
| `MicrophoneMuter.swift` | Mutes the default microphone for every app and restores it exactly, even after a crash. |
| `CoreAudioMicrophone.swift` | Core Audio access to the default input's mute and volume. |
| `RecordingIcon.swift` | The animated menu bar icon while recording: the brand gradient flowing through the mark. |
| `Brand.swift` | The brand accent colours (Sky, Pool) used in code. |
| `SpeechEngine.swift` | Locale resolution, speech-model download, file transcription. |
| `Transcript.swift` | `Speaker`, `TranscriptSegment`, Markdown rendering, `TranscriptMerger` (labels + echo removal). |
| `AgentCLI.swift` | Engine choice and fallback, running `claude` / `codex` headless without tools, reading their output. Shared by the summary and the live chat. |
| `Summarizer.swift` | The meeting-notes prompt and parsing the summary into title + body. |
| `MeetingChat.swift` | The live chat prompt, the request (transcript so far, earlier Q&A, question) and its model choice. |
| `LiveChatModel.swift` | `@Observable` chat thread for one recording: one question at a time, drops answers after a reset. |
| `LiveChatView.swift` | The SwiftUI question field and answers under the live transcript. |
| `NotePipeline.swift` | Orchestrates mix → transcribe → summarize; file naming (`stamp`, `uniqueBase`); ffmpeg arguments. |
| `Note.swift` | Renders the note Markdown at every stage. |
| `Config.swift` | Reads `~/.config/murmur/.env` plus environment overrides. |
| `Shell.swift` | Runs external tools with a sane environment; `Log` writes `~/Library/Logs/Murmur.log`. |
| `HotKey.swift` | Parses `HOTKEY` strings and registers the Carbon global hotkey. |
| `Notifier.swift` | User notifications; clicking one opens the note. |
| `Alerts.swift` | Modal alerts: quit while busy, permission help. |

## Concurrency

- `AppDelegate`, `LiveSession`, `LiveTranscriptModel` and the window are `@MainActor`.
- ScreenCaptureKit delivers buffers on a private serial queue (`murmur.audio`). `AudioRecorder` writes
  tracks on that queue and calls the live router from it, so `LiveTranscriber.append` must stay cheap:
  it only converts the buffer and yields it into an `AsyncStream`. Recognition runs inside the analyzer.
- `LiveAudioRouter` is guarded by an `NSLock` because it is touched from both the capture queue and the main actor.
- Live results hop back to the main actor (`Task { @MainActor in model.apply(update) }`).
- Processing runs in a `Task`; several notes can be processing at once (each tracked in `activeJobs`
  and shown in the menu). Quitting while recording or processing asks for confirmation.

## Design principles in the code

- **Never lose data.** The note is rewritten after each step; raw tracks are deleted only after the
  note is complete; a summary failure keeps the transcript and explains why.
- **Recording is never blocked by optional features.** If live transcription can't start, the window
  says so and recording continues. If the mic is denied, system audio is still recorded.
- **Pure logic is static and tested.** Argument building, parsing, merging, alignment math and file
  naming are static functions covered by `Tests/MurmurTests`.
