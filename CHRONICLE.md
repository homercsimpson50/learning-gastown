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

*This chronicle will be updated as exploration continues.*
