# Murmur documentation

Technical documentation for Murmur, the local meeting-notes menu-bar app. For installing and day-to-day
use, start with the [project README](../README.md). These pages explain how it works inside and how to
change it.

| Page | What it covers |
|---|---|
| [architecture.md](architecture.md) | Components, the end-to-end flow, threading, the file map |
| [recording.md](recording.md) | ScreenCaptureKit capture, the two tracks, alignment, mixing, the global shortcut |
| [live-transcript.md](live-transcript.md) | The live window: streaming recognition, the view model, failure behavior |
| [transcription.md](transcription.md) | Apple speech recognition, languages, You/Others labels, echo removal |
| [summaries.md](summaries.md) | Claude Code and Codex: exact commands, the prompt, fallback, errors |
| [notes.md](notes.md) | Note file layout, the step-by-step note rewrite, recovering leftover recordings |
| [configuration.md](configuration.md) | Every `.env` setting, defaults, where files live |
| [development.md](development.md) | Building, signing, installing, testing, the release loop, common changes |
| [troubleshooting.md](troubleshooting.md) | Logs, permissions, and what each error message means |
| [../brand/BRAND.md](../brand/BRAND.md) | Logo, colours, icon files |

## Murmur in one paragraph

Press ⌃⌥⌘R. Murmur records your microphone and the Mac's audio as two separate tracks, and shows a
live transcript while you talk. Press ⌃⌥⌘R again. The tracks are mixed into one `.m4a`, each track is
transcribed on the Mac with Apple's speech recognition (mic = **You**, system audio = **Others**), and
the labeled transcript is summarized by Claude Code (or Codex) through the login you already have. The
result is `~/MeetingNotes/YYYY-MM-DD-HHMM.md` with the summary on top and the transcript below,
next to the audio file. No API keys, no local LLMs, no accounts, no telemetry.

## Fixed product decisions

These were chosen on purpose. Keep them unless the owner decides otherwise:

- **Summaries and the live chat only through Claude Code or Codex.** No API-key providers and no local models
  (Ollama, whisper.cpp). Claude Code is the default.
- **Transcription only through Apple's on-device recognizer** (`SpeechAnalyzer`, macOS 26+).
- **Speaker labels are You vs Others only**, taken from the audio source. No voice-based diarization and no guessed names.
- **Everything local except the transcript text** sent to the summary engine.
- **Global shortcut ⌃⌥⌘R** by default: three modifiers so it's never pressed by accident.
