# Notes

## Folder layout

```
~/MeetingNotes/
├── 2026-10-21-1430.md          the note
├── 2026-10-21-1430.m4a         mixed audio (both tracks)
├── 2026-10-21-1430-2.md        a second recording started in the same minute
├── 2026-10-21-1430-2.m4a
└── .recording-2026-10-21-1600/ raw tracks of a recording in progress, or left behind
    ├── mic.caf                 You
    └── system.caf              Others
```

`NOTES_DIR` changes the folder. The `.recording-*` folder is hidden and removed automatically once its
note is complete.

## Note anatomy

```markdown
# Mobile App Launch Moved to November 12

*Wednesday, 21 October 2026 at 14:00 · 20 s · [audio](2026-10-21-1400.m4a) · transcribed with Apple on-device speech · summarized with Claude Code*

## Summary
- … five bullets …

## Decisions
- …

## Action items
- [ ] **Maria**: Update the release notes (due Friday)
- [ ] **You**: Talk to the payments team (due tomorrow)

---

## Transcript

**[00:00] Others:** Okay, everyone, let's start the weekly sync. …

**[00:11] You:** Agreed. We will launch on November 12th. …
```

- Title: from the summary; "Meeting notes" if there's no summary yet.
- Meta line: date and time of the start, duration (`19 s`, `59 min`, `1 h 31 min`), a relative link to
  the audio, and which engines produced the transcript and summary.
- A `> **Note:** …` quote appears under the meta line when something failed (for example `Summary failed: …`).
- Everything above `---` is the summary; everything below is the transcript.

## Written step by step

`NotePipeline` rewrites the note after each step, so it's useful even if a later step fails or the
app quits:

| Stage | Summary area | Transcript area |
|---|---|---|
| Audio saved | `_Transcribing…_` | `_Pending._` |
| Transcribed | `_Summarizing…_` | the transcript (or `_No speech detected._`) |
| Done | the summary | the transcript |
| Summary failed | `> **Note:** Summary failed: …` | the transcript |
| Transcription failed | `> **Note:** <error>` | `_Pending._` |

Rendering lives in `Note.render()` (`Sources/Murmur/Note.swift`); tests in `NoteTests.swift`.

## Reprocessing and recovery

`NotePipeline.process(path:)` handles both cases:

- **An audio file** (`.m4a`, `.wav`…): transcribed as one mixed track, no You/Others labels. The note is
  written next to the file with the same name. The date comes from the file name if it's a stamp,
  otherwise now.
- **A `.recording-<stamp>` folder** (left behind if Murmur was quit or crashed mid-recording): the
  tracks are mixed, transcribed with labels, and the note keeps the original start time from the folder name.
  The folder is deleted once the note is complete.

Ways to run it:

```bash
make process FILE=~/MeetingNotes/2026-10-21-1430.m4a
make process FILE=~/MeetingNotes/.recording-2026-10-21-1600
/Applications/Murmur.app/Contents/MacOS/Murmur --process <path>   # same thing
```

or menu › **Process Audio File…**, which accepts files and folders. Reprocessing a file whose note
already exists overwrites that note, which is how you redo a failed summary.
