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
  ├── Browser → http://localhost:8080  (GT Dashboard)
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
       │    └── /home/agent/.claude (subscription auth — read-only mount)
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
docker build -t gastown:latest -f Dockerfile .
```

This takes ~5 minutes the first time. The image is ~4.5GB and contains everything pre-compiled (Go, Dolt, Claude Code, GT, BD, tmux). Container startup is instant after that.

### 2. Configure and start

```bash
cd ~/learning-gastown/guides/containerized   # or wherever you put the compose file

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
| `DASHBOARD_PORT` | 8080 | GT dashboard port on host |
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
- `~/.claude:ro` — read-only auth mount

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

**http://localhost:8080** — convoy tracking, worker status, merge queue.

### GT Feed (TUI)

```bash
docker compose exec gastown gt feed           # activity dashboard
docker compose exec gastown gt feed -p        # problems view (stuck agents)
```

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

### Shell aliases (add to ~/.zshrc or ~/.bashrc)

```bash
alias gtx='docker compose -f ~/learning-gastown/guides/containerized/docker-compose.yml exec gastown'
alias gtmayor='gtx gt mayor attach'
alias gtfeed='gtx gt feed'
alias gtstatus='gtx gt status'
```

Then: `gtmayor`, `gtfeed`, `gtstatus`.

### Starting and stopping

```bash
# Start (if stopped)
docker compose -f ~/learning-gastown/guides/containerized/docker-compose.yml up -d

# Stop Gas Town services first (clean shutdown)
docker compose exec gastown gt down

# Stop containers
docker compose stop

# Destroy and recreate (volumes persist)
docker compose down && docker compose up -d
```

### Updating Gas Town

When a new version of GT is released:

```bash
# Rebuild the image with latest source
cd ~/code/gastown-src && git pull && docker build -t gastown:latest -f Dockerfile .

# Recreate the container (volumes persist)
cd ~/learning-gastown/guides/containerized
docker compose down && docker compose up -d
```

---

## What's Isolated vs Shared

| Component | Where | Persists? | Host can access? |
|-----------|-------|-----------|-----------------|
| gt, bd, tmux, dolt | Container image | Yes (image layer) | No |
| Town data (/gt/) | Docker volume | Yes | Via `docker cp` |
| Rig repos | Bind-mount from host | Yes | Yes (your IDE) |
| Claude auth | Read-only mount | N/A | N/A |
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
- Modify Claude auth credentials (read-only mount)
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
- **Claude auth token** is readable by agents (read-only mount doesn't prevent reads)
- **Outbound network** is unrestricted — agents can exfiltrate data via HTTP or DNS
- **git credential.helper store** saves tokens in plaintext inside the container

See **[SECURITY.md](SECURITY.md)** for the full review with severity ratings, attack examples, fixes applied, and a hardening checklist.

---

## Git Authentication Inside the Container

Agents need to push/pull from GitHub. Options:

### Option 1: GitHub CLI (simplest)

```bash
docker compose exec gastown gh auth login
```

Stores a token inside the container volume. Simple but the agent holds the raw token.

### Option 2: Gateway git credential helper (recommended)

Add a thin script inside the GT container that fetches credentials from the gateway:

```bash
# /usr/local/bin/git-credential-gateway
#!/bin/bash
if [[ "$1" == "get" ]]; then
    TOKEN=$(curl -s gateway:9999/github/internal/token 2>/dev/null | jq -r .value)
    echo "protocol=https"
    echo "host=github.com"
    echo "username=x-access-token"
    echo "password=${TOKEN}"
fi
```

Then configure git to use it:

```bash
git config --global credential.helper /usr/local/bin/git-credential-gateway
```

This requires adding a `/github/internal/token` endpoint to the gateway server. The token stays inside the Docker network and is rate-limited.

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
├── docker-compose.yml          # Three-container setup (GT + VLogs + Gateway)
├── test-container.sh           # Integration tests (38 checks across 10 categories)
├── secrets.env.example         # Template for gateway secrets
└── gateway-sidecar/
    ├── Dockerfile              # Gateway container build
    ├── server.py               # Flask proxy with security controls
    └── requirements.txt        # Python dependencies
```
