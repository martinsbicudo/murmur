# Live transcript window

While recording, the **Murmur · Live** window shows what is being said, labeled **You** (blue-green gradient) and
**Others** (grey). It's a preview only: the final note is transcribed again from the saved tracks,
which gives more accurate text.

## Behavior

- Opens automatically when recording starts, unless `LIVE_TRANSCRIPT=off`. Menu › **Show Live Transcript**
  opens it any time.
- A floating, non-activating `NSPanel`: it stays above other windows without stealing focus from the
  meeting app, joins all Spaces and works next to full-screen apps.
- Remembers its size and position (`setFrameAutosaveName("MurmurLiveTranscript")`). The first time, it
  appears in the bottom-right corner of the main screen.
- Auto-scrolls to the newest text.
- Text still being recognized ("volatile") is shown in a lighter colour and is replaced as the
  recognizer refines it; it becomes final when the sentence ends.
- The status line shows "Preparing on-device speech recognition…" at start, "Listening…" once running,
  or "Live transcript unavailable: …" if it failed.

## How it works

```
capture queue                         analyzer                      main actor
AudioRecorder ──buffer──► LiveAudioRouter.route(speaker, buffer)
                             └─► LiveTranscriber.append  ──convert──► AsyncStream<AnalyzerInput>
                                                                     SpeechAnalyzer + SpeechTranscriber
                                                                       results (volatile / final)
                                                                         └─► LiveUpdate ──► LiveTranscriptModel.apply
                                                                                               └─► SwiftUI view
```

- `LiveSession.start` resolves the locale once, then starts one `LiveTranscriber` per speaker
  (`[.you, .others]`, or only `.others` without mic permission) and attaches each to the router.
  Buffers that arrive before a transcriber is attached are simply not shown live; they're still recorded.
- `LiveTranscriber` creates a `SpeechTranscriber` with `reportingOptions: [.volatileResults, .fastResults]`,
  asks `SpeechAnalyzer.bestAvailableAudioFormat` for the format it wants, and converts every capture
  buffer to it with `AVAudioConverter` (rebuilt if the input format changes).
- `LiveSession.stop` cancels a start still in progress, then for each transcriber finishes the input
  stream and calls `finalizeAndFinishThroughEndOfInput()`, so the last words still land in the window.

## The view model (`LiveTranscriptModel`)

The window shows **blocks**: consecutive speech from one speaker. Each block has `finalText` and
`volatileText`.

- A volatile update replaces the open block's `volatileText` for that speaker.
- A final update appends to `finalText`, clears `volatileText` and closes the block.
- A new update for a speaker without an open block continues the last block if it's the same speaker,
  otherwise starts a new block. So if You and Others alternate, the window alternates too.
- An empty block (a volatile guess that resolved to nothing) is removed.

### Echo

On speakers the microphone hears the other participants, which used to show up as **You**. The model
keeps the **Others** text from the last 8 s (`LiveTranscriptModel.echoWindow`, by arrival time, since the
two recognizers don't share a clock) plus the current volatile Others text, and:

- hides a **You** update (volatile or final) when it's an echo of that text, using the same rule as the
  final transcript (`TranscriptMerger.isEcho(_:of:)`, at least 50 % of its words);
- on every **Others** update, removes **You** blocks touched in the last 8 s that turn out to be an echo,
  for when the mic's copy is recognized before the original.

`reset()` clears everything at the start of each recording. All of this is covered by
`Tests/MurmurTests/LiveTranscriptModelTests.swift`.

## Mute

While recording (and only with microphone permission), a bar at the top of the window has a **Mute**
button; menu › **Mute Microphone** and the global shortcut **⌃⌥⌘M** (`MUTE_HOTKEY`) do the same. While
muted, the menu bar shows `mic.slash.fill` before the elapsed time. The shortcut does nothing when not recording. Muting does two things, in `AppDelegate.setMuted`:

1. **Murmur stops recording you.** `AudioRecorder.setMicrophoneMuted(true)` drops microphone buffers on
   the capture queue, so they reach neither `mic.caf` nor the live window. When you unmute, `TrackWriter`
   pads the gap with silence, so the tracks stay aligned. The system track (Others) is not affected.
   `LiveTranscriptModel.setMuted` also drops the half-recognized You text and ignores You updates.
2. **No app can hear you.** `MicrophoneMuter` mutes the default input device through Core Audio
   (`CoreAudioMicrophone`): the device's input mute (`kAudioDevicePropertyMute`) when it's settable,
   otherwise its input volume (`kAudioDevicePropertyVolumeScalar`) set to 0. What it changed (device UID,
   previous mute state or volume) is saved in `UserDefaults` (`MicrophoneMuteRecord`) *before* changing it.

Unmute, stopping the recording, quitting (`applicationWillTerminate`) and the next launch after a crash
all call `MicrophoneMuter.restore()`, which puts the device back exactly as it was (a mic that was
already muted stays muted) and clears the record.

If the microphone can't be muted (no settable mute or volume), Murmur still stops recording you and the
bar says, in orange, that other apps can still hear you. The meeting app's own mute button doesn't change:
it still shows you as unmuted, but it only receives silence.

Tests: `Tests/MurmurTests/MicrophoneMuterTests.swift` (fake device; tests never touch the real mic) and
the mute cases in `LiveTranscriptModelTests.swift`.

## Ask about the meeting

The bottom of the window is a quick chat about the recording in progress (`LiveChatView`, `LiveChatModel`,
`MeetingChat`).

- **What it sees:** only `LiveTranscriptModel.transcriptText`, one `You:` / `Others:` line per block, final
  and volatile text, captured when you press Return. That's everything the live window transcribed since
  this recording started, after echo removal and without anything said while muted. No older meetings, no audio.
- **Follow-ups:** each request carries the earlier answered questions of this recording as `<earlier_questions>`.
  Failed questions are shown in orange and left out of that history.
- **One at a time:** the field can't send while an answer is pending.
- **New recording:** `LiveSession.start` calls `chat.reset()`, which clears the thread and the draft. An answer
  that arrives after the reset is dropped. After a recording stops, you can still ask about it until the
  next one starts.
- **Engine:** `AgentCLI` with `MeetingChat.systemPrompt` (brief answers in the question's language, only what
  the transcript supports, say so when it doesn't). Same commands, isolation and fallback as summaries
  ([summaries.md](summaries.md)). Model: `CLAUDE_CODE_CHAT_MODEL` (default `sonnet`), or for Codex
  `CODEX_CHAT_MODEL`, then `CODEX_MODEL`. Measured: about 5 s per answer with Sonnet on a short transcript.
  Each question is one prompt on your plan, and its size grows with the transcript.
- **SwiftUI note:** the typed text lives in `LiveChatModel.draft`, not in `@State`: the Command Line Tools
  toolchain doesn't ship SwiftUI's macro plugin, so `@State` doesn't compile here.

## Failure behavior

Live transcription is optional. Any error (language not supported, speech model still downloading,
recognizer unavailable) is shown in the window's status line and logged. Recording and the final note
are not affected.
