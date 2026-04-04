# Running Gas Town in Containers

## Why Containerize Gas Town?

Gas Town agents run with `--dangerously-skip-permissions`. On a personal throwaway laptop, that's fine. On a work machine with access to corporate VPN, SSH keys, cloud credentials, and sensitive repos — one rogue polecat could:

- Delete files outside its rig
- Read `~/.ssh/`, `~/.aws/`, browser profiles, Slack tokens
- Run destructive shell commands on the host
- Push to production repos accidentally
- Modify system configs

**The fix:** Run Gas Town inside Docker. Agents get full autonomy *inside the container* but can't touch the host.

---

## Architecture

```
Your Laptop (host)
  │
  ├── Browser → http://localhost:8081  (GT Dashboard)
  ├── Browser → http://localhost:9428/select/vmui  (Agent telemetry)
  ├── Terminal → docker compose exec gastown gt feed  (TUI)
  ├── Terminal → docker compose exec gastown gt mayor attach  (Mayor)
  ├── IDE → edit rig repos directly  (bind-mounted from host)
  │
  └── Docker Compose project: "gastown"
       │
       ├── Container: gastown
       │    ├── gt, bd              (pre-built binaries)
       │    ├── tmux                (agent sessions)
       │    ├── dolt sql-server     (beads database, port 3307)
       │    ├── claude CLI          (agent runtime)
       │    │
       │    ├── /gt/               (town root — persistent volume)
       │    │   ├── mayor/
       │    │   ├── .beads/
       │    │   └── rigs/
       │    │       └── myproject/  (bind-mounted from host)
       │    │
       │    └── /home/agent/.claude (persistent volume + keyring for credentials)
       │
       ├── Container: gt-victoria-logs
       │    └── VictoriaLogs       (agent telemetry, VMUI on :9428)
       │
       └── Container: gt-gateway
            └── Flask proxy        (GitHub/Jira/Slack — agents never see tokens)
```

### Why Everything Runs in One GT Container

GT agents are **tmux sessions sharing a filesystem, Dolt database, event bus, and IPC via mail/hooks**. Splitting polecats into separate containers would break all inter-agent communication — you'd need to rewrite GT's coordination from local files to network protocols. That's a rewrite, not a deployment choice.

The container boundary isolates **GT from your host**, not agents from each other. Agents trust each other (they're your team). The sidecars (VictoriaLogs, gateway) are truly independent services with no shared state, so they correctly get their own containers.

---

## Prerequisites

- Docker Desktop (macOS/Windows) or Docker Engine (Linux)
- The Gas Town source repo cloned locally
- Claude Code CLI subscription (Pro/Max)

---

## Quick Start

### 1. Build the Gas Town image

```bash
cd ~/code/gastown-src   # or wherever you cloned the gastown repo
docker build -t gastown:latest -f ~/learning-gastown/guides/containerized/Dockerfile .
```

This takes ~5 minutes the first time. The image is ~4.5GB and contains everything pre-compiled (Go, Dolt, Claude Code, GT, BD, tmux) plus `gnome-keyring` and `dbus` for Claude Code credential persistence. Container startup is instant after that.

### 2. Configure and start

```bash
cd ~/learning-gastown/guides/containerized

# Edit docker-compose.yml to add your rig repos as bind-mounts (see below)

# Start all services
GIT_USER="Your Name" GIT_EMAIL="you@example.com" docker compose up -d
```

### 3. Attach to the Mayor

```bash
docker compose exec gastown gt mayor start
docker compose exec gastown gt mayor attach
# Detach with Ctrl-B D
```

### 4. Add rigs (inside the container)

```bash
docker compose exec gastown bash

# Inside the container:
gt rig add myproject /gt/rigs/myproject/repo
gt up
```

---

## Rig Repo Setup

### Standalone repos

Each repo on the host gets a bind-mount in `docker-compose.yml`:

```yaml
volumes:
  # One line per rig
  - ~/code/frontend:/gt/rigs/frontend/repo
  - ~/code/backend:/gt/rigs/backend/repo
  - ~/code/infra:/gt/rigs/infra/repo
```

Then inside the container:

```bash
gt rig add frontend /gt/rigs/frontend/repo --adopt
gt rig add backend /gt/rigs/backend/repo --adopt
gt rig add infra /gt/rigs/infra/repo --adopt
```

### Monorepo with multiple projects

If you have a monorepo like:
```
~/code/megarepo/
  ├── projects/auth/
  ├── projects/api/
  ├── projects/web/
  └── shared/
```

Mount the monorepo root once:

```yaml
volumes:
  - ~/code/megarepo:/gt/rigs/megarepo/repo
```

Then use **sparse checkout** to create focused rigs per subproject:

```bash
# Each rig checks out only its relevant directory + shared deps
gt rig add auth https://github.com/yourorg/megarepo \
  --sparse-checkout projects/auth,shared \
  --prefix auth

gt rig add api https://github.com/yourorg/megarepo \
  --sparse-checkout projects/api,shared \
  --prefix api

gt rig add web https://github.com/yourorg/megarepo \
  --sparse-checkout projects/web,shared \
  --prefix web
```

Alternatively, add the whole monorepo as one rig and direct work to specific directories via bead descriptions:

```bash
gt rig add megarepo /gt/rigs/megarepo/repo --adopt
# Then: gt sling "fix auth token refresh in projects/auth/..."
```

The sparse checkout approach is better for large monorepos — each rig's polecats only see the files they need, reducing confusion and context window waste.

---

## Docker Compose Reference

The complete `docker-compose.yml` is in `containerized/docker-compose.yml`. Key configuration:

### Environment variables

Set these when running `docker compose up`:

| Variable | Default | Purpose |
|----------|---------|---------|
| `GIT_USER` | TestUser | Git commit author name |
| `GIT_EMAIL` | test@example.com | Git commit author email |
| `DASHBOARD_PORT` | 8081 | GT dashboard port on host (8081 avoids collision with local GT) |
| `VLOGS_PORT` | 9428 | VictoriaLogs VMUI port on host |
| `SECRETS_FILE` | ./secrets.env.example | Path to secrets file for gateway |
| `GATEWAY_TOKEN` | (empty) | Auth token for gateway (optional) |
| `JIRA_ALLOWED_PROJECTS` | (empty) | Comma-separated Jira project keys |
| `GITHUB_ALLOWED_REPOS` | (empty) | Comma-separated org/repo names |

### Security settings applied

- `cap_drop: ALL` — drops all Linux capabilities
- `cap_add: CHOWN, SETUID, SETGID` — minimum needed for container operation
- `no-new-privileges` — prevents privilege escalation
- `pids: 512` — prevents fork bombs
- `cpus: 4, memory: 4G` — prevents resource exhaustion
- `~/.claude` mounted read-only to staging path; writable `claude-data` volume for credentials
- `gnome-keyring` + `dbus` in container for secure credential storage

---

## Observability

### VictoriaLogs (agent telemetry)

GT streams OTLP telemetry to VictoriaLogs automatically. Open **http://localhost:9428/select/vmui** to query.

Example LogsQL queries:
```
*                                    # all events
_msg:agent.event                     # agent tool calls
_msg:agent.event AND session:mayor   # mayor's tool calls
status:error                         # all errors
_msg:bd.call AND status:error        # failed bead operations
gt.agent:Toast                       # everything from polecat Toast
```

Telemetry is retained for 30 days by default (configurable via `retentionPeriod` in compose).

### GT Dashboard

**http://localhost:8081** — convoy tracking, worker status, merge queue.

### GT Feed (TUI)

```bash
docker compose exec gastown gt feed           # activity dashboard
docker compose exec gastown gt feed -p        # problems view (stuck agents)
docker compose exec gastown gt feed --agents  # agent tool-call activity (see below)
```

### Agent Observability TUI (gt feed --agents)

A custom extension that adds a real-time agent tool-call view to `gt feed`. Shows what each agent is doing moment-to-moment — reads, writes, searches, bash commands — summarized into human-readable one-liners.

```
03:42:01 mayor    Read CHRONICLE.md (lines 1-50)
03:42:03 mayor    Searched codebase for 'gateway' (4 files matched)
03:42:08 Toast    Fixed auth token refresh in src/auth.ts
03:42:12 Toast    Ran test suite (14 passed, 0 failed)
```

Press `a` from any `gt feed` view to toggle into agents mode.

**To use this**, build GT from the fork with the feature branch:

```bash
cd ~/code/gastown-src
git remote add fork https://github.com/homercsimpson50/gastown.git  # if not already added
git fetch fork feat/agent-observability-tui
git checkout feat/agent-observability-tui
make build && make install

# Rebuild the Docker image to include it:
docker build -t gastown:latest -f Dockerfile .
```

Requires VictoriaLogs running (included in this docker-compose) and `GT_OTEL_LOGS_URL` + `GT_LOG_AGENT_OUTPUT=true` (already set in compose).

Source: [homercsimpson50/gastown@feat/agent-observability-tui](https://github.com/homercsimpson50/gastown/tree/feat/agent-observability-tui)

---

## Secrets Gateway

The gateway proxies API calls to GitHub, Jira, and Slack so agents never see raw tokens. It runs inside the Docker network — not port-mapped to the host.

### Setup

1. Create a secrets file:

```bash
mkdir -p ~/.gt-secrets
cp secrets.env.example ~/.gt-secrets/myproject.env
chmod 600 ~/.gt-secrets/myproject.env
# Edit and fill in real tokens
```

2. Point compose at it:

```bash
SECRETS_FILE=~/.gt-secrets/myproject.env docker compose up -d
```

3. Agents call the gateway instead of external APIs:

```bash
# GitHub — create a PR
curl -s -X POST gateway:9999/github/repos/myorg/myproject/pulls \
  -H "Content-Type: application/json" \
  -d '{"title":"Add dark mode","head":"feature/dark-mode","base":"main"}'

# Jira — get an issue
curl -s gateway:9999/jira/issue/MYPROJ-123

# Jira — add a comment
curl -s -X POST gateway:9999/jira/issue/MYPROJ-123/comment \
  -H "Content-Type: application/json" \
  -d '{"body":{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"Fixed in PR #42"}]}]}}'

# Slack — post a message
curl -s -X POST gateway:9999/slack/chat.postMessage \
  -H "Content-Type: application/json" \
  -d '{"channel":"#eng-updates","text":"MYPROJ-123 deployed to staging"}'

# Health check
curl -s gateway:9999/health
```

### What the gateway enforces

- **Path validation** — rejects `..`, `//`, and non-alphanumeric characters
- **Repo/project allowlists** — agents can only access allowed repos/projects
- **Endpoint blocking** — admin, delete, transfer, user management endpoints blocked
- **Method restrictions** — DELETE blocked on Jira; Slack limited to safe methods
- **Payload size limits** — 1MB max request body
- **Audit logging** — every proxied call logged with method, path, and status code

### Per-rig secrets

Use separate secrets files per project to limit blast radius:

```
~/.gt-secrets/
├── frontend.env      # GitHub PAT for frontend repo
├── backend.env       # GitHub PAT + Jira + DB credentials
└── infra.env         # AWS keys for infra rig
```

---

## Daily Workflow

### The `gtc` CLI

Instead of typing long docker compose commands, use `gtc` — a wrapper script in this directory.

```bash
# Add to ~/.zshrc or ~/.bashrc:
alias gtc='~/learning-gastown/guides/containerized/gtc'
```

### Starting with repos

```bash
# Standalone repos
gtc up --repo ~/code/frontend --repo ~/code/backend

# Monorepo projects (mounts only the specified project directories)
gtc up --monorepo ~/code/cpe-analytics -p 42 -p 56

# Both
gtc up --repo ~/code/api --monorepo ~/code/cpe-analytics -p 42
```

`gtc up` starts containers in the background and returns immediately. To change mounts later, run `gtc up` again with new flags — it recreates the container with updated mounts (GT data persists).

### Common commands

```bash
gtc status              # containers + mounted rigs
gtc attach              # Mayor session (Ctrl-B D to detach)
gtc feed                # activity TUI
gtc feed --agents       # agent tool-call TUI (requires fork build)
gtc shell               # bash inside container
gtc exec gt status      # run any gt command
gtc test                # run integration tests (39 checks)
gtc down                # stop everything
```

### Staying up to date with upstream gastown

```bash
gtc sync
```

This fetches the latest from `gastownhall/gastown`, updates your local main, rebases the `feat/agent-observability-tui` branch, and pushes to your fork. Then rebuild:

```bash
cd ~/code/gastown-src && make build && make install
docker build -t gastown:latest -f ~/learning-gastown/guides/containerized/Dockerfile .
gtc up  # recreate container with new image
```

---

## What's Isolated vs Shared

| Component | Where | Persists? | Host can access? |
|-----------|-------|-----------|-----------------|
| gt, bd, tmux, dolt | Container image | Yes (image layer) | No |
| Town data (/gt/) | Docker volume | Yes | Via `docker cp` |
| Rig repos | Bind-mount from host | Yes | Yes (your IDE) |
| Claude settings | Read-only mount (staging) | N/A | N/A |
| Claude credentials | Docker volume (keyring) | Yes | No |
| Dashboard | Port 8080 | N/A | Yes (browser) |
| Telemetry (VMUI) | Port 9428 | Yes (30 days) | Yes (browser) |
| Agent sessions (tmux) | Container memory | While running | Via `docker exec` |
| Secrets | Gateway sidecar only | N/A | Host file only |

### What agents CAN do inside the container

- Full read/write to mounted rig repos
- Execute any command inside the container
- Install packages inside the container
- Make network requests (git push/pull, API calls)
- Access Dolt, tmux, all GT infrastructure
- Call gateway-proxied services (GitHub, Jira, Slack)

### What agents CANNOT do

- Access host filesystem outside mounted paths
- Read `~/.ssh`, `~/.aws`, browser data, etc.
- Read host Claude auth credentials (settings synced, not credentials)
- Modify host Claude config (host mount is read-only staging path)
- Access the host Docker daemon
- Escalate privileges
- Kill host processes
- See raw API tokens (gateway holds them)
- Fork-bomb or OOM the host (resource limits enforced)

---

## Security Review

A comprehensive security review found **23 issues** (2 critical, 6 high, 15 medium). Six have been fixed in this setup; 17 remain as known risks with documented mitigations.

**Key takeaway:** This setup is significantly safer than bare-metal (agents can't read SSH keys, AWS creds, browser data) but is not airtight against a determined adversarial agent inside the container.

Top risks to be aware of:
- **Claude credentials** are stored in the container's keyring — agents with shell access could extract them
- **Outbound network** is unrestricted — agents can exfiltrate data via HTTP or DNS
- **git credential.helper store** saves tokens in plaintext inside the container

See **[SECURITY.md](SECURITY.md)** for the full review with severity ratings, attack examples, fixes applied, and a hardening checklist.

---

## Claude Code Authentication

Claude Code credentials are stored in the container's GNOME Keyring (backed by D-Bus). The entrypoint starts the keyring daemon automatically with an empty password.

On first attach, run `/login` inside Claude Code. The OAuth token persists in the `claude-data` Docker volume across container restarts.

**How it works:**
- Host `~/.claude` is mounted read-only at `/home/agent/.claude-host` (settings only)
- The entrypoint syncs `settings.json` and `settings.local.json` into the writable `/home/agent/.claude`
- Claude Code stores OAuth credentials in GNOME Keyring via `libsecret`
- The `claude-data` named volume persists `/home/agent/.claude` across restarts

**If `/login` doesn't persist:** Check that the container image includes `gnome-keyring` and `dbus` (rebuild with `docker build -t gastown:latest -f Dockerfile .`).

---

## Git Authentication Inside the Container

Agents need to push/pull from GitHub. Options:

### Option 1: GitHub CLI (simplest)

```bash
docker compose exec gastown gh auth login
```

Stores a token inside the container volume. Simple but the agent holds the raw token.

### Option 2: Gateway git credential helper (recommended)

The gateway has a `/git/credential` endpoint that returns the GitHub token for push/pull. It's rate-limited (30 calls/min) and only reachable inside the Docker network.

Create a credential helper script inside the GT container:

```bash
# /usr/local/bin/git-credential-gateway
#!/bin/bash
if [[ "$1" == "get" ]]; then
    RESP=$(curl -s gateway:9999/git/credential 2>/dev/null)
    echo "protocol=$(echo "$RESP" | jq -r .protocol)"
    echo "host=$(echo "$RESP" | jq -r .host)"
    echo "username=$(echo "$RESP" | jq -r .username)"
    echo "password=$(echo "$RESP" | jq -r .password)"
fi
```

Then configure git to use it:

```bash
chmod +x /usr/local/bin/git-credential-gateway
git config --global credential.helper /usr/local/bin/git-credential-gateway
```

The token never touches disk — it's fetched on demand from the gateway and used for that single git operation.

### Option 3: SSH deploy keys

Mount a deploy key (read-only) and configure git to use SSH:

```yaml
volumes:
  - ~/.ssh/deploy_key:/home/agent/.ssh/id_ed25519:ro
```

---

## Troubleshooting

**Container crash-loops on startup** — Check `docker logs gastown`. Common cause: mounting `~/.gitconfig` as read-only (the entrypoint needs to write git config). Don't mount gitconfig — use `GIT_USER`/`GIT_EMAIL` env vars instead.

**"Can't connect to Dolt"** — Dolt may not have started. Run `docker compose exec gastown gt up`.

**Dashboard not loading on localhost:8080** — Check `docker compose ps`. Verify the gastown container is running (not restarting).

**Agent can't push to GitHub** — Set up git auth (see section above).

**Container uses too much disk** — Check `docker system df -v`. Prune old images: `docker image prune`.

**VictoriaLogs shows no data** — Verify the OTLP URL is correct in compose env vars. Check `docker compose exec gastown env | grep OTEL`.

---

## File Layout

```
containerized/
├── README.md                   # This guide
├── SECURITY.md                 # Full security review (23 issues, fixes, hardening checklist)
├── Dockerfile                  # GT container image (Go, Claude Code, keyring, etc.)
├── docker-entrypoint.sh        # Container init (git config, keyring, settings sync)
├── docker-compose.yml          # Base compose (GT + VLogs + Gateway)
├── docker-compose.override.yml # Auto-generated by gtc with repo mounts
├── gtc                         # CLI wrapper (gtc up, gtc attach, gtc feed, etc.)
├── test-container.sh           # Integration tests (39 checks across 10 categories)
├── secrets.env.example         # Template for gateway secrets
└── gateway-sidecar/
    ├── Dockerfile              # Gateway container build
    ├── server.py               # Flask proxy with security controls
    └── requirements.txt        # Python dependencies
```
