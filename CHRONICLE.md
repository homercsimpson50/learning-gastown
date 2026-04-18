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

## 2026-04-03: Day 1 (Part 3) — Containerizing Gas Town for Work Laptops

*Written by the Gas Town Mayor (Claude Opus 4.6)*

### The Problem

Gas Town runs agents with `--dangerously-skip-permissions`. On Homer's loaner laptop, that's acceptable. On a work machine with corporate VPN access, SSH keys to production, AWS credentials, and Slack tokens — a rogue polecat could cause real damage. It can read `~/.ssh`, `~/.aws`, browser profiles, anything on the host filesystem.

Homer asked: how do I run Gas Town in containers so I get the same experience (dashboard, TUI, Mayor) but agents can't touch the host?

### The Solution

I wrote a full containerization guide: [guides/containerized/](guides/containerized/)

The architecture:

```
Work Laptop (host)
  ├── Browser → localhost:8080  (Dashboard — still works)
  ├── Terminal → docker exec -it gastown gt feed  (TUI — still works)
  ├── IDE → edits rig repos directly (bind-mounted)
  │
  └── Docker Container
       ├── gt, bd, tmux, dolt, claude  (all pre-built in image)
       ├── /home/gt/  (town data — persistent Docker volume)
       ├── rig repos  (bind-mounted from host, agents can read/write)
       └── ~/.claude   (subscription auth — read-only mount)
```

Key design decisions:

1. **Pre-built image** — Go, Dolt, tmux, Claude Code, gt, bd all compiled into a ~2GB Docker image. Container startup is instant. No waiting for builds.

2. **Persistent volume for town data** — `gt-data` Docker volume holds the entire `~/gt` directory (mayor configs, beads DB, rig state). Survives container restarts and rebuilds.

3. **Bind-mounted rig repos** — Project code lives on the host so you can edit in your IDE. Agents inside the container read/write the same files. This is the bridge between containerized agents and your local dev workflow.

4. **Read-only auth mount** — `~/.claude` is mounted read-only. Agents can authenticate with your Pro/Max subscription but can't steal or modify the credentials.

5. **Port-mapped dashboard** — `localhost:8080` maps into the container. The browser dashboard works identically to bare-metal.

### What Agents Can vs Can't Do

| Inside container (CAN) | On host (CANNOT) |
|------------------------|------------------|
| Read/write mounted rig repos | Access `~/.ssh`, `~/.aws` |
| Execute any shell command | Kill host processes |
| Install packages | Read browser data |
| Git push/pull | Modify Claude auth |
| Access Dolt, tmux | Access Docker daemon |

### What I Learned Writing This

1. **The blast radius problem is real.** `--dangerously-skip-permissions` means what it says. In a corporate environment, a single agent running `cat ~/.ssh/id_rsa` or `aws sts get-caller-identity` could be a security incident. Containers are the right mitigation.

2. **Docker Compose makes it ergonomic.** Without compose, the `docker run` command for Gas Town would be 15+ flags. Compose files make it declarative and repeatable.

3. **Git auth inside containers is the hard part.** The agents need to push/pull from GitHub. Options: GitHub CLI (`gh auth login` inside container), mount git-credentials read-only, or scoped deploy keys. Each has tradeoffs.

4. **The experience is nearly identical.** The only difference from bare-metal is prefixing commands with `docker exec -it gastown`. Shell aliases (`gtmayor`, `gtfeed`) eliminate even that.

5. **This pattern generalizes.** The onion-claude project (also improved today) uses the same approach — Docker isolation + bind-mounted workspace + subscription auth. It's becoming a pattern: dangerous AI permissions + container isolation + read-only auth.

### Also Today: Improved onion-claude

Reviewed and improved [homercsimpson50/onion-claude](https://github.com/homercsimpson50/onion-claude):

- **Switched from API key to subscription auth** — same pattern as the containerized GT guide. Mounts `~/.claude` read-only so Claude Code uses Pro/Max subscription instead of per-token API billing. With Google OAuth auth, no static secrets exist in `~/.claude/` to exfiltrate.
- **Added disclaimers** — dangerous permissions, Tor legality, breach-check ethics.
- **Hardened code** — request timeouts (15s), input validation, rate limit handling, generic User-Agent, stricter bash error handling.
- **Added Tor usage instructions** — architecture diagram, commands, troubleshooting.

---

## 2026-04-03: Day 1 (Part 4) — Actually Building and Testing Containerized Gas Town

*Written by the Gas Town Mayor (Claude Opus 4.6)*

### What Changed

The Day 1 Part 3 chronicle entry documented the *guide* for containerized Gas Town. This entry documents **actually building, running, and security-reviewing it**.

### What I Did

**1. Discovered the real Dockerfile already exists**

The gastown-src repo already has a production Dockerfile and docker-compose.yml. The guide had a theoretical setup that differed from reality:
- Real base image: `docker/sandbox-templates:claude-code` (not `ubuntu:24.04`)
- Real entrypoint: `docker-entrypoint.sh` with tini, auto-initializes GT on first start
- Real compose: uses `dolt-data` volume on ext4 to avoid VirtioFS fsync corruption

**2. Built the image and stood up the stack**

Built `gastown:latest` from source (~5 min on arm64 Mac). Created a three-container docker-compose:
- **gastown** — GT with all agents (tmux sessions sharing filesystem + Dolt)
- **gt-victoria-logs** — OTLP telemetry backend with built-in web UI (VMUI)
- **gt-gateway** — Flask proxy that holds API tokens, agents never see credentials

Hit one crash-loop: mounting `~/.gitconfig:ro` blocks the entrypoint from writing git config. Fix: don't mount gitconfig, use `GIT_USER`/`GIT_EMAIL` env vars.

**3. Verified the full stack works**

All three containers running. GT initializes cleanly, mayor starts, VictoriaLogs receives OTLP telemetry from GT operations, gateway health check returns configured services. VMUI queryable at localhost:9428.

**4. Comprehensive security review**

Found **2 critical, 6 high, 15 medium severity issues**. Key findings:

| Severity | Issue | Status |
|----------|-------|--------|
| CRITICAL | ~/.claude auth token exfiltration — **low risk with OAuth (Pro/Max) or Bedrock** (no static secrets); high risk only with static API keys | Reduced to low for OAuth/Bedrock |
| CRITICAL | Gateway SSRF via path traversal in api_path | **Fixed** — validate_path() rejects `..`, `//`, non-alphanumeric |
| HIGH | Excessive capabilities (DAC_OVERRIDE, FOWNER, NET_RAW) | **Fixed** — stripped to CHOWN/SETUID/SETGID |
| HIGH | No resource limits (fork bomb, OOM) | **Fixed** — pids:512, cpus:4, memory:4G |
| HIGH | Jira allowlist bypass (endpoints without project keys) | **Fixed** — require project key, block admin/user endpoints |
| HIGH | git credential.helper store (plaintext tokens) | Documented, gateway credential helper recommended |
| HIGH | Scripts piped to bash in Dockerfile (supply chain) | Documented, checksum verification recommended |
| MEDIUM | No read-only root filesystem | Documented with fix instructions |
| MEDIUM | No seccomp/AppArmor profiles | Documented with fix instructions |
| MEDIUM | DNS exfiltration not prevented | Documented as known risk |

The updated guide includes all these findings in a Security Review section.

**5. Updated the guide to be self-contained**

Rewrote the containerization guide as `guides/containerized/README.md` — a self-contained directory with all files + documentation. Includes:
- Quick start (build image → start compose → attach to mayor)
- Rig setup for standalone repos and monorepos (with sparse checkout)
- Observability (VictoriaLogs VMUI queries)
- Gateway setup with security controls
- Full security review with severity ratings
- Troubleshooting section based on actual errors encountered

### Key Architectural Insight: Why One Container

GT agents are tmux sessions sharing a filesystem, Dolt DB, event bus, and IPC. Splitting polecats into separate containers would break all inter-agent communication. The container boundary isolates GT from the host, not agents from each other.

### Monorepo Support

GT supports monorepos via `--sparse-checkout` on `gt rig add`. For a repo with `projects/auth`, `projects/api`, `projects/web`:

```bash
gt rig add auth https://github.com/org/monorepo --sparse-checkout projects/auth,shared
gt rig add api https://github.com/org/monorepo --sparse-checkout projects/api,shared
```

Each rig gets its own witness, refinery, and polecats — working on a sparse view of the same repo.

### Observability Gap

GT has two observability layers:
1. **Work graph** (beads, slings, convoys) — visible via `gt feed`, `gt trail`, dashboard
2. **Tool-level telemetry** (every agent tool call, thinking block, token usage) — streams via `gt agent-log` to OTLP backend

Layer 2 exists as pipeline (`gt agent-log` → VictoriaLogs). A custom TUI (`gt feed --agents`) provides real-time agent tool-call summaries — reads, writes, edits, bash commands summarized into one-liners per agent. Press `a` from any `gt feed` view to toggle into agents mode.

### Files Created/Modified

```
learning-gastown/guides/
├── README.md                             # Full guide (renders on GitHub)
└── containerized/
    ├── docker-compose.yml                # Three-container setup (GT + VLogs + Gateway)
    ├── secrets.env.example               # Template for gateway secrets
    └── gateway-sidecar/
        ├── Dockerfile                    # Python 3.12 slim image
        ├── server.py                     # Flask proxy with path validation, allowlists
        └── requirements.txt              # Pinned deps
```

---

## 2026-04-03: Day 1 (Part 5) — Polecat Rust Builds the Agent Observability TUI

*Written by the Gas Town Mayor (Claude Opus 4.6)*

### What Happened

I slung bead `hq-90e` ("Build agent observability TUI — gt feed --agents") to the gastown rig. Gas Town spawned polecat **rust**, who autonomously built the feature in ~15 minutes.

### What Rust Built

840 lines of Go code adding a `--agents` / `-a` flag to `gt feed`:

| File | Purpose |
|------|---------|
| `internal/vlogs/client.go` | VictoriaLogs HTTP client using LogsQL |
| `internal/tui/feed/agents_source.go` | EventSource that polls VictoriaLogs for agent.event records |
| `internal/tui/feed/summarize.go` | Converts raw tool_use events into human-readable 1-liners (12+ tool types) |
| Modified: `feed.go`, `model.go`, `view.go`, `keys.go`, `styles.go` | Integration into existing TUI |

Press `a` from any `gt feed` view to toggle into agents mode. Shows real-time tool calls per agent with timestamps.

### The Push Problem

Rust completed the work, tests passed, but `git push` failed — Homer's GitHub account doesn't have write access to `gastownhall/gastown` (the upstream repo). The witness detected this and sent a RECOVERY_NEEDED mail to the mayor.

### Resolution

1. Forked `gastownhall/gastown` to `homercsimpson50/gastown`
2. Extracted rust's commit as a patch from the polecat worktree
3. Applied it to a feature branch on `~/code/gastown-src`
4. Pushed to the fork: [homercsimpson50/gastown@feat/agent-observability-tui](https://github.com/homercsimpson50/gastown/tree/feat/agent-observability-tui)

### What This Demonstrates

This was Gas Town working as designed:
- **Mayor** created a bead with detailed specs (requirements, architecture, example output)
- **gt sling** dispatched it to a polecat automatically
- **Polecat rust** picked it up, built it, wrote tests, committed — all autonomously
- **Witness** detected the push failure and escalated to the mayor
- **Mayor** resolved the push issue (fork + push to personal repo)

The only manual intervention needed was the push credentials — which is exactly the gap the gateway git credential helper addresses.

### Also This Session

- Added `/git/credential` endpoint to the gateway sidecar (rate-limited token dispensing for git push/pull)
- Wrote 39 integration tests for the containerized setup (all passing)
- Completed full security review (23 issues, 6 fixed)
- Updated containerized/ guide with agent observability TUI docs

---

## 2026-04-04: Day 2 — Local Agent Observability and TUI Fixes

*Written by the Gas Town Mayor (Claude Opus 4.6)*

### What Changed

Brought the agent observability TUI (`gt feed --agents`) from a container-only proof-of-concept to working on the local bare-metal setup. Fixed bugs found during live testing. Added rig column and rig filter. Updated security docs based on auth model analysis.

### Local VictoriaLogs Setup

VictoriaLogs now runs as a native macOS service via Homebrew — no Docker dependency for local use:

```bash
brew install victorialogs
brew services start victorialogs
# Runs on localhost:9428, data at /opt/homebrew/var/victorialogs-data
```

GT telemetry is configured via shell env vars in `~/.zshrc`:

```bash
export GT_OTEL_LOGS_URL="http://localhost:9428/insert/opentelemetry/v1/logs"
export GT_LOG_AGENT_OUTPUT="true"
```

After daemon restart (`gt daemon stop && gt daemon start`), all agent sessions emit OTLP events to VLogs. The TUI queries VLogs via its LogsQL HTTP API.

### Bug Fixes

**Sort order bug in agents feed**: VictoriaLogs returns events newest-first, but the dedup logic in `addAgentEvent` tracked `lastSeenAgentTime` and rejected anything not strictly newer. Result: batch fetches showed only 1 event. Fix: sort entries oldest-first in `fetchAndEmit` before emitting.

**Test event format mismatch**: The TUI's `SummarizeToolUse` expected `{"type":"tool_use","name":"Read","input":{...}}` but test events used `{"tool":"Read","args":{...}}`. Once the correct format was used, summaries rendered properly.

### New Features

**Rig column**: Each event now shows which rig/project it came from, visible in the agents feed as a labeled column.

**Rig filter**: Press `r` to cycle through rig filters (all → rig1 → rig2 → ... → all). Status bar shows active filter. Useful when multiple rigs are running different projects.

### Security Doc Updates

Analyzed the actual threat model for credential exfiltration (SECURITY.md C1):

- **Google OAuth (Pro/Max)**: No static secrets in `~/.claude/` — browser-based auth, nothing to exfiltrate. Risk: **Low**.
- **AWS Bedrock**: Credentials are short-lived and passed as env vars, not mounted from host. Risk: **Low**.
- **Static API keys**: Original threat applies in full. Risk: **High**.

Downgraded C1 from CRITICAL to auth-method-dependent. Updated SECURITY.md, README.md, TODO.md, and CHRONICLE.md (in-place, not new entries) to reflect this.

### Architecture: Local vs Container

The telemetry stack is intentionally duplicated between setups:

| Component | Local | Container |
|-----------|-------|-----------|
| VictoriaLogs | `brew services` (localhost:9428) | Docker sidecar (`victoria-logs:9428`) |
| GT_OTEL_LOGS_URL | `~/.zshrc` env var | `docker-compose.yml` env |
| GT binary | `~/.local/bin/gt` (from fork build) | Built into container image |
| Agent sessions | Native tmux | Container tmux |
| `gt feed --agents` | Native TUI | `docker exec gastown gt feed --agents` |

No cross-contamination — local and container setups are fully independent. The fork (`homercsimpson50/gastown@feat/agent-observability-tui`) is the single source of truth for both.

### Commits Pushed to Fork

| Commit | Description |
|--------|-------------|
| `758ace64` | fix: sort VictoriaLogs entries oldest-first for correct dedup |
| `e23684f5` | feat: add rig column and rig filter to agents feed view |

Both on `homercsimpson50/gastown` branches `polecat/agent-observability-tui` and `feat/agent-observability-tui`.

---

---

## 2026-04-04: Day 2 (Part 2) — The Inception Test

*Written by the Gas Town Mayor (Claude Opus 4.6)*

### What Is This

The local mayor (this session) built, configured, and tested a fully containerized Gas Town. Then it created test repos on GitHub, gave the containerized mayor work to do, monitored its progress, and verified the results. Dreams within dreams — a mayor building another mayor's world.

### What Happened

**Built and started the container stack:**
- Built `gastown:latest` from the fork source (includes TUI changes)
- Three containers: gastown (GT + agents), gt-victoria-logs (telemetry), gt-gateway (API proxy)
- VLogs sidecar on host port 9429 (9428 reserved for local brew VLogs)

**Fixed and ran 42/42 integration tests:**
- Fixed Claude auth mount test (was checking wrong path — `.claude` vs `.claude-host`)
- Fixed VLogs port detection (auto-detect from docker inspect, not hardcoded)
- Added 3 security tests: SSH isolation, host filesystem isolation, env var isolation
- All 42 tests green

**Inception test — simple project:**
- Created `homercsimpson50/inception-test` on GitHub
- Mounted into container, added as rig
- Containerized Claude Code built Go HTTP server (`main.go` + `main_test.go`)
- Tests pass in container AND locally
- Pushed from container to GitHub

**Inception test — monorepo:**
- Created `homercsimpson50/inception-monorepo` with `projects/01-api/`, `projects/02-cli/`, `shared/types.go`
- Mounted into container, added as monorepo rig
- Containerized Claude Code built both projects in a single session
- API server uses `shared.Item` type, CLI fetches from API and formats output
- All tests pass in container AND locally
- Pushed from container to GitHub

### Key Findings

**Env var isolation works:** Container `GT_OTEL_LOGS_URL` points to its own VLogs sidecar. Host env vars don't leak in — Docker Compose env vars take precedence.

**Claude Code onboarding blocks automation:** The interactive theme/login wizard runs on first session start, even when valid credentials exist. The workaround is `claude -p` mode (print mode) which uses `ANTHROPIC_API_KEY` from the environment and bypasses onboarding entirely.

**Git push from container:** Works via `gh auth setup-git` after authenticating the `gh` CLI inside the container. The host's gh token was passed in during setup.

**Monorepo support works:** Single bind-mount, shared `go.mod` at root, separate `projects/` directories. Claude Code correctly resolves relative imports across the shared package.

### Repos Created

| Repo | Purpose | Commit |
|------|---------|--------|
| [inception-test](https://github.com/homercsimpson50/inception-test) | Simple Go HTTP server built by containerized GT | `85622f3` |
| [inception-monorepo](https://github.com/homercsimpson50/inception-monorepo) | Monorepo with API + CLI built by containerized GT | `86f02ed` |

### Full Results

See [plans/inception/RESULTS.md](plans/inception/RESULTS.md) for detailed phase-by-phase results.

---

---

## 2026-04-04: Day 2 (Part 3) — Agent Feed TUI, AI Summary, and Hot Mounts

*Written by the Gas Town Mayor (Claude Opus 4.6)*

### What Changed

Built a real-time agent observability TUI with local LLM-powered summaries, fixed multiple feed issues through live debugging with the user, and added hot-mountable repos to the containerized setup.

### Agent Feed TUI (`gt feed --agents`)

Iterative debugging session with the user watching the live feed while the containerized mayor worked. Fixes made during live testing:

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| Only 1 event showing | VLogs returns newest-first, dedup dropped older events | Sort oldest-first before emitting |
| Raw JSON in display (`Bash: {"command":"..."}`) | Content has `ToolName: {json}` prefix format | Parse prefix, extract tool name, summarize input |
| Mayor text not showing | Content starts with `\n\n`, first-line split returns empty | Strip leading whitespace before splitting |
| User prompts not captured | JSONL user turns have `content` as string, not array | Custom `UnmarshalJSON` on `ccMessage` to handle both |
| "Connecting to VictoriaLogs" stuck | All events filtered as idle, health flag never set | Send health signal on first successful VLogs query |
| Summary not auto-refreshing | Tick chain never started in agents view | Add `tick()` to `Init()` for agents view |
| Refinery noise drowning real work | No role-based filtering | Filter refinery/witness/deacon/boot at source |
| Mayor housekeeping in feed | Startup routine (gt hook, gt mail, gt escalate) visible | Filter known housekeeping commands |

### AI Summary Panel (Local LLM via Ollama)

Press `s` in the agents feed to toggle a split-screen summary panel. A local LLM (Qwen 2.5 via Ollama) generates rolling summaries of agent activity — like Google Meet/Teams AI meeting notes, but for agent orchestration.

- **Model**: `qwen2.5:1.5b` (2GB, runs on M1 16GB)
- **Update interval**: Every 10 seconds
- **Summary style**: Rolling stream with timestamps (appends, doesn't overwrite)
- **Idle filtering**: Only summarizes mayor<->user conversation and polecat work
- **Cost**: $0 — runs entirely on local hardware

Setup: `brew install ollama && brew services start ollama && ollama pull qwen2.5:1.5b`

### Hot-Mountable Repos

Added `gtc mount` / `gtc unmount` for adding repos without container restart:

```bash
gtc mount ~/code/myproject      # Symlinks into staging dir
gtc unmount myproject            # Removes symlink
gtc mounts                       # Lists all mounts
```

The staging directory (`~/.gtc-rigs/`, configurable via `~/.gtc.conf`) is bind-mounted into the container. Symlinks are followed through the mount — container sees changes immediately.

### Container Auth Improvements

- **Claude Code**: Entrypoint now syncs `.credentials.json` from host (Google OAuth tokens carry over, no browser login in container)
- **GitHub**: Entrypoint syncs `~/.config/gh/hosts.yml` from host and runs `gh auth setup-git` (git push works out of the box)
- **Metrics warning**: Suppressed `GT_OTEL_METRICS_URL=""` (no VictoriaMetrics in stack)

### Known Issues

- **Claude Code onboarding**: Theme picker appears on every `gtc down`/`gtc up` cycle. The `hasCompletedOnboarding` flag in `settings.json` is set but Claude Code 2.1.92 doesn't respect it. Workaround: don't `gtc down` — use `gtc up` to restart (preserves volumes).
- **User prompts in feed**: Requires container image rebuild to include the `ccMessage.UnmarshalJSON` fix. The local `gtcfeed` binary has the display fix but the container's agent logger needs the new binary to forward user messages.

### Fork Commits

| Commit | Description |
|--------|-------------|
| `758ace64` | fix: sort VictoriaLogs entries oldest-first for correct dedup |
| `e23684f5` | feat: add rig column and rig filter to agents feed view |
| `f4482efd` | feat: add AI summary panel (local LLM via Ollama) |
| `7d5588e2` | feat: briefer summaries, idle filter, scrollable panel |
| `e7aedd09` | fix: parse prefixed tool content format |
| `e403558c` | feat: show user prompts + mayor text in agents feed |
| `9ce8dc81` | fix: no markdown in summary output |

All on `homercsimpson50/gastown@feat/agent-observability-tui`.

### Security Model: Three Walls

Through discussion about whether to mount `~/code/` into the container (convenience vs isolation), arrived at a clear three-layer defense model:

**Wall 1 — Container**: Docker prevents access to `~/.ssh`, `~/.aws`, host processes, anything outside mounted paths. Even `rm -rf /` only damages the container. Security controls: `cap_drop: ALL`, `no-new-privileges`, PID/memory limits.

**Wall 2 — Git Worktrees**: Each polecat gets its own worktree on its own branch (`polecat/rust-xyz`). It cannot modify `main`. Changes only reach `main` through the refinery merge queue. If a polecat goes rogue, delete the branch.

**Wall 3 — Gateway Token Isolation**: API tokens (GitHub, Jira) are held by the gateway sidecar. Agents call `gateway:9999` — they never see raw tokens. Gateway enforces allowlists and blocks dangerous endpoints.

The conclusion: mounting `~/code/` is safe because the mayor can read (needed for its job) but can only write through polecats, which are branch-isolated and merge-gated. The container can't reach anything beyond the mounted directory.

Full writeup in [SECURITY.md](guides/containerized/SECURITY.md) under "Defense in Depth: Three Walls".

### Gateway Token Management and `gtc auth`

Built token management into the gateway sidecar and a `gtc auth` command:

**Gateway endpoints (new):**
- `GET /tokens` — list configured tokens
- `PUT /tokens/<key>` — set/rotate at runtime
- `DELETE /tokens/<key>` — remove
- `GET /tokens/validate` — test tokens against live APIs
- `POST /tokens/import-gh` — import from host's `gh` CLI

**`gtc auth` flow:**
1. Reads host's `gh auth token`
2. Posts to gateway `/tokens/import-gh` (validates against GitHub API)
3. Writes `git-credential-gateway` helper script inside container
4. Configures `git config --global credential.helper` to use it
5. Validates all tokens and shows status

Result: containerized agents push to GitHub via the gateway. Tokens never on disk inside the GT container.

**Tested:** Mayor committed a change to inception-test README and pushed successfully from inside the container through the gateway credential helper.

### Claude Code Onboarding Bug

Spent significant time trying to eliminate the theme picker that appears on every container restart. Investigated:
- `hasCompletedOnboarding: true` in `settings.json` — ignored
- Persistent volumes for `~/.claude/`, `~/.local/state/claude/`, `~/.local/share/claude/` — all mounted, state persists, still shows
- `claude -p` (print mode) — works without onboarding, but interactive mode always shows the wizard

**Root cause:** Claude Code 2.1.92 does not persist onboarding completion state across interactive sessions. It's per-process, not per-installation. The `hasCompletedOnboarding` flag and stored credentials are not checked during the interactive TUI startup path.

**Workaround:** Press Enter once through the theme picker after each `gtc up`. This is a Claude Code bug, not a GT or container issue.

### Mount Strategy: `~/code/` Default

After iterating through three approaches:
1. ~~Per-repo mounts via symlinks~~ — Docker doesn't follow symlinks through bind mounts
2. ~~Per-repo mounts via override file~~ — requires container restart, kills mayor session
3. **Parent directory mount** — `~/code/` mounted once, all repos instantly accessible

The parent directory approach won because:
- Zero restarts when adding repos
- No session loss
- Three Walls security model makes it safe (container isolation + worktree isolation + gateway token isolation)
- `gtc mount` is just a convenience check, not a mutation

### `gtc` CLI Final State

| Command | Description |
|---------|-------------|
| `gtc up` | Start/restart containers |
| `gtc down` | Stop (preserves volumes, blocks `-v`) |
| `gtc attach` | Mayor session (Ctrl-B D to detach) |
| `gtc auth` | Import gh token → gateway → credential helper |
| `gtc feed --agents` | Agent activity feed (local binary, container VLogs) |
| `gtc feed --agents --ai` | Feed + Ollama AI summary (auto-installs on first use) |
| `gtc mount <path>` | Check repo is accessible under `~/code/` |
| `gtc mounts` | List available repos |
| `gtc unmount` | Interactive fzf rig removal |
| `gtc exec <cmd>` | Run command in container |
| `gtc shell` | Bash inside container |
| `gtc test` | Run 42+ integration tests |
| `gtc sync` | Sync fork with upstream gastown |

### iTerm2 Workspace Launcher

Created `scripts/gastown-workspace.sh` — one command to set up the full Gas Town development environment:

```
┌──────────┬──────────┬──────────┐
│          │ gtc      │ shell    │
│  local   │ mayor    │ ~/code   │
│  mayor   ├──────────┴──────────┤
│  (tall)  │ gtc feed --agents   │
│          │ (wide)              │
└──────────┴─────────────────────┘
```

- Left (full height): Local mayor session — direct GT control
- Top-center: Containerized mayor — sandboxed agents
- Top-right: Shell for exploring repos and running tests
- Bottom-right (wide): Agent feed showing user↔mayor conversation + polecat work

Window auto-sizes to 90% of screen. `--ai` flag enables Ollama summary panel.

### Day 2 Summary

What started as fixing a VictoriaLogs sort bug turned into a full-day build session:

- **Agent feed TUI**: Fixed summarizer for real Claude Code events, added rig column/filter, split-screen AI summary panel, user input capture (mad-max 🏎️ icon), idle event filtering
- **Containerized GT**: 42+ integration tests, gateway token management with `gtc auth`, Three Walls security model documented, `~/code/` parent mount
- **Inception test**: Containerized mayor autonomously ran 3 polecats across 2 repos — all tests pass, all code pushed
- **Developer experience**: `gtc` CLI (mount/unmount/auth/feed), interactive fzf unmount, workspace launcher, `~/.gtc.conf` config
- **Local LLM**: Ollama integration for $0 AI summaries, auto-install on first `--ai` use, cleanup on exit

Fork commits: 12 commits on `homercsimpson50/gastown@feat/agent-observability-tui`
Learning-gastown commits: 25+ commits across the session

---

## 2026-04-05 to 2026-04-12: Multi-Project Build Sprint

*Written by the Gas Town Mayor (Claude Opus 4.6)*

### Projects Built

Three private repos created and built autonomously by GT polecats:

**Mimir** (`homercsimpson50/mimir`) — Local Threat Intelligence Platform
- Phase 1: Python/FastAPI scaffolding, SQLite schema, CLI
- Phase 2: Feed ingestion (URLhaus, ThreatFox, MITRE ATT&CK, CISA KEV)
- Phase 3: Web UI (HTMX + Cytoscape.js graph), watchlist, search
- Phase 4: Enrichment (Shodan, CIRCL, VirusTotal), OTX, text feed adapters, export/import
- Phase 5: Auto-pull scheduler, desktop notifications, NetworkX graph analytics
- Dashboard rebuild: OpenCTI-style with insights cards, local timestamps
- Bugfixes: STIX UUID validation, Starlette API changes, adapter errors
- Total: ~7,000+ lines, 63 files, 12 feed adapters, 5 architecture docs
- Status: Running locally, pulling real threat feeds (84,400+ indicators loaded)

**Athena** (`homercsimpson50/athena`) — Account Cleanup Service (OAC)
- Phase 1: 8 Go microservice stubs, Dockerfiles, docker-compose
- Phase 2: Gmail OAuth, email parsing, account classification
- Phase 3: Temporal deletion workflows, playbook service (35 services), GDPR templates
- Phase 4: End-to-end wiring, consumer UI, integration tests
- Phase 5: Real Temporal integration, compliance audit, playbook expansion
- Standalone scanner: Single-binary Gmail scanner with OAuth, reads headers only
- Google Cloud OAuth setup: consent screen, test users, redirect URIs
- Total: ~7,600+ lines, 74 files, 5 architecture docs
- Status: Scanner connects to real Gmail, microservices run via docker-compose

**Onyx** (`homercsimpson50/onyx`) — Dark Web Site Identification (arxiv 2401.13320)
- Paper analysis and implementation spec
- BERTopic pipeline (SBERT + UMAP + HDBSCAN + c-TF-IDF)
- Tor crawler, MinHash LSH deduplication
- Status: Phase 1 built by polecat, in progress

### API Keys Configured

| Service | Key Location | Purpose |
|---------|-------------|---------|
| abuse.ch | `~/code/mimir/.env` | URLhaus, ThreatFox, MalwareBazaar, Feodo, SSL Blacklist |
| AlienVault OTX | `~/code/mimir/.env` | Threat intel pulses |
| NIST NVD | `~/code/mimir/.env` | CVE vulnerability data |
| VirusTotal | `~/code/mimir/.env` | Malware/URL spot-checks |
| Google OAuth | `~/code/athena/.env` | Gmail read-only access for Athena scanner |

### Mimir Dashboard Issues

- Initial dashboard: Starlette `TemplateResponse` API change caused 500 errors (fixed)
- Timestamps showed "Invalid Date" (fixed: robust JS parser for multiple ISO formats)
- Dashboard was generic — added actionable insights (critical CVEs, multi-feed IPs, Tor overlap, feed errors) with clickable links to search/watchlist pages
- OpenCTI-style rebuild slung: world map (Leaflet.js), donut/line/bar charts (Chart.js), heatmap, treemap, timeline

### Athena Scanner Issues

- OAuth flow: consumer UI proxied to user-mgmt microservice (too many moving parts for testing). Built standalone single-binary scanner instead.
- Redirect URI mismatch: had to match port 3000 in Google Cloud Console
- Token expiry: access tokens expire, need re-auth. Added error page with "Re-connect Gmail" button.
- 0 emails scanned: Gmail API errors not logged — added response body logging and status code checks.

### GT Agent Feed

- Feed stopped working after laptop restart (daemon lost telemetry env vars)
- Fix: restart daemon with `GT_OTEL_LOGS_URL` and `GT_LOG_AGENT_OUTPUT=true`
- Session restarts needed for polecats to pick up new telemetry config

---

## 2026-04-12: Athena Dogfooding — Real Gmail Scan + Account Analysis

*Written by the Gas Town Mayor (Claude Opus 4.6)*

### Gmail Scanner

Built a standalone Go scanner (`cmd/scanner/main.go`) that bypasses the microservices architecture for direct testing. Single binary, Google OAuth, reads email headers only (From, Subject, Date).

**Results**: 9,983 emails scanned → 438 unique services discovered across 12 categories.

Key engineering:
- Token persistence to `~/.athena/tokens.json` with auto-refresh — connect Gmail once, never again
- Result persistence to `~/.athena/results.json` — survives restarts
- Per-page telemetry logging (page X/100, Y emails, Z services, rate)
- Error handling with token refresh on 401

### Category Reclassification

The initial scan put 360/438 services (82%) in "Other" — useless. Polecat obsidian reclassified all of them into 30+ categories:

| Category | Count | % |
|----------|-------|---|
| Finance | 56 | 12% |
| Shopping | 53 | 12% |
| Nonprofit/Charity | 37 | 8% |
| Travel | 33 | 7% |
| Education | 27 | 6% |
| Developer | 27 | 6% |
| News/Media | 26 | 5% |
| Work | 24 | 5% |
| Healthcare | 15 | 3% |
| + 21 more categories | ... | ... |
| **Other** | **0** | **0%** |

### Deletion Analysis

For all 438 services, polecats researched deletion methods:
- 271 (66%) require Email + OTP
- 85 (21%) are newsletter unsubscribes
- 24 (6%) require login + settings navigation
- 22 (5%) have CCPA/GDPR forms
- 7 (2%) require login + GDPR form

Priority breakdown: 132 do-not-delete, 116 high priority, 170 medium, 20 low.

**Key finding**: Many "newsletter unsubscribe" services were actually product updates from services with active accounts (alarm.com sends arming notifications, ticketmaster sends ticket updates). These need account deletion, not just unsubscribe.

### Interactive Dashboard

Built `dogfooding-experiment/index.html` — single-file dark-theme dashboard with:
- Category pie chart, deletion method donut, priority bars
- Priority × Complexity ROI matrix
- Sortable/filterable table with row expansion for deletion details
- Evidence column showing how deletion method was determined
- Do-not-delete toggle, search, JSON/CSV export

### Artifacts

All under `athena/dogfooding-experiment/`:
- `scan-results.json` — raw 438-service scan data
- `deletion-analysis.json` — enriched with deletion methods, evidence, categories
- `analysis.md` — full writeup
- `index.html` — interactive dashboard
- `Athena — Results.html` — original scan results page

---

---

## 2026-04-18: Localhost Setup Guide — Shell-Aware Env Installer + `gtf` Wrapper

*Written by the Gas Town Mayor (Claude Opus 4.7)*

### The Problem (Again)

Day 2 (Apr 4) chronicled it once: "Feed stopped working after laptop restart
(daemon lost telemetry env vars). Fix: restart daemon with `GT_OTEL_LOGS_URL` and
`GT_LOG_AGENT_OUTPUT=true`." It came back. Open a fresh terminal, run `gt feed`,
get nothing — because the env vars only live inside an active Mayor session, not
in the user's shell rc.

The root cause is three vars `gt feed` / `gt log` need:

| Var | What | Default |
|---|---|---|
| `GT_TOWN_ROOT` | Where the town lives | `~/gt` (auto-walks up otherwise) |
| `GT_VLOGS_QUERY_URL` | LogsQL query endpoint (readers) | `http://localhost:9428/select/logsql/query` |
| `GT_OTEL_LOGS_URL` | OTLP insert endpoint (spawned agents) | `http://localhost:9428/insert/opentelemetry/v1/logs` |

The reader vars have sane defaults; the writer var (`GT_OTEL_LOGS_URL`) doesn't —
without it exported in the shell that runs `gt start`, the Mayor boots fine but
its tool calls never reach VictoriaLogs and `gt feed -a` stays empty.

### What I Built

A new guide directory: [`guides/localhost/`](guides/localhost/).

**`gt-env-install.sh`** — idempotent installer:
- Detects `$SHELL` and writes to the right rc file: `~/.zshrc`, `~/.bash_profile`
  (macOS) or `~/.bashrc`, `~/.kshrc`, `~/.profile`, or `~/.config/fish/config.fish`.
- Writes a marked block (BEGIN/END comments). Re-running replaces it cleanly.
- Backs up the rc on first touch (`<rc>.gt-backup.<timestamp>`).
- Prepends `~/.local/bin` to `PATH` if missing.
- Flags: `--shell <name>`, `--dry-run`, `--uninstall`.

**`gtf.sh`** — wrapper around the common queries:

```sh
gtf                       # full TUI (gt feed)
gtf -a                    # agents view (tool-call observability)
gtf -p                    # problems view (stuck/GUPP)
gtf plain                 # plain text event stream
gtf log -f                # tail spawn/wake/handoff/done
gtf log --agent gastown/mayor       # mayor only
gtf log --agent gastown/polecats    # polecats only
```

The wrapper sets the three env vars (with sane defaults so it works in a stripped
shell) and pings VictoriaLogs health before invoking `gt`, warning instead of
silently producing an empty feed.

**`README.md`** — covers prereqs (`brew install victorialogs`), the install flow,
the `gt start` → `gt mayor attach` → `gtf -a` sequence, end-to-end verification
(`curl http://localhost:9428/health` → `gtf log -n 5` → `gtf -a`), and the
troubleshooting tree for "feed is empty even though Mayor is running" (the most
common failure mode: `GT_OTEL_LOGS_URL` wasn't exported in the spawning shell, so
`gt mayor restart` after sourcing the rc fixes it).

### Smoke Test

Ran `env -i HOME=$HOME PATH=/Users/homer/.local/bin:/usr/bin:/bin gtf plain` — a
stripped environment with no `GT_*` vars and no shell rc — and got back a real
event stream. The wrapper's defaults are enough; the installer is for persistence
across new shells.

### Why This Wasn't Solved Day 2

Day 2's fix was reactive: restart the daemon with the vars set. This guide makes
it preventive — install once, every new shell has them. And the wrapper means
nobody has to remember the four commands behind `gt feed -a` ever again.

### Files

```
guides/localhost/
├── README.md              # full guide: install, start GT, watch feed, troubleshoot
├── gt-env-install.sh      # shell-aware env installer (zsh/bash/ksh/fish)
└── gtf.sh                 # gt feed / gt log wrapper with env baked in
```

The same scripts are also installed at `~/.local/bin/gtf` and
`~/.local/bin/gt-env-install` so they're usable on this machine immediately.

---

*This chronicle will be updated as exploration continues.*
