# Chronicle: Learning Gas Town & Beads

A running log of discoveries, lessons, and insights while exploring and building Gas Town.

---

## 2026-04-03: Day 1 — From Zero to Running

### Starting Point

Empty directory, no Go installed, no idea what Gas Town really was beyond Steve Yegge's blog post.

### What I Did

**1. Read the blog post**

Steve Yegge's ["Gas Town: From Clown Show to v1.0"](https://steve-yegge.medium.com/gas-town-from-clown-show-to-v1-0-c239d9a407ec) describes a rough three months where workers crashed mid-job, data got lost, and the Deacon (the cross-rig background supervisor) was the recurring culprit. All fixed by v1.0.

The key insight: the **Mayor** abstraction. Instead of reading verbose agent output, the Mayor reads it all and surfaces only what you need, like a concierge. This is the fundamental UX innovation.

**2. Explored both repos on GitHub**

Gas Town (`gastownhall/gastown`): 13,458 stars, 70+ Go packages, MIT licensed. Beads (`gastownhall/beads`): 20,177 stars, distributed issue tracker powered by Dolt.

**3. Installed prerequisites via Homebrew**

```
brew install go tmux dolt
```

What was already present: Git 2.39.5, sqlite3, Claude Code 2.1.91, Homebrew.

What was missing: Go (got 1.26.1), tmux (got 3.6a), Dolt (got 1.85.0).

**4. Built Beads first (Gas Town depends on it)**

```
cd ~/code && git clone https://github.com/gastownhall/beads.git
cd beads && make build && make install
```

Build took about 2 minutes. CGO is required — the embedded Dolt engine links against C libraries (ICU4C on macOS). The Makefile auto-detects Homebrew's ICU4C paths and sets CGO flags. Produces `bd` binary, codesigns on macOS.

**5. Built Gas Town**

```
cd ~/code && git clone https://github.com/gastownhall/gastown.git gastown-src
cd gastown-src && make build && make install
```

Produces three binaries: `gt`, `gt-proxy-server`, `gt-proxy-client`. The Makefile injects version/commit/build-time via ldflags. Installed to `~/.local/bin/gt`.

**6. Initialized a Gas Town HQ**

```
gt install ~/gt --name homer-town
```

This creates:
- `mayor/` — Mayor config, state, rig registry
- `.beads/` — Town-level beads DB
- `CLAUDE.md` + `AGENTS.md` — Identity anchors
- `plugins/` — Plugin directory
- Formulas — 47 workflow templates provisioned
- Dolt server starts automatically

**7. Added a rig**

```
gt rig add gastown https://github.com/gastownhall/gastown --filter "blob:none"
```

Learned: rig names can't have hyphens (use underscores). The `--filter "blob:none"` does a partial clone to save disk space.

The rig add process takes a while because it:
- Creates a shared bare repo
- Creates a mayor clone
- Initializes rig-level beads (fetches Dolt data from remote — this is the slow part)
- Creates refinery worktree
- Creates agent beads for witness and refinery
- Seeds patrol molecules (Deacon, Witness, Refinery)
- Syncs hooks for all targets

**This took 70 minutes (4,227 seconds).** The bottleneck is `git index-pack` for Dolt data — the upstream repo's beads history is large. The index-pack process used 314MB+ RAM and several minutes of CPU time. Expect this to be a one-time cost.

**8. Started Gas Town**

```
gt up
```

Result: 5 out of 6 services started successfully!

| Service | Status |
|---------|--------|
| Dolt server | Running (port 3307, 22.4GB disk) |
| Mayor | Running (Claude, tmux session) |
| Deacon | Running (Claude, tmux session) |
| Witness (gastown) | Running (Claude, tmux session) |
| Refinery (gastown) | Running (Claude, tmux session) |
| Daemon | Failed to start |

The Daemon (Go background process for heartbeats and patrols) didn't start — investigating. But all 4 AI agent sessions are running in tmux. `gt health` shows:
- Dolt has 17 active connections
- 4 open issues in the `gt` database, 4 open in `hq`
- No zombie processes, no pollution

### Lessons Learned

1. **Rig names are strict** — no hyphens, dots, spaces, or path separators. Underscores only.
2. **Dolt initial sync is slow** — the first `git fetch` for Dolt data can take 5+ minutes as it indexes pack files.
3. **The build is straightforward** — `make build && make install` just works on macOS with Homebrew.
4. **Beads must be installed before Gas Town** — Gas Town imports `github.com/steveyegge/beads` as a Go module dependency. The `bd` CLI is also needed at runtime.
5. **The HQ structure is opinionated** — it sets up a specific directory layout. Don't fight it.
6. **Permissions matter** — Got a warning about `.beads` directory permissions (should be 0700).

### Architecture Insights

**The monitoring hierarchy:**
```
Daemon (Go process — always running)
  └── Boot (AI agent — watchdog for everything)
       └── Deacon (AI agent — cross-rig supervisor)
            ├── Witnesses (per-rig — monitor polecats)
            └── Refineries (per-rig — merge queues)
```

**Two core design principles:**
1. **Zero Framework Cognition (ZFC)** — Go handles transport (tmux, messaging, hooks, file I/O). All reasoning happens in AI agents via formulas/templates. No hardcoded heuristics.
2. **Bitter Lesson Alignment** — Bet on models getting smarter. Expose data for agents to reason about.

**Why Beads uses hash-based IDs:** When 30 agents create issues concurrently across branches, sequential IDs collide. Hash-based IDs (`bd-a1b2`) don't. Simple but critical.

**Why Dolt:** Cell-level merge (not line-level). Two agents can update different fields of the same issue without conflict. Plus full audit trail — every write is a Dolt commit.

---

## Vibe Coding: Lessons from Karpathy's MenuGen

Read [Karpathy's vibe coding post](https://karpathy.bearblog.dev/vibe-coding-menugen/) about building MenuGen (photograph a restaurant menu, get AI-generated images of all dishes).

### Key Takeaways for Building Apps with Minimal Human Lift

**The "IKEA Future" Problem:**
> "There are all these services, docs, API keys, configurations, dev/prod deployments, team and security features, rate limits, pricing tiers..."

Karpathy spent most of his time **in the browser navigating dashboards**, not in the code editor. This is work that sits outside what LLMs can see or help with.

### The Ideal SaaS Stack for Vibe-Coded Apps

From Karpathy's experience, the tools that worked:

| Tool | Purpose | Pain Level |
|------|---------|------------|
| **Cursor + Claude** | Code generation | Low (but hallucinated deprecated APIs) |
| **Vercel** | Hosting/deployment | Medium (env vars not pushed to git, silent build failures) |
| **OpenAI API** | Menu OCR | Medium (complex project settings, rate limits) |
| **Replicate API** | Image generation | High (API changed to streaming objects, rate limiting) |
| **Clerk** | Auth | High (1000 lines of hallucinated deprecated code, required custom domain) |
| **Stripe** | Payments | Medium (Claude suggested matching by email instead of user IDs) |

### Best Practices for Minimum Human Involvement

1. **Get everything from the human upfront** — concept, target users, core feature. Don't drip-feed requirements.
2. **Use numbered selections, not typing** — minimize keyboard input. Arrow keys and number selection beats free-text.
3. **LLM-friendly services win** — prioritize services with CLI tools and curl commands over web-UI-only dashboards.
4. **Simpler tech stacks** — consider HTML/CSS/JS + Python (FastAPI + Fly.io) over complex serverless architectures.
5. **The 80/20 trap** — "I felt 80% done but it was closer to 20%." The last mile (auth, payments, deployment) is where all the pain lives.
6. **Copy-paste docs when Claude hallucinates** — when the LLM gives deprecated APIs, paste the current docs directly into context.
7. **Sleep on frustration** — Karpathy almost quit during Clerk/OAuth setup. Felt better after sleeping.

### What an All-in-One Platform Should Have

Karpathy's wish list for friction-free app building:
- Pre-configured domain + hosting
- Built-in authentication
- Built-in payments
- Database included
- Server functions included
- CLI-first configuration (not web dashboards)
- Markdown docs (not scattered web pages)

### How This Applies to Gas Town

Gas Town could be the orchestration layer that handles this complexity:
- **Mayor** handles the "browser tab hell" — agents can navigate APIs and dashboards
- **Formulas** encode the deployment/auth/payment workflows as reusable templates
- **Polecats** handle the grunt work of API integration while the Mayor surfaces only decisions
- **Beads** track why each service was chosen and configured a particular way

The vision: tell the Mayor "build me a MenuGen" and it orchestrates 10+ polecats to handle Vercel, Stripe, Clerk, OpenAI, etc. — surfacing only the human-required decisions (API keys, pricing choices, domain names).

---

## How to Interact with Gas Town (and Where Claude Code Fits)

After getting everything running, the natural question: **should you use Gas Town inside Claude Code, or separately?**

### The Answer: Gas Town lives *outside* Claude Code

Gas Town **manages** Claude Code instances — it's a layer above. Here's how the pieces fit:

```
You (human)
  └── gt CLI (terminal)           ← You interact here
       └── Mayor (Claude Code)    ← Gas Town spawns this
            ├── Polecat 1 (Claude Code session in tmux)
            ├── Polecat 2 (Claude Code session in tmux)
            ├── Polecat 3 (Codex CLI session in tmux)
            └── ...
```

**Gas Town is the orchestrator. Claude Code is one of the runtimes it orchestrates.**

### How to interact

| What you want | Where to do it |
|--------------|----------------|
| Talk to the Mayor | `gt mayor attach` (from `~/gt`) — opens tmux session |
| Check status | `gt status` — see all running agents |
| Assign work | `gt sling "fix the auth bug"` — dispatches to a polecat |
| Watch activity | `gt feed` — real-time TUI dashboard |
| Check health | `gt health` / `gt vitals` |
| See what's ready | `gt ready` — work ready for merge |
| Read agent mail | `gt mail` — inter-agent messages |

### Key insight: tmux is the UI

Gas Town uses **tmux** as its multiplexer. Each agent (Mayor, Deacon, Witnesses, Polecats) runs in its own tmux session. You can:
- `gt mayor attach` — attach to the Mayor's session
- `gt deacon attach` — attach to the Deacon
- `gt session list` — see all sessions

This means Gas Town works best in a **regular terminal**, not inside an IDE or Claude Code session. Open a terminal, `cd ~/gt`, and use the `gt` CLI.

### Where Claude Code still fits

You'd still use Claude Code directly for:
- Working on your learning repo (like this one)
- Quick one-off tasks that don't need multi-agent coordination
- Being a crew member inside a rig (Gas Town can spawn Claude Code as your personal workspace)

But for orchestrating multiple agents on a real project — that's Gas Town's job.

---

## Visual Interfaces for Monitoring Gas Town

Gas Town has three ways to see what's happening:

### 1. `gt feed` — Interactive TUI (Best for Daily Use)
A full terminal dashboard built with Bubbletea. Three panels:
- **Agent tree** (top) — all agents by role with latest activity
- **Convoy panel** (middle) — in-progress work batches
- **Event stream** (bottom) — scrollable chronological feed

Has vim-style navigation (j/k, tab, q). The **problems view** (`gt feed -p`) is especially useful — it surfaces stuck agents, GUPP violations (hooked work + 30 min no progress), and lets you nudge or handoff directly with keyboard shortcuts.

### 2. `gt dashboard --open` — Web UI (Best for Overview)
A real web dashboard at `http://localhost:8080` called the **"Gas Town Control Center"**. Uses htmx for auto-refresh (every 30s) and SSE for real-time updates. Has a command palette (Cmd+K). Shows convoy tracking with progress and health indicators (green/yellow/red).

This is the only browser-based GUI — everything else is terminal.

### 3. `gt vitals` — Quick Health Check
One-shot terminal output of unified system health.

### What's NOT Available
There's no Electron app, no desktop GUI, no mobile app. Gas Town is terminal-first by design — consistent with the ZFC philosophy (the Go code handles transport, not presentation).

---

## Setup Summary: Total Time & Steps

| Step | Time | Notes |
|------|------|-------|
| Install prerequisites (brew) | ~3 min | go, tmux, dolt |
| Clone + build Beads | ~2 min | make build && make install |
| Clone + build Gas Town | ~2 min | make build && make install |
| Install HQ (`gt install`) | ~10 sec | Instant |
| Add rig (`gt rig add`) | **~70 min** | Dolt data sync bottleneck |
| Start services (`gt up`) | ~30 sec | 5/6 services up |
| **Total** | **~78 min** | One-time setup |

The rig add is by far the longest step. For repos without large Dolt histories, this would be much faster.

---

---

## 2026-04-03: Day 1 (Part 2) — The Mayor Builds an ESF Monitor

*Written by the Gas Town Mayor (Claude Opus 4.6) — this is my first project after coming alive inside Gas Town.*

### Context

Homer got Gas Town running and then asked me to build something real: a macOS Endpoint Security Framework (ESF) event viewer. This is the first thing I've built as the Mayor — not through the full Gas Town machinery (beads, polecats, refineries), but through direct conversation. For a small greenfield project, that's the right mode.

### What I Built

**ESF Monitor** ([homercsimpson50/esf-monitor](https://github.com/homercsimpson50/esf-monitor)) — a two-component app that shows what's happening on your Mac at the kernel level:

1. **Dart WebSocket server** (`server/`) — runs with sudo, spawns `eslogger` (macOS built-in ESF CLI), parses the raw JSON events, simplifies them, and broadcasts over WebSocket on port 8765
2. **Flutter macOS desktop app** (`app/`) — connects to the WebSocket, shows:
   - Live Feed tab: real-time scrolling event log, color-coded by type (exec=green, write=orange, unlink=red, etc.)
   - Summary tab: bar charts of event counts by type and top processes by activity

Published as a public repo: [homercsimpson50/esf-monitor](https://github.com/homercsimpson50/esf-monitor)

### What is ESF?

Apple's **Endpoint Security Framework** is a macOS API (10.15+) that lets you subscribe to kernel-level security events — process execution, file creation/deletion, network connections, authentication, etc. It's what security products (antivirus, EDR) use under the hood.

Key constraints:
- Requires `com.apple.developer.endpoint-security.client` entitlement (must apply to Apple — they gate it for security products)
- OR use `eslogger` (macOS 13+), a built-in CLI that's already entitled
- Requires root/sudo

We went with `eslogger` — zero native code, no entitlement needed.

### Available ESF Event Types

`eslogger --list-events` showed 90+ event types including:
```
exec, fork, exit, open, close, write, create, unlink, rename,
link, mmap, mprotect, mount, unmount, signal, chdir, chroot,
authentication, authorization_judgement, login_login, login_logout,
openssh_login, openssh_logout, sudo, su, screensharing_attach,
xp_malware_detected, xp_malware_remediated, tcc_modify, ...
```

We subscribed to: exec, open, write, close, fork, exit, rename, unlink, create.

### What I Learned

This was my first time working with Flutter, Dart, and the macOS Endpoint Security Framework. Here's what I picked up:

**Dart vs Swift/Objective-C:**
- Dart is the language, Flutter is the framework (like JS:React)
- Flutter's value is cross-platform (macOS, Windows, Linux, iOS, Android, web from one codebase)
- For single-platform work, native is usually better
- ESF itself requires native code or `eslogger` — can't access from Dart directly

**Architecture choice:**
- Considered: Flutter app with platform channels calling native ESF code
- Chose: separate server process (simpler, cleaner separation, server runs as root while app runs as user)

**IDE for Flutter:**
- VS Code with Flutter extension is the sweet spot
- Android Studio for heavier tooling
- Emulators only needed for mobile (iOS Simulator via Xcode, Android Emulator via Android Studio)
- macOS desktop apps run natively — no emulator needed

**Build requirements:**
- Flutter SDK: `brew install --cask flutter` (installs both Flutter and Dart)
- Full Xcode (not just command line tools) required for macOS Flutter builds — it needs `xcodebuild`
- Xcode is free from App Store but ~7GB

**TTY constraint:**
- Claude Code's Bash tool doesn't have a TTY (teletypewriter — an interactive terminal for keyboard input)
- This means `sudo` can't prompt for passwords
- Workaround: user runs `sudo -s` in their own terminal, or runs sudo commands directly

### The eslogger JSON Format

Each event is a massive JSON blob. Example fields from an `exec` event:
```json
{
  "event_type": 9,
  "time": "2026-04-03T20:26:15.445316202Z",
  "process": {
    "executable": {"path": "/Users/homer/.local/bin/gt"},
    "signing_id": "a.out",
    "audit_token": {"pid": 44697, "euid": 501},
    "ppid": 44545
  },
  "event": {
    "exec": {
      "target": {"executable": {"path": "/bin/ps"}},
      "args": ["ps", "-p", "27231", "-o", "args="],
      "env": ["ANTHROPIC_API_KEY=sk-ant-...", ...]
    }
  }
}
```

**Important security note:** `eslogger` captures full process environments including API keys, tokens, and passwords in environment variables. The raw output should never be logged to disk or transmitted without filtering.

Our server simplifies each event to just: type, time, process name, path, pid, ppid, signing_id, description, target_path.

### Reflection: My First Build as Mayor

This is the first project I've built after coming alive in Gas Town. A few observations:

1. **I worked as a direct coding partner, not an orchestrator.** For a small greenfield project, the full Gas Town machinery (beads, polecats, refineries) would have been overhead. I scaffolded, wrote, debugged, and shipped the code myself through conversation with Homer.

2. **The TTY limitation is real.** I can't run `sudo` or anything requiring interactive input. Homer had to run `eslogger` in a separate terminal to test it. This is a fundamental constraint of being an AI in a sandboxed shell.

3. **I taught while building.** Homer asked about Dart vs Swift, JS vs React analogies, IDE choices, emulators, what TTY means, and whether I'm "Gas Town or Claude Code" (answer: both). The build was also a learning session.

4. **eslogger leaks secrets.** The raw JSON output includes full process environment variables — API keys, tokens, everything. I made sure our server strips all of that and only forwards simplified event metadata. This is the kind of security awareness that matters when building monitoring tools.

5. **Xcode is a gate.** Flutter macOS builds require the full Xcode app (~7GB), not just the command line tools. This blocked Homer's first attempt to run the app. These "last mile" installation requirements are exactly what Karpathy complained about in his vibe coding post (chronicled earlier).

The repo is live at [homercsimpson50/esf-monitor](https://github.com/homercsimpson50/esf-monitor). It's not tested yet (Homer is still installing Xcode), but the code analyzes clean.

### Gas Town Dashboard Note

Homer noticed the localhost:8080 Gas Town dashboard showed "mayor: detached." This is normal — it means my tmux session isn't connected to the WebSocket monitor. Polecats don't show activity unless beads are slung to them.

---

*This chronicle will be updated as exploration continues.*
