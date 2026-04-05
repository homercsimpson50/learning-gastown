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

### Hot-mount repos (recommended — no restart)

Add and remove repos while the container is running:

```bash
gtc mount ~/code/frontend            # Mount a repo
gtc mount ~/code/backend api-server  # Mount with custom name
gtc mounts                           # List all mounts
gtc unmount frontend                 # Remove a mount
```

Then register inside the container:
```bash
gtc exec gt rig add frontend /gt/rigs-host/frontend --adopt
```

**How it works**: `gtc mount` creates a symlink in `~/.gtc-rigs/` on the host. This directory is bind-mounted into the container at `/gt/rigs-host/`. Docker follows symlinks through the mount — the container sees changes immediately.

**Config**: Set `GTC_RIGS_DIR` in `~/.gtc.conf` to change the staging directory:
```bash
echo 'GTC_RIGS_DIR="$HOME/my-rigs"' > ~/.gtc.conf
```

### Legacy: Static mounts (requires restart)

Each repo on the host gets a bind-mount in `docker-compose.yml`:

```yaml
volumes:
  - ~/code/frontend:/gt/rigs/frontend/repo
  - ~/code/backend:/gt/rigs/backend/repo
```

Then inside the container:

```bash
gt rig add frontend /gt/rigs/frontend/repo --adopt
gt rig add backend /gt/rigs/backend/repo --adopt
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

**Local (non-container) setup:** VictoriaLogs can also run natively via `brew install victorialogs && brew services start victorialogs`. See the [main README](../../README.md#local-victorialogs-setup-for-gt-feed---agents) for local setup instructions. Local and container setups are fully independent — no cross-contamination.

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
- Read host Claude auth credentials (OAuth: no static secrets in `~/.claude/`; Bedrock: short-lived creds passed as env vars, no host mounting)
- Modify host Claude config (host mount is read-only staging path)
- Access the host Docker daemon
- Escalate privileges
- Kill host processes
- See raw API tokens (gateway holds them)
- Fork-bomb or OOM the host (resource limits enforced)

---

## Security Review

A comprehensive security review found **23 issues** (2 critical, 6 high, 15 medium). Seven have been fixed or reduced; 16 remain as known risks with documented mitigations.

**Key takeaway:** This setup is significantly safer than bare-metal (agents can't read SSH keys, AWS creds, browser data) but is not airtight against a determined adversarial agent inside the container.

**Auth method matters:** The original C1 (critical — credential exfiltration from `~/.claude/`) assumed static API keys. If you authenticate via **Google OAuth (Pro/Max)** or **AWS Bedrock**, there are no static secrets in `~/.claude/` to exfiltrate, reducing this to low risk. See [SECURITY.md](SECURITY.md) C1 for details.

Remaining risks to be aware of:
- **Outbound network** is unrestricted — agents can exfiltrate data via HTTP or DNS
- **git credential.helper store** saves tokens in plaintext inside the container
- **Static API keys** (if used instead of OAuth/Bedrock) remain a high-risk exfiltration target

See **[SECURITY.md](SECURITY.md)** for the full review with severity ratings, attack examples, fixes applied, and a hardening checklist.

---

## Claude Code Authentication

### How it works (zero manual steps after first setup)

Your host machine authenticates Claude Code via Google OAuth (Pro/Max subscription). The containerized setup inherits this automatically:

1. **Host side**: You logged in once via browser → Claude Code stored OAuth tokens in `~/.claude/.credentials.json`
2. **Container entrypoint**: On first start, copies `.credentials.json` from the read-only host mount (`~/.claude-host/`) into the container's writable `claude-data` volume
3. **Claude Code inside container**: Finds the refresh token, silently gets fresh access tokens — no browser needed
4. **Persistence**: The `claude-data` Docker volume survives container restarts, `gtc down`/`up`, laptop reboots, and image rebuilds. Auth is permanent until you explicitly delete the volume.

### One-time setup (first time only)

On the very first `gtc attach`, Claude Code shows a theme picker (Dark/Light mode). Select one and press Enter. This is the only manual step — it persists in the volume and never appears again.

If you see a login screen instead of the theme picker, your host `~/.claude/.credentials.json` may be missing or expired. Fix:
```bash
# On the host (not in container):
claude    # This opens browser → Google OAuth → stores credentials
# Then restart the container to re-sync:
gtc down && gtc up --repo ...
```

### For teammates

Anyone using this setup needs:
1. A Claude Pro/Max subscription authenticated on their host machine (`claude` → browser login → done)
2. GitHub CLI authenticated on their host machine (`gh auth login` → browser login → done)
3. That's it. The container inherits both credentials automatically.

No API keys, no tokens to manage, no secrets files. The container entrypoint handles everything.

### Credential lifecycle

| Event | What happens |
|-------|-------------|
| `gtc up` (first time) | Entrypoint copies `.credentials.json` from host into volume |
| `gtc up` (subsequent) | Volume already has credentials, entrypoint skips copy |
| Laptop restart | Volume persists, credentials still valid |
| `gtc down && gtc up` | Volume persists, credentials still valid |
| Image rebuild | Volume persists (volumes are independent of images) |
| OAuth token expires | Claude Code uses refresh token automatically |
| Refresh token revoked | Delete volume: `docker volume rm gastown_claude-data`, then `gtc up` to re-sync |

### What NOT to do

- Do NOT pass `ANTHROPIC_API_KEY` — use OAuth only
- Do NOT run `/login` inside the container — credentials sync from host
- Do NOT mount `~/.claude` as writable — the read-only host mount + separate volume is the correct pattern

### AWS Bedrock (planned)

Support for AWS Bedrock as an alternative to Claude Pro/Max OAuth is planned for environments where personal Claude subscriptions are not permitted. Bedrock credentials are short-lived, auto-expire, and passed as environment variables — no host filesystem mounting needed. See [TODO.md](TODO.md) for details.

### Security note on auth methods

Neither OAuth (Pro/Max) nor Bedrock stores long-lived static secrets in `~/.claude/`. This means mounting `~/.claude:ro` into the container exposes only settings and preferences, not credentials. The critical exfiltration risk (SECURITY.md C1) only applies if you use a static `ANTHROPIC_API_KEY`.

---

## Git Authentication Inside the Container

### Automatic (default — zero setup)

The entrypoint syncs your host's `gh` CLI credentials (`~/.config/gh/hosts.yml`) into the container. The container can push/pull from GitHub immediately — no manual auth needed.

**Prerequisites on host:** `gh auth login` (one time)

The entrypoint also runs `gh auth setup-git` which configures git to use `gh` as a credential helper. This means `git push` and `git pull` just work inside the container.

Like Claude credentials, the `gh` config is mounted read-only from the host and copied into the container on first start. It persists in the container across restarts.

### Alternative: Gateway git credential helper (for shared/team setups)

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
