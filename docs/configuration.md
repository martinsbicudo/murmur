# Configuration

All settings live in `~/.config/murmur/.env` (menu › **Settings (.env)…** opens it in TextEdit and
creates it from the bundled template if it's missing; `make deps` also creates it). The template is
[`.env.example`](../.env.example).

The file is re-read at the start of every recording and every processing job, so changes apply
without restarting, except `HOTKEY` and `MUTE_HOTKEY`, which are registered at launch.

## Settings

| Key | Default | Values | Effect |
|---|---|---|---|
| `SUMMARY_ENGINE` | `claude-code` | `claude-code`, `codex` | Preferred summary engine; the other is the fallback ([summaries.md](summaries.md)) |
| `LANGUAGE` | `auto` | `auto` or a locale (`pt-BR`, `en-US`, `es-ES`…) | Recognition language for live and final transcripts |
| `HOTKEY` | `ctrl+option+cmd+r` | modifiers + one letter/digit, or `off` | Global start/stop shortcut. Restart Murmur after changing |
| `MUTE_HOTKEY` | `ctrl+option+cmd+m` | same as `HOTKEY`, or `off` | Global mute/unmute while recording ([live-transcript.md](live-transcript.md#mute)). Must differ from `HOTKEY`. Restart Murmur after changing |
| `LIVE_TRANSCRIPT` | `on` | `on`, `off` | Open the live window automatically when recording starts |
| `NOTES_DIR` | `~/MeetingNotes` | path, `~` allowed | Where notes, audio and raw tracks go |
| `CLAUDE_CODE_MODEL` | Claude Code's default | e.g. `opus`, `sonnet` | Passed as `--model` |
| `CLAUDE_CODE_BIN` | auto-detected | path | Use a specific `claude` binary |
| `CODEX_MODEL` | Codex's default | a Codex model name | Passed as `-m` |
| `CLAUDE_CODE_CHAT_MODEL` | `sonnet` | e.g. `haiku`, `sonnet`, `opus` | Model for questions in the live window ([live-transcript.md](live-transcript.md#ask-about-the-meeting)) |
| `CODEX_CHAT_MODEL` | `CODEX_MODEL` | a Codex model name | Same, when the chat runs on Codex |
| `CODEX_BIN` | auto-detected | path | Use a specific `codex` binary |
| `FFMPEG_PATH` | auto-detected | path | Use a specific `ffmpeg` |

Empty values count as unset. Lines starting with `#` are comments, `export KEY=value` is accepted, and
values may be wrapped in single or double quotes.

## Environment overrides

Environment variables with the same names override the file (only these keys and the `CLAUDE_CODE_*` /
`CODEX_*` prefixes are read). That's mostly useful for testing the CLI mode:

```bash
NOTES_DIR=/tmp/test LANGUAGE=en-US SUMMARY_ENGINE=codex \
  /Applications/Murmur.app/Contents/MacOS/Murmur --process /tmp/test/meeting.m4a
```

## Where things live

| Path | What |
|---|---|
| `~/.config/murmur/.env` | Settings |
| `~/MeetingNotes/` | Notes, audio, `.recording-*` raw tracks |
| `~/Library/Logs/Murmur.log` | Log (menu › Show Log) |
| `/Applications/Murmur.app` | Installed app (bundle id `local.murmur.app`) |
| `~/Library/Keychains/murmur-signing.keychain-db` | Local code-signing identity ([development.md](development.md)) |

Code: `Sources/Murmur/Config.swift`. Tests: `ConfigTests.swift`.
