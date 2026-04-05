# Learning Gas Town & Beads

A deep dive into [Gas Town](https://github.com/gastownhall/gastown) and [Beads](https://github.com/gastownhall/beads) — Steve Yegge's multi-agent orchestration framework and its companion distributed issue tracker.

This repo documents what I learned by exploring the codebases, reading the source, and building them from scratch. See also the [Chronicle](CHRONICLE.md) for the full day-by-day build log.

### Table of Contents

- [What is Gas Town?](#what-is-gas-town)
- [What is Beads?](#what-is-beads)
- [The Journey from "Clown Show" to v1.0](#the-journey-from-clown-show-to-v10)
- [Gas Town Architecture](#gas-town-architecture)
  - [The Cast of Characters](#the-cast-of-characters)
  - [The Refinery: Merge Queue](#the-refinery-bors-style-bisecting-merge-queue)
  - [Workflow Primitives](#workflow-primitives)
- [Beads Architecture](#beads-architecture)
  - [Hash-based IDs (with example)](#example-why-sequential-ids-break-with-multiple-agents)
  - [Cell-level Merge (with example)](#example-cell-level-merge-vs-line-level-merge)
- [How to Build Gas Town](#how-to-build-gas-town)
- [How to Build Beads](#how-to-build-beads)
- [How to Use Gas Town (Day-to-Day)](#how-to-use-gas-town-day-to-day)
- [Monitoring & Dashboards](#monitoring--dashboards)
- [Design Philosophy](#design-philosophy)
- [What I Found Most Interesting](#what-i-found-most-interesting)
- [Resources](#resources)

---

## What is Gas Town?

Gas Town is an **orchestration framework for AI coding agents**. It coordinates 4-30+ AI agents (Claude Code, Codex, Copilot, Gemini, Cursor, etc.) working simultaneously on a codebase. Think of it as a "city government" for your AI workforce.

**The problem it solves:** When multiple AI agents work on the same repo, you get context loss on restart, merge chaos, no coordination, and information overload. Gas Town fixes all of that.

**Key stats (as of April 2026):**
- 13,458 GitHub stars
- Written in Go (~12.3M lines)
- MIT licensed
- v1.0.0 released April 3, 2026

## What is Beads?

Beads (`bd`) is a **distributed graph issue tracker for AI coding agents**, powered by [Dolt](https://github.com/dolthub/dolt) (a version-controlled SQL database). Its tagline: *"A memory upgrade for your coding agent."*

Where Git captures the What, Where, Who, and How — Beads captures **the Why**. It gives agents persistent, structured memory so they can handle long-horizon tasks without losing context.

**Key stats:**
- 20,177 GitHub stars
- Also Go, also MIT licensed
- v1.0.0 released same day as Gas Town

---

## The Journey from "Clown Show" to v1.0

Steve Yegge's [blog post](https://steve-yegge.medium.com/gas-town-from-clown-show-to-v1-0-c239d9a407ec) describes a rough first three months:

- Workers crashing mid-job ("serial killer sprees")
- Data loss incidents ("22-nose Clown Show")
- The **Deacon** (a cross-rig background supervisor) was the recurring culprit

All resolved by v1.0 — the system now runs stably for weeks.

---

## Gas Town Architecture

### The Cast of Characters

Gas Town uses a rich domain vocabulary. Here's the hierarchy:

| Concept | What it does |
|---------|-------------|
| **Mayor** | Primary AI coordinator — your personal concierge. Reads all worker output and surfaces only what matters |
| **Town** | Workspace root directory (e.g., `~/gt/`) |
| **Rigs** | Project containers, each wrapping a git repo |
| **Crew** | Human workspace within a rig |
| **Polecats** | Worker AI agents with persistent identity but ephemeral sessions |
| **Hooks** | Git worktree-based persistent storage for agent work |
| **Convoys** | Work tracking units bundling multiple beads |
| **Witness** | Per-rig lifecycle manager monitoring polecats |
| **Deacon** | Cross-rig background supervisor running patrol cycles |
| **Dogs** | Infrastructure workers for maintenance tasks |
| **Refinery** | Per-rig Bors-style bisecting merge queue (see diagram below) |
| **Seance** | Session discovery/continuation via `.events.jsonl` logs |
| **Wasteland** | Federated work coordination network linking Gas Towns via DoltHub |
| **Scheduler** | Config-driven capacity governor preventing API rate limit exhaustion |

### Monitoring Hierarchy

```
Daemon (Go process)
  └── Boot (AI agent)
       └── Deacon (AI agent)
            ├── Witnesses (per-rig)
            └── Refineries (per-rig)
```

### The Refinery: Bors-Style Bisecting Merge Queue

Agents never push directly to `main`. Instead, the **Refinery** batches completed work and tests it before merging. If a batch fails, it bisects to find the broken PR — just like [Bors](https://bors.tech/).

```mermaid
graph TD
    subgraph "Agent Work"
        A1[Polecat 1: PR #101] -->|gt done| Q
        A2[Polecat 2: PR #102] -->|gt done| Q
        A3[Polecat 3: PR #103] -->|gt done| Q
        A4[Polecat 4: PR #104] -->|gt done| Q
    end

    Q[Merge Queue] -->|Batch 1: PRs 101+102+103+104| B1

    subgraph "Refinery Processing"
        B1{Test batch<br/>101+102+103+104} -->|PASS| M[Merge all to main]
        B1 -->|FAIL| B2{Bisect: test<br/>101+102}
        B2 -->|PASS| B3{Test 103+104}
        B2 -->|FAIL| B4{Test 101 alone}
        B3 -->|FAIL| B5{Test 103 alone}
        B4 -->|PASS| FOUND1[PR 102 broke the build]
        B4 -->|FAIL| FOUND2[PR 101 broke the build]
        B5 -->|PASS| FOUND3[PR 104 broke the build]
        B5 -->|FAIL| FOUND4[PR 103 broke the build]
    end

    FOUND1 -->|Reject & notify| A2
    M -->|main updated| DONE[Clean main branch]
```

**Why this matters with 30 agents:** Without a merge queue, agents would constantly break each other's work. The Refinery guarantees that `main` is always green. When a batch fails, bisecting pinpoints exactly which PR is the culprit — no human investigation needed.

#### Full Lifecycle: What Happens When PRs Fail?

The flowchart above shows bisection, but the real question is: what happens to the broken PR? Who fixes it, how does it get retested, and what if *multiple* PRs fail? Here's the full sequence:

```mermaid
sequenceDiagram
    participant P1 as Polecat 1
    participant P2 as Polecat 2
    participant P3 as Polecat 3
    participant MQ as Merge Queue
    participant R as Refinery
    participant M as Main Branch
    participant W as Witness

    Note over P1,P3: All 3 agents finish work
    P1->>MQ: gt done (PR #101)
    P2->>MQ: gt done (PR #102)
    P3->>MQ: gt done (PR #103)

    MQ->>R: Batch: 101 + 102 + 103
    R->>R: Test batch together
    R-->>R: FAIL!

    Note over R: Bisect phase begins
    R->>R: Test 101 + 102
    R-->>R: FAIL!
    R->>R: Test 101 alone
    R-->>R: PASS ✓
    Note over R: → PR #102 is broken

    R->>R: Test 103 alone
    R-->>R: FAIL!
    Note over R: → PR #103 is also broken

    Note over R: Two failures found
    R->>MQ: Reject PR #102 (reason: test failure)
    R->>MQ: Reject PR #103 (reason: test failure)
    R->>M: Merge PR #101 ✓

    Note over MQ,W: Notify agents via mail system
    MQ->>W: Notify: PR #102 rejected
    MQ->>W: Notify: PR #103 rejected
    W->>P2: Mail: "PR #102 failed tests. Fix and resubmit."
    W->>P3: Mail: "PR #103 failed tests. Fix and resubmit."

    Note over P2,P3: Agents fix their work
    P2->>P2: Read failure logs, fix code
    P3->>P3: Read failure logs, fix code
    P2->>MQ: gt done (PR #102 v2)
    P3->>MQ: gt done (PR #103 v2)

    MQ->>R: Batch: 102v2 + 103v2
    R->>R: Test batch together
    R-->>R: PASS ✓
    R->>M: Merge both ✓

    Note over M: Main is always green 🟢
```

**Key points about failure handling:**

1. **The Refinery identifies ALL broken PRs** — not just the first one. Bisection continues until every PR in the batch is classified as pass or fail.

2. **Broken PRs go back to their polecat** — via Gas Town's mail system. The Witness (per-rig health monitor) delivers the rejection notice with test failure logs.

3. **The polecat fixes its own work** — it reads the failure logs, patches the code, and resubmits with `gt done`. No human involved.

4. **Passing PRs merge immediately** — PR #101 doesn't wait for #102 and #103 to get fixed. It merges as soon as the Refinery confirms it's clean.

5. **Fixed PRs enter the next batch** — they go back into the queue and get tested again (possibly alongside new work from other agents).

6. **If a polecat can't fix it** — the Witness escalates to the Deacon, which may reassign the work to a different polecat or escalate to a human via the escalation system.

### Workflow Primitives

- **Formulas** — TOML-defined workflow templates for multi-step processes
- **Molecules** — Epics with children defining dependency-aware execution graphs. Children are parallel by default; explicit `blocks` dependencies create sequencing.

---

## Beads Architecture

### Two-Layer Data Model

1. **CLI Layer** — Cobra-based Go CLI (`cmd/bd/`) with commands like `bd create`, `bd ready`, `bd update`, `bd close`, `bd dep add`, `bd sync`
2. **Dolt Database Layer** — Version-controlled SQL database in `.beads/dolt/`. Every write auto-commits to Dolt, creating an immutable audit trail.

### Storage Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| **Embedded** (default) | Dolt runs in-process, no server needed. Single-writer, file-lock enforced. | Solo agent, simple setups |
| **Server** | Connects to external `dolt sql-server` on port 3307. Multi-writer capable. | Gas Town multi-agent orchestration |

### Key Design Decisions

- **Hash-based IDs** (`bd-a1b2`) instead of sequential IDs — prevents merge collisions when multiple agents create issues concurrently
- **Event-driven FlushManager** with single-owner pattern — channels instead of mutexes eliminates race conditions
- **Cell-level merge** (via Dolt) — two agents can update different fields of the same issue without conflict
- **Dolt branching** is independent of git branches, enabling isolated workstreams

#### Example: Why Sequential IDs Break with Multiple Agents

Imagine 3 agents working in parallel on different git branches:

```
Agent A (branch: feature-auth)     creates issue #42
Agent B (branch: feature-api)      creates issue #42  ← COLLISION!
Agent C (branch: feature-ui)       creates issue #42  ← COLLISION!
```

With sequential IDs, each agent's local counter independently reaches `#42`. When branches merge, you get three different issues all claiming to be `#42`. Which one wins? Data loss.

Beads solves this with **hash-based IDs** derived from content + timestamp + agent identity:

```
Agent A → bd-f7a3   (hash of "auth task" + timestamp + agent-A-identity)
Agent B → bd-c91e   (hash of "api task"  + timestamp + agent-B-identity)
Agent C → bd-2d5b   (hash of "ui task"   + timestamp + agent-C-identity)
```

Every ID is globally unique. Branches merge cleanly. No coordination needed between agents.

#### Example: Cell-Level Merge vs Line-Level Merge

Traditional git uses **line-level merge**. If two people edit the same line, you get a conflict — even if they changed different parts of the line.

Dolt uses **cell-level merge**, like a spreadsheet. Each field in a row is an independent cell:

```
Issue bd-f7a3 in the beads database:

           title          status       assignee
           ─────          ──────       ────────
Original:  "Fix auth"     "pending"    "unassigned"
Agent A:   "Fix auth"     "active"     "unassigned"   ← changed status
Agent B:   "Fix auth"     "pending"    "polecat-7"    ← changed assignee
```

With **line-level merge** (git): CONFLICT — both agents touched the same row.

With **cell-level merge** (Dolt): No conflict! Agent A changed `status`, Agent B changed `assignee`. Different cells. Dolt merges both automatically:

```
Merged:    "Fix auth"     "active"     "polecat-7"    ✓ Both changes preserved
```

This is critical when 30 agents are updating issue statuses, adding comments, and reassigning work simultaneously. Line-level merge would create constant conflicts. Cell-level merge just works.

### Integrations

- Claude Code plugin (`integrations/claude-code/`)
- MCP Server (`integrations/beads-mcp/`, published on PyPI)
- JetBrains Junie (`integrations/junie/`)
- GitHub Issues, GitLab, Jira, Linear, Notion import/sync

---

## Repo Structure: Gas Town

```
gastown/
├── cmd/
│   ├── gt/                  # Main CLI binary
│   ├── gt-proxy-server/     # Proxy server
│   └── gt-proxy-client/     # Proxy client
├── internal/                # 70+ Go packages
│   ├── mayor/               # Mayor orchestration
│   ├── polecat/             # Worker agent management
│   ├── deacon/              # Background supervisor
│   ├── witness/             # Per-rig lifecycle
│   ├── refinery/            # Merge queue
│   ├── beads/               # Beads integration
│   ├── convoy/              # Work tracking
│   ├── formula/             # Workflow templates
│   ├── hooks/               # Git worktree hooks
│   ├── scheduler/           # Capacity management
│   ├── wasteland/           # Federation
│   ├── tui/                 # Terminal UI (Bubbletea)
│   └── ...                  # 50+ more packages
├── plugins/                 # 14 built-in plugins
│   ├── compactor-dog/
│   ├── dolt-archive/
│   ├── github-sheriff/
│   ├── rate-limit-watchdog/
│   ├── stuck-agent-dog/
│   └── ...
├── templates/               # Role instruction templates
├── docs/                    # Extensive documentation
├── scripts/                 # Build/release scripts
├── npm-package/             # npm distribution wrapper
└── gt-model-eval/           # Model evaluation tooling
```

## Repo Structure: Beads

```
beads/
├── cmd/bd/                  # CLI entry point
├── internal/
│   ├── storage/             # Dolt backend
│   ├── beads/               # Core domain
│   ├── idgen/               # Hash-based ID generation
│   ├── molecules/           # Workflow graphs
│   ├── compact/             # Semantic memory decay/summarization
│   ├── git/                 # Git integration
│   ├── query/               # SQL query layer
│   ├── routing/             # Multi-repo routing
│   ├── github/              # GitHub Issues sync
│   ├── gitlab/              # GitLab sync
│   ├── jira/                # Jira sync
│   ├── linear/              # Linear sync
│   ├── notion/              # Notion sync
│   ├── ui/                  # TUI (Charm libraries)
│   └── telemetry/           # OpenTelemetry
├── integrations/
│   ├── claude-code/         # Claude Code plugin
│   ├── beads-mcp/           # MCP server (Python)
│   └── junie/               # JetBrains integration
└── docs/
    ├── ARCHITECTURE.md
    ├── DOLT.md
    ├── INTERNALS.md
    ├── MOLECULES.md
    └── FAQ.md
```

---

## How to Build Gas Town

### Prerequisites

- Go 1.25+
- Git 2.25+ (worktree support required)
- Dolt 1.82.4+
- Beads (`bd`) 0.55.4+
- sqlite3
- tmux 3.0+ (recommended)
- At least one AI agent CLI (Claude Code, Codex, Copilot, etc.)

### Build from Source

```bash
git clone https://github.com/gastownhall/gastown.git
cd gastown

# Build all binaries (gt, gt-proxy-server, gt-proxy-client)
make build

# Install to ~/.local/bin with version info baked in
make install

# Run tests
make test

# Or build manually without make
go build -o gt ./cmd/gt
```

### Docker

```bash
docker compose build && docker compose up -d
docker compose exec gastown zsh
gt up
```

### Package Managers

```bash
brew install gastown
# or
npm install -g @gastown/gt
```

## How to Build Beads

### Prerequisites

- Go 1.25+
- CGO enabled (`CGO_ENABLED=1`) — embedded Dolt links C libraries
- macOS: `xcode-select --install && brew install icu4c`
- Ubuntu: `sudo apt install build-essential`

### Build from Source

```bash
git clone https://github.com/gastownhall/beads.git
cd beads

# Build (produces ./bd binary, codesigns on macOS)
make build

# Install to ~/.local/bin
make install

# Run tests
make test
```

### Package Managers

```bash
brew install beads
# or
npm install -g @beads/bd
# or
go install github.com/steveyegge/beads/cmd/bd@latest
```

---

## Design Philosophy

Two principles from Gas Town's `CONTRIBUTING.md`:

### 1. Zero Framework Cognition (ZFC)

Go code handles **transport** — tmux sessions, message delivery, hooks, nudges, file I/O, observability. All **reasoning and decision-making** happens in AI agents via formulas and role templates. No hardcoded thresholds or heuristics in Go.

### 2. Bitter Lesson Alignment

Bet on models getting smarter rather than building elaborate hand-crafted heuristics. Expose data for agents to reason about rather than encoding the reasoning.

> "By the end of 2026, people will be mostly programming by talking to a face." — Steve Yegge

---

## How to Use Gas Town (Day-to-Day)

Gas Town runs **outside** your IDE/editor. It's an orchestrator that manages Claude Code (and other agent) sessions via tmux. You interact with it from a regular terminal.

### Quick Start After Install

```bash
cd ~/gt                          # Go to your town root

gt status                        # See what's running
gt mayor attach                  # Talk to the Mayor (your AI concierge)
gt feed                          # Real-time activity dashboard (TUI)
```

### Common Commands

| Task | Command | What happens |
|------|---------|-------------|
| **Start everything** | `gt up` | Starts Dolt, Daemon, Mayor, Deacon, Witnesses, Refineries |
| **Check status** | `gt status` | Shows all services and agent states |
| **Talk to Mayor** | `gt mayor attach` | Opens Mayor's tmux session — ask it to do things |
| **Assign work** | `gt sling "add dark mode"` | Creates a bead and dispatches a polecat to do it |
| **Watch activity** | `gt feed` | Live TUI showing agent events across all rigs |
| **See ready work** | `gt ready` | PRs that passed the Refinery and are ready to merge |
| **Check health** | `gt health` | Dolt server, DB stats, zombie processes |
| **Full diagnostics** | `gt doctor` | 30+ health checks |
| **Agent messages** | `gt mail` | Inter-agent mail system |
| **View changelog** | `gt changelog` | Completed work across rigs |
| **Stop everything** | `gt down` | Gracefully stops all services |

### Typical Workflow

1. **Open a terminal** and `cd ~/gt`
2. **`gt up`** — start services (idempotent, safe to run multiple times)
3. **`gt mayor attach`** — tell the Mayor what you want built
4. The Mayor breaks work into beads, dispatches polecats
5. **`gt feed`** — watch agents work in real-time
6. **`gt ready`** — review completed work
7. Polecats push to the Refinery merge queue automatically
8. The Refinery tests, bisects failures, merges clean PRs to main

### Where Gas Town vs Claude Code

| Use Gas Town when... | Use Claude Code directly when... |
|---------------------|--------------------------------|
| Coordinating multiple agents | Quick one-off tasks |
| Long-running projects | Exploring/learning a codebase |
| Work that needs merge queue safety | Simple bug fixes |
| You want the Mayor to manage complexity | You want direct control |

---

## Monitoring & Dashboards

Gas Town provides three ways to see what's happening. There's no Electron/desktop app — it's terminal-first by design.

### `gt feed` — Interactive TUI (Best for Daily Use)

A full terminal dashboard built with [Bubbletea](https://github.com/charmbracelet/bubbletea):

| Panel | Shows |
|-------|-------|
| **Agent tree** (top) | All agents by role with latest activity |
| **Convoy panel** (middle) | In-progress and recently landed work batches |
| **Event stream** (bottom) | Scrollable chronological event feed |

Navigation: `j/k` scroll, `tab` switch panels, `1/2/3` jump to panel, `q` quit.

The **problems view** (`gt feed -p`) surfaces stuck agents and GUPP violations (hooked work + 30 min no progress). Keyboard actions: `Enter` = attach, `n` = nudge, `h` = handoff.

The **agents view** (`gt feed -a`) shows real-time agent tool calls from VictoriaLogs — reads, writes, edits, bash commands summarized into human-readable one-liners per agent. Shows rig/project column; press `r` to cycle rig filter. Press `s` to toggle AI summary panel (local LLM via Ollama). Only shows user<->mayor conversation and polecat coding work — infrastructure noise (refinery patrols, witness checks) is filtered out.

```
Event symbols:
  +  created     →  in_progress    ✓  completed    ✗  failed
  🦉 patrol      ⚡ nudged         🎯 sling        🤝 handoff

Agent state (problems view):
  🔥 GUPP violation (critical)     ⚠  STALLED     ●  Working
  ○  Idle                          💀 Zombie
```

#### Local VictoriaLogs Setup (for `gt feed --agents`)

```bash
brew install victorialogs
brew services start victorialogs
```

Add to `~/.zshrc`:
```bash
export GT_OTEL_LOGS_URL="http://localhost:9428/insert/opentelemetry/v1/logs"
export GT_LOG_AGENT_OUTPUT="true"
```

Restart the GT daemon (`gt daemon stop && gt daemon start`). All agent sessions will emit OTLP events to VLogs. Query raw logs at `http://localhost:9428/select/vmui`.

Source: [homercsimpson50/gastown@feat/agent-observability-tui](https://github.com/homercsimpson50/gastown/tree/feat/agent-observability-tui)

### `gt dashboard --open` — Web UI (Best for Overview)

A browser-based dashboard at `http://localhost:8080` called the **"Gas Town Control Center"**:

- Convoy list with status indicators and progress tracking
- Activity health indicators (green/yellow/red)
- Auto-refreshes every 30s via htmx + SSE for real-time updates
- Command palette via `Cmd+K`

```bash
gt dashboard --open              # Start and open browser
gt dashboard --port 3000         # Custom port
gt dashboard --bind 0.0.0.0      # Listen on all interfaces
```

### `gt vitals` — Quick Health Snapshot

One-shot terminal output of unified system health. Good for scripting or quick checks.

---

## Key Dependencies

### Gas Town
- `spf13/cobra` — CLI framework
- `charmbracelet/bubbletea` + `bubbles` + `lipgloss` + `glamour` — TUI
- `steveyegge/beads` — Core dependency
- `BurntSushi/toml` — Formula parsing
- `go-rod/rod` — Browser automation
- `go-sql-driver/mysql` — Dolt SQL connectivity
- OpenTelemetry stack — Observability
- `testcontainers-go` — Integration testing

### Beads
- `dolthub/dolt` — Version-controlled SQL database (embedded)
- `spf13/cobra` — CLI
- Charm libraries — TUI
- OpenTelemetry — Observability

---

## What I Found Most Interesting

1. **The Mayor abstraction** — Instead of reading raw agent output, the Mayor filters and presents only what matters. It's like having a project manager between you and 30 agents.

2. **Hash-based bead IDs** — Simple but brilliant. Sequential IDs break when multiple agents create issues concurrently across branches. Hash-based IDs (`bd-a1b2`) just work.

3. **Dolt as a database** — Using a version-controlled SQL database means every issue change has a full audit trail. Cell-level merge (not line-level) makes concurrent agent writes safe.

4. **The Refinery** — A Bors-style bisecting merge queue means agents never push directly to main. This prevents the merge chaos that would otherwise be inevitable with 30 agents.

5. **Zero Framework Cognition** — The Go code is deliberately "dumb" — it handles plumbing, not thinking. All intelligence lives in the AI agents themselves. This is a bet that models will keep getting smarter, so don't bake in today's heuristics.

6. **Wasteland federation** — Gas Towns can federate work across organizations via DoltHub. This is infrastructure for a future where AI agents collaborate across company boundaries.

---

## End-to-End Setup on macOS (What We Actually Did)

We built everything from scratch on a Mac. Here's the real timing:

| Step | Command | Time |
|------|---------|------|
| Install prerequisites | `brew install go tmux dolt` | ~3 min |
| Clone + build Beads | `git clone ... && make install` | ~2 min |
| Clone + build Gas Town | `git clone ... && make install` | ~2 min |
| Create HQ | `gt install ~/gt --name homer-town` | ~10 sec |
| Add rig | `gt rig add gastown https://github.com/gastownhall/gastown` | **~70 min** |
| Start services | `gt up` | ~30 sec |
| **Total** | | **~78 min** |

The rig add is by far the longest step — it syncs the upstream Dolt data (beads history), which involves downloading and indexing large pack files. For repos without existing Dolt histories, this would be much faster.

**Final state after setup:**

```
$ gt status
Town: homer-town (/Users/homer/gt)
👤 Overseer: Homer Simpson

Services: dolt (PID ..., :3307)  tmux (4 sessions)

🎩 mayor        ● [claude]
🐺 deacon       ● [claude]

─── gastown/ ─────────────────────
🦉 witness      ● [claude]
🏭 refinery     ● [claude]
```

---

## Guides

- **[Running Gas Town in Containers](guides/containerized/)** — Self-contained directory with docker-compose.yml, gateway sidecar, and full guide. Covers security review, observability (VictoriaLogs), monorepo support, and daily workflow. Essential reading before running GT on a machine with corporate credentials.

---

## Projects Built with Gas Town

### ESF Monitor

**Repo:** [homercsimpson50/esf-monitor](https://github.com/homercsimpson50/esf-monitor)

A macOS Endpoint Security Framework event viewer — the Mayor's first build after coming alive in Gas Town. Uses `eslogger` (macOS built-in) to stream kernel-level security events through a Dart WebSocket server to a Flutter desktop dashboard with live feed and summary views.

Built entirely through Mayor-human conversation, not through the full Gas Town orchestration stack (polecats, refineries). Demonstrates the Mayor working as a direct coding partner for greenfield projects.

**Stack:** Dart server + Flutter macOS desktop app | **Events:** exec, open, write, close, fork, exit, rename, unlink, create

---

## Resources

- [Gas Town repo](https://github.com/gastownhall/gastown)
- [Beads repo](https://github.com/gastownhall/beads)
- [Steve Yegge's blog post: "Gas Town: From Clown Show to v1.0"](https://steve-yegge.medium.com/gas-town-from-clown-show-to-v1-0-c239d9a407ec)
- [Gas Town glossary](https://github.com/gastownhall/gastown/blob/main/docs/glossary.md)
- [Beads architecture docs](https://github.com/gastownhall/beads/blob/main/docs/ARCHITECTURE.md)
- [Gas City](https://github.com/gastownhall/gascity) — The successor framework (alpha)
