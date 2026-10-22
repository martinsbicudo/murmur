# Recording

## Starting and stopping

- **Global shortcut:** ⌃⌥⌘R by default (`HOTKEY` in [configuration](configuration.md)). Registered with
  Carbon's `RegisterEventHotKey`, so it works from any app and needs no Accessibility permission.
  `HotKeySpec.parse` accepts `ctrl`/`control`, `option`/`opt`/`alt`, `shift`, `cmd`/`command` plus one
  letter or digit, and requires at least one of ctrl/option/cmd so Shift+letter can't hijack typing.
  If another app already owns the combination, Murmur shows a "Shortcut unavailable" notification.
  Changing `HOTKEY` requires restarting Murmur. A second shortcut, ⌃⌥⌘M (`MUTE_HOTKEY`), mutes and unmutes
  the microphone while recording ([live-transcript.md](live-transcript.md#mute)). Every shortcut's Carbon
  handler sees every press, so `GlobalHotKey` only acts on its own `EventHotKeyID` and passes the rest on.
- **Menu:** Start Recording / Stop Recording (the menu item shows the shortcut).
- **Feedback:** the "Tink" system sound on start, "Pop" on stop. While recording, the brand gradient (light blue → pool green) flows
  through the menu bar icon in a 3 s loop (`RecordingIcon`, 15 fps; a static gradient when *Reduce motion* is
  on) and the elapsed time shows next to it; it shows `…` while notes are processing.
- There is no pause. Stop ends the recording and starts processing.

## Capture

`AudioRecorder.start` builds one `SCStream` over the main display:

| Setting | Value | Why |
|---|---|---|
| `capturesAudio` | `true` | Everything the Mac plays: the meeting app, but also music and alerts |
| `captureMicrophone` | `true` if mic permission granted | Your voice, on the same clock as system audio |
| `excludesCurrentProcessAudio` | `true` | Murmur's own start/stop sounds aren't recorded |
| `sampleRate` / `channelCount` | 48 kHz / 2 | |
| video | 2×2 px, 1 fps, no cursor | ScreenCaptureKit needs a video config; it's kept as small as possible and never saved |

Two outputs are added: `.audio` → **Others** (`system.caf`) and `.microphone` → **You** (`mic.caf`).
Both are written into `~/MeetingNotes/.recording-<stamp>/` while recording.

If the microphone permission is denied, only system audio is recorded and a notification says so;
everything in the transcript is then labeled Others.

If the stream fails mid-recording (for example the display configuration changes), Murmur posts
"Recording interrupted" and stops cleanly, processing whatever was captured.

## Track alignment (`TrackWriter`)

The two sources don't deliver audio continuously: the system track is silent when nothing plays, and
buffers arrive with their own presentation timestamps. To keep both files aligned to the moment
recording started, every buffer's timestamp is compared with a shared `clockStart` (the first buffer
of either source). If the file is behind that position by more than **20 ms** (`gapTolerance`),
the missing frames are written as silence before the buffer. Jitter below 20 ms is ignored. A buffer
that arrives early is never trimmed.

So `mic.caf` and `system.caf` start at the same instant and timestamps in the two transcripts are comparable,
which the echo removal depends on (see [transcription.md](transcription.md)).

A track that never received audio isn't returned by `stop()`. If neither has audio, processing fails
with "No audio was captured", which almost always means a missing permission.

## Mixing

On stop, `ffmpeg` mixes the tracks into `<stamp>.m4a` (AAC 128 kbps), next to the note:

- one track: re-encoded as is;
- two tracks: each resampled to 48 kHz stereo, then `amix=inputs=2:duration=longest:normalize=0`
  (no volume halving) followed by `alimiter=limit=0.95` to avoid clipping.

The `.m4a` is the file you keep; transcription uses the separate `.caf` tracks, which are deleted once
the note is finished.

## File naming

The stamp is the start time, `yyyy-MM-dd-HHmm`. If a note with that name already exists (two recordings
in the same minute), `-2`, `-3`… is appended to both the `.md` and the `.m4a`.
