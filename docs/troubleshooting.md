# Troubleshooting

Start with the log: menu › **Show Log**, or `tail -f ~/Library/Logs/Murmur.log`. It records shortcut
registration, recording start/stop with the tracks captured, live transcription status, speech-model
downloads, which summary engine ran, failures, and the path of each finished note.

## Permissions

| Permission | Needed for | If missing |
|---|---|---|
| Screen & System Audio Recording | All capture (ScreenCaptureKit) | "Murmur couldn't start recording" alert |
| Microphone | The You track | Records system audio only; "Microphone access is off" notification |
| Speech Recognition (if macOS asks) | Transcription | Transcription error in the note |
| Notifications (optional) | "Meeting notes ready" banner | Notes still appear, without a banner |

After granting Screen & System Audio Recording, quit and reopen Murmur. To start over:
`make reset-permissions`, then launch Murmur and grant them again.

If permissions are lost after every `make install`, the build was ad-hoc signed: run `make cert`, then
`make install`, and grant them one last time. `codesign -dv /Applications/Murmur.app` should show
`Authority=Murmur Local Signing`.

## Messages and what to do

| Message | Cause | Fix |
|---|---|---|
| Murmur couldn't start recording | No Screen & System Audio Recording permission | Grant it, quit and reopen |
| Shortcut unavailable | Another app owns the `HOTKEY` combination | Pick another `HOTKEY`, restart Murmur |
| Invalid HOTKEY | Unparseable value | Use e.g. `ctrl+option+cmd+r`; needs ctrl, option or cmd |
| No audio was captured | Neither track got audio | Check permissions and that the meeting audio plays through the Mac |
| `_No speech detected._` in the note | Audio captured but nothing recognized | Wrong `LANGUAGE`, or audio played on a device the Mac doesn't route (USB speakerphone) |
| Apple speech recognition doesn't support "…" | `LANGUAGE` (or the system locale with `auto`) isn't supported | Set `LANGUAGE=pt-BR`, `en-US`… |
| Apple speech recognition isn't available on this Mac | Recognizer unavailable | Check macOS version (26+) and Siri/Dictation language assets |
| Live transcript unavailable: … | Live recognition couldn't start (often the speech model still downloading) | Nothing to do; the final note is still transcribed |
| ffmpeg not found. Install it with `make deps`. | `ffmpeg` missing | `make deps`, or set `FFMPEG_PATH` |
| Summary failed: … isn't installed | Neither `claude` nor `codex` found | Install one, or set `CLAUDE_CODE_BIN` / `CODEX_BIN` |
| Summary failed: Claude Code failed: Not logged in | Claude Code logged out | Run `claude` in a terminal and log in, then reprocess |
| Summary failed: Codex failed: … | Codex error or logged out | Run `codex login`, then reprocess |
| Recording interrupted | The capture stream stopped (display change, sleep) | The captured part is processed; record again |

Reprocess any note with menu › **Process Audio File…** or `make process FILE=<audio or .recording folder>`.

## Transcript quality

- **Other people's words labeled "You"**: echo from speakers. Use headphones, or lower
  `TranscriptMerger.echoContainment` (or widen `echoWindow`) in code so more echoes are dropped ([transcription.md](transcription.md)).
- **Mic still muted after Murmur quit**: Murmur restores it on quit and on the next launch. If it's
  still muted, open Murmur once, or unmute it in System Settings › Sound › Input. The log shows
  `microphone muted` / `microphone restored` ([live-transcript.md](live-transcript.md#mute)).
- **Everything labeled Others**: microphone permission is off.
- **Garbled text**: wrong language. Set `LANGUAGE` to what people speak; mixed-language meetings
  are transcribed in one language only.

## Leftover `.recording-*` folders

If Murmur quit or crashed while recording or processing, the raw tracks stay in
`~/MeetingNotes/.recording-<stamp>/` (hidden; `ls -a ~/MeetingNotes`). Process the folder to get the note
with labels and the original time; it's deleted after the note is complete. See [notes.md](notes.md).
