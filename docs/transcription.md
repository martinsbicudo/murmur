# Transcription

The final transcript comes from Apple's on-device speech recognition (`Speech` framework,
`SpeechAnalyzer` + `SpeechTranscriber`, macOS 26). No audio leaves the Mac, and no separate model
download or Homebrew package is needed.

## Language

`SpeechEngine.locale(for:)` turns `LANGUAGE` into a supported locale:

- `auto` (default) uses the system locale (`Locale.current`);
- anything else is parsed as a locale identifier (`pt-BR`, `en-US`, `es-ES`…);
- `SpeechTranscriber.supportedLocale(equivalentTo:)` maps it to the closest supported locale. If there
  is none, transcription fails with *Apple speech recognition doesn't support "…"*.

The recognizer handles one language per meeting. On a Mac with an unusual language/region pair
(for example English with a Brazilian region, `en_BR`), set `LANGUAGE` explicitly.

The first time a locale is used, `AssetInventory` downloads its speech model (once, managed by macOS).
The log shows `downloading speech model for <locale>`.

## File transcription

`SpeechEngine.transcribeFile` creates a transcriber with `attributeOptions: [.audioTimeRange]`, starts
`SpeechAnalyzer` on the `AVAudioFile` with `finishAfterFile: true`, and collects only **final** results.
Each result becomes a `TranscriptSegment(start:text:speaker:end:)`, where `start` and `end` are the
result's audio time range in seconds.

For a recording, each track is transcribed separately: `mic.caf` as You, `system.caf` as Others.
For a plain audio file (menu › Process Audio File… or `make process FILE=x.m4a`) there's one mixed
track, so segments have no speaker.

## Speaker labels and echo removal (`TranscriptMerger`)

Labels come from the source, not from voice analysis: whatever the microphone heard is **You**,
whatever the Mac played is **Others**. All remote participants are "Others".

On speakers instead of headphones, the microphone also hears the other participants, so their speech
appears in both tracks. The recognizer hears that echo badly ("put up a PR" becomes "have a beer"), and
it splits the two tracks into segments differently, so the copy is rarely word for word.
`TranscriptMerger.merge(you:others:)` drops a **You** segment when at least **50 %** of its words
(`echoContainment`, lower-cased letter/digit words) appear in the **Others** text whose time range
overlaps it, widened by **3 s** on each side (`echoWindow`).

Measured on a real 12-minute call on speakers: echoes scored 0.55–1.0, the owner's own lines 0.0–0.33.

Then all segments are sorted by start time. On an exact tie, Others comes first.

Limits: a very garbled echo can still slip through as You, and a short reply that repeats the other
person's words while they're talking ("Yes, Tuesday") can be dropped. Headphones avoid both.

## Rendering

`Transcript.markdown` renders each paragraph as

```
**[mm:ss] You:** text
```

(`h:mm:ss` past one hour; no label for unlabeled segments). Consecutive segments from the same speaker
are merged into one paragraph until it reaches about 600 characters, so the transcript reads as turns
instead of one line per recognizer result. The note's meta line says "transcribed with Apple on-device speech".

## Where to change things

| Change | Where |
|---|---|
| Echo thresholds | `TranscriptMerger.echoWindow`, `echoContainment` in `Transcript.swift` (shared with the live window) |
| Paragraph length | `Transcript.maxParagraphLength` |
| Recognizer options | `SpeechEngine.makeTranscriber` |
| Locale rules | `SpeechEngine.locale(for:)` |

Tests: `Tests/MurmurTests/TranscriptTests.swift` (rendering, merging, echo cases, tie order).
