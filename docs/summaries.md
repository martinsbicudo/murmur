# Summaries

Summaries are produced only by **Claude Code** (default) or **Codex**, through the CLI login that
already exists on the Mac. There are no API keys and no local models; that is a product decision.

The command lines, engine choice and fallback below live in `AgentCLI` and are shared with the live
chat ([live-transcript.md](live-transcript.md#ask-about-the-meeting)), which only changes the prompt and
the model.

## Choosing the engine

`SUMMARY_ENGINE=claude-code` (default) or `SUMMARY_ENGINE=codex`. An unknown value falls back to
Claude Code.

`AgentCLI.engines(preferred:isInstalled:)` returns the preferred engine first and the other one
second, keeping only the installed ones. Murmur tries them in that order and stops at the first
success. So if Claude Code is preferred but fails (for example, logged out), Codex is tried, if installed.
The engine actually used, plus the model if one is set, appears in the note's meta line ("summarized with Claude Code").

Binaries are looked up in `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `/bin`,
or at `CLAUDE_CODE_BIN` / `CODEX_BIN` if set.

## Claude Code

Murmur runs `claude` in a fresh empty temp folder, with the transcript on stdin:

```bash
claude -p --output-format json \
  --setting-sources project --strict-mcp-config --no-session-persistence \
  --tools "" --system-prompt "<prompt>" [--model <CLAUDE_CODE_MODEL>]
```

| Flag | Why |
|---|---|
| `-p --output-format json` | Headless; the JSON result has `is_error`, `subtype` and `result` |
| `--setting-sources project` (in an empty folder) | Ignores your user settings, hooks and plugins |
| `--strict-mcp-config` | No MCP servers |
| `--tools ""` | No tools at all; it can only write text |
| `--no-session-persistence` | Nothing saved to your Claude Code history |
| `--system-prompt` | Replaces the coding-agent prompt with the meeting-notes prompt |

`--bare` is not used because it skips the OAuth login, which is how Murmur avoids needing an API key.

`AgentCLI.claudeCodeText` treats `is_error: true` or a `subtype` other than `success` as a failure
and surfaces the CLI's message (for example "Not logged in · Please run /login"). If the process exits
non-zero, the JSON on stdout is still parsed so the real message is shown instead of an empty error.

**Environment quirk:** Claude Code reads its OAuth credentials from the Keychain and needs `USER`
and `LOGNAME` to find them. Apps launched by Finder or launchd may not have them, so `Shell.environment`
always sets `USER`, `LOGNAME`, `HOME` and a `PATH` that includes the search paths above.

## Codex

```bash
codex exec --skip-git-repo-check --ephemeral --ignore-user-config --ignore-rules \
  -s read-only -C <empty temp dir> -o <temp dir>/answer.md [-m <CODEX_MODEL>] -
```

The prompt (system prompt + "Do not run commands or read files; answer only from this transcript." +
transcript) is sent on stdin (`-`). The final message is read from the `-o` file. The sandbox is read-only and the
session is ephemeral, and your Codex config and rules are ignored.

## The prompt

`Summarizer.systemPrompt` asks for Markdown in exactly this shape, in the meeting's language:

```markdown
# <short title, max 8 words>

## Summary
- <exactly 5 bullets>

## Decisions
- <each decision, or "- None recorded.">

## Action items
- [ ] **<Owner>**: <task> (due <date>, only if mentioned)
```

It explains the labels (You = the user's mic, Others = everyone else, unlabeled = one mixed recording),
tells the model not to invent names, dates or commitments, and sets the owner rule: **You** when the
user commits, the person's name when it's clear, otherwise **Unassigned**.

The transcript is sent as `<transcript>…</transcript>`. `Summarizer.parse` takes the first `# ` line as
the note title (default "Meeting notes") and the rest as the summary body.

## Cost and privacy

Each summary is one prompt on your Claude (or ChatGPT/Codex) plan. A one-hour meeting is roughly
10–15k tokens of transcript. `CLAUDE_CODE_MODEL=sonnet` (or a cheaper `CODEX_MODEL`) spends less.
Only the transcript text is sent: Claude Code to Anthropic, Codex to OpenAI. The audio never leaves the Mac.

## Failure handling

| Error | Message in the note |
|---|---|
| Neither CLI found | `Summary failed: Claude Code (claude) or Codex (codex) isn't installed…` |
| CLI error / not logged in | `Summary failed: Claude Code failed: <CLI message>` |
| Empty answer | `Summary failed: <engine> returned an empty answer.` |

In every case the note keeps the transcript, and **Process Audio File…** can rerun it later.

Tests: `Tests/MurmurTests/SummarizerTests.swift`, `EngineSelectionTests.swift`.
