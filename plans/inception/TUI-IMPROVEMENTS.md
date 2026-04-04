# Agent Feed TUI Improvements

Feedback from live inception test — watching containerized agents work in real time.

## P1: Fix summarizer for real Claude Code events

The `SummarizeToolUse` function expects `{"type":"tool_use","name":"Bash","input":{...}}`
but real Claude Code OTLP events have the content as just `{"command":"gt done 2>&1"}`.
The tool name may be in a different field. Falls back to raw JSON truncation — ugly.

**Fix:** Parse the real event format in `summarize.go`. Check what fields
VictoriaLogs actually stores from Claude Code's OTLP export.

## P1: Clean up display format

Current: `16:27:32  in  😺 rust  Bash: {"command":"gt done 2>&1","timeout":60000`
Wanted:  `16:27:32  in  😺 rust  gt done`

- Drop tool name prefixes ("Bash:", "Read:", "Edit:") — extract the useful content
- For Bash: show the command only
- For Read: show the filename only
- For Edit: show the filename only
- For Grep: show the pattern only

## P1: Pin column headers

Add a fixed header row above the scrolling content:
```
TIME      RIG          ROLE  AGENT      DESCRIPTION
────────  ───────────  ────  ─────────  ──────────────────────────
16:27:32  inception    😺    rust       gt done
```

## P1: Local timezone

Container runs in UTC. The TUI should either:
- Accept a `TZ` env var and convert
- Or display in the user's local timezone (detect from host)

`gtc feed` should pass `-e TZ=$(date +%Z)` or the IANA timezone.

## P2: Split-screen LLM summary (like Teams/Meet AI notes)

Real-time AI summary of what agents are doing, displayed in a right-side panel.

**How it would work:**
- Buffer last N events (e.g., 30 seconds of activity)
- Periodically send to Claude API: "Summarize what these agents are doing in 2-3 sentences"
- Display rolling summary in a right panel, updating every ~10 seconds
- Toggle with a keybind (e.g., `s` for summary)

**Example output:**
```
┌─ Events ──────────────────────┬─ Summary ─────────────────────┐
│ 16:27:32 rust  gt done        │ Polecat rust just finished    │
│ 16:27:28 rust  git add ...    │ building the /version endpoint│
│ 16:27:21 rust  go test        │ for inception-test. Tests     │
│ 16:27:14 mayor gt sling ...   │ passed, committed. Mayor is   │
│ 16:27:07 mayor ls polecats    │ now slinging monorepo work.   │
│                               │                               │
│                               │ Updated 5s ago                │
└───────────────────────────────┴───────────────────────────────┘
```

This is the "Google Meet AI notes" equivalent for agent orchestration.
