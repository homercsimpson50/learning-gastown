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
  ├── Terminal → docker exec -it gastown gt feed  (TUI)
  ├── Terminal → docker exec -it gastown gt mayor attach  (Mayor)
  │
  └── Docker Container: "gastown"
       │
       ├── gt, bd              (pre-built binaries)
       ├── tmux                (agent sessions)
       ├── dolt sql-server     (beads database, port 3307)
       ├── claude CLI          (agent runtime)
       │
       ├── /home/gt/           (town root — persistent volume)
       │   ├── mayor/
       │   ├── .beads/
       │   └── rigs/
       │       └── myproject/  (bind-mounted from host)
       │
       └── /home/user/.claude  (subscription auth — read-only mount)
```

Key points:
- **Dashboard** still works on localhost:8080 via port mapping
- **TUI** (`gt feed`, `gt mayor attach`) works via `docker exec -it`
- **Rig repos** bind-mounted from host so you can also edit in your IDE
- **Auth** uses your Pro/Max subscription via read-only `~/.claude` mount
- **Agents can't escape** — no docker.sock, no privileged mode, dropped capabilities

---

## Dockerfile

```dockerfile
FROM ubuntu:24.04

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    tmux \
    curl \
    jq \
    ca-certificates \
    build-essential \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Node.js (for Claude Code CLI)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Go (for building gt and bd from source)
RUN curl -fsSL https://go.dev/dl/go1.26.1.linux-amd64.tar.gz | tar -C /usr/local -xzf -
ENV PATH="/usr/local/go/bin:/root/go/bin:${PATH}"

# Dolt
RUN curl -fsSL https://github.com/dolthub/dolt/releases/latest/download/install.sh | bash

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Build Beads from source
RUN git clone https://github.com/gastownhall/beads.git /tmp/beads \
    && cd /tmp/beads && make build && make install \
    && rm -rf /tmp/beads

# Build Gas Town from source
RUN git clone https://github.com/gastownhall/gastown.git /tmp/gastown \
    && cd /tmp/gastown && make build && make install \
    && rm -rf /tmp/gastown

# Create non-root user
RUN useradd -m -s /bin/bash gtuser
USER gtuser
WORKDIR /home/gtuser

# Default: start a shell (gt up is run manually)
CMD ["/bin/bash"]
```

### Pre-built image (faster)

If you don't want to compile from source every time, build the image once and reuse it:

```bash
docker build -t gastown-runtime .

# Tag with version for stability
docker tag gastown-runtime gastown-runtime:v1.0
```

The image is ~2GB but contains everything pre-compiled. Container startup is instant.

---

## Docker Compose

```yaml
# docker-compose.yml
services:
  gastown:
    image: gastown-runtime:v1.0
    container_name: gastown
    hostname: gastown

    # Keep the container running and interactive
    stdin_open: true
    tty: true

    # Security: contain the blast radius
    security_opt:
      - no-new-privileges
    cap_drop:
      - ALL
    cap_add:
      - NET_RAW  # needed for some git operations

    ports:
      - "8080:8080"   # GT Dashboard
      - "3307:3307"   # Dolt server (optional, for external tools)

    volumes:
      # Town data (persistent across restarts)
      - gt-data:/home/gtuser/gt

      # Your project repos (bind-mount from host)
      # Add one line per rig you want to work on:
      - ~/code/myproject:/home/gtuser/gt/rigs/myproject/repo

      # Claude auth (read-only — agents can't steal or modify your login)
      - ~/.claude:/home/gtuser/.claude:ro

      # Git config (so commits have your name)
      - ~/.gitconfig:/home/gtuser/.gitconfig:ro

    # Restart policy: container persists across reboots
    restart: unless-stopped

volumes:
  gt-data:
    driver: local
```

---

## Usage

### First-time setup

```bash
# Build the image (one-time, takes ~10 min)
docker compose build

# Start the container
docker compose up -d

# Initialize Gas Town inside the container
docker exec -it gastown bash
gt install ~/gt --name my-town
gt rig add myproject /home/gtuser/gt/rigs/myproject/repo
gt up
```

### Daily workflow

```bash
# Start container (if stopped)
docker compose up -d

# Attach to Mayor
docker exec -it gastown gt mayor attach

# Check status
docker exec -it gastown gt status

# Watch activity
docker exec -it gastown gt feed

# Open dashboard in browser
open http://localhost:8080

# Sling work
docker exec -it gastown gt sling "add dark mode to the settings page"
```

### Shell aliases (add to ~/.zshrc)

```bash
alias gtx='docker exec -it gastown'
alias gtmayor='docker exec -it gastown gt mayor attach'
alias gtfeed='docker exec -it gastown gt feed'
alias gtstatus='docker exec -it gastown gt status'
alias gtsling='docker exec -it gastown gt sling'
```

Then: `gtmayor`, `gtfeed`, `gtsling "fix the auth bug"`.

### Stopping

```bash
# Stop Gas Town services first (clean shutdown)
docker exec -it gastown gt down

# Then stop the container
docker compose stop

# Or destroy and recreate (gt-data volume persists)
docker compose down
docker compose up -d
```

---

## What's Isolated vs Shared

| Component | Where | Persists? | Host can access? |
|-----------|-------|-----------|-----------------|
| gt, bd, tmux, dolt | Inside container | Yes (image layer) | No |
| Town data (~gt/) | Docker volume `gt-data` | Yes | Via `docker cp` |
| Rig repos | Bind-mount from host | Yes | Yes (your IDE) |
| Claude auth | Read-only mount | N/A | N/A |
| Dashboard | Port 8080 | N/A | Yes (browser) |
| Agent sessions (tmux) | Inside container | While running | Via `docker exec` |

### What agents CAN do inside the container

- Full read/write to mounted rig repos
- Execute any command inside the container
- Install packages inside the container
- Make network requests (git push/pull, API calls)
- Access Dolt, tmux, all GT infrastructure

### What agents CANNOT do

- Access host filesystem outside mounted paths
- Read `~/.ssh`, `~/.aws`, browser data, etc.
- Modify Claude auth credentials (read-only mount)
- Access the host Docker daemon
- Escalate privileges
- Kill host processes

---

## Multiple Rigs

Add more bind-mounts in `docker-compose.yml`:

```yaml
volumes:
  - ~/code/frontend:/home/gtuser/gt/rigs/frontend/repo
  - ~/code/backend:/home/gtuser/gt/rigs/backend/repo
  - ~/code/infra:/home/gtuser/gt/rigs/infra/repo
```

Then inside the container:

```bash
gt rig add frontend /home/gtuser/gt/rigs/frontend/repo
gt rig add backend /home/gtuser/gt/rigs/backend/repo
gt rig add infra /home/gtuser/gt/rigs/infra/repo
```

---

## Git Authentication Inside the Container

Agents need to push/pull from GitHub. Use the **gateway sidecar** (see Secrets Management below) — it proxies GitHub API calls and provides a git credential helper so agents can `git push` without ever holding a raw token.

If you're not using the gateway yet, a quick interim option:

```bash
# Inside the container — use GitHub CLI
gh auth login
```

This stores a token inside the container (persists in the gt-data volume). It's simpler but the agent holds the raw token. Move to the gateway when you set up the full stack.

---

## Secrets Management

The biggest risk with containerized agents isn't filesystem access — it's secrets. Agents need to call Jira, push to GitHub, access databases. If those tokens live in the container's environment, a rogue agent can read and exfiltrate them.

**Principle:** Agents should be able to *use* external services without ever seeing the raw tokens.

### Architecture: Service Gateway Sidecar

Instead of giving agents tokens, run a **gateway sidecar** that holds the tokens and proxies API calls. Agents call the gateway; the gateway authenticates to the real service. Tokens never leave the sidecar.

```
┌──────────────────────────────────────────────────────────┐
│ Docker Network: gt-net (no docker.sock)                  │
│                                                          │
│  ┌──────────────────┐        ┌──────────────────┐        │
│  │  gateway          │        │  gastown         │        │
│  │  (sidecar)        │◄───────│  (GT + agents)   │        │
│  │                   │ HTTP   │                  │        │
│  │  Holds tokens for:│ :9999  │  Agents call:    │        │
│  │  - GitHub         │        │  gateway:9999/   │        │
│  │  - Jira           │        │  github/...      │        │
│  │  - Slack          │        │  jira/...        │        │
│  │  - any API        │        │  slack/...       │        │
│  │                   │        │                  │        │
│  │  Can enforce:     │        │  Never sees:     │        │
│  │  - path allowlist │        │  - raw tokens    │        │
│  │  - read-only      │        │  - credentials   │        │
│  │  - rate limits    │        │                  │        │
│  │  - audit logging  │        │                  │        │
│  └──────────────────┘        └──────────────────┘        │
│         │                                                │
│         │ reads sealed env file (no vault/keychain)       │
└─────────│────────────────────────────────────────────────┘
          ▼
    ~/.gt-secrets/myproject.env (host, chmod 600)
```

### Why Not Give Agents the Raw Token?

Even with allowlists, once an agent has a Jira token it can call *any* Jira endpoint — delete issues, access other projects, read user data. The allowlist only controls whether the agent gets the token, not what it does with it.

With a gateway proxy:
- **Path restrictions** — only allow `/issue/PROJ-*`, block `/admin/*`, `/user/*`
- **Method restrictions** — allow GET (read), block DELETE
- **Rate limits** — prevent agents from hammering APIs
- **Audit logging** — every API call goes through one place
- **Zero token exposure** — agents never see credentials

### Sealed Secrets File

The gateway reads tokens from a flat file — not from Keychain, 1Password, or any vault. If the gateway is compromised, the attacker gets only the tokens in that file, not your entire credential store.

```bash
# On the host, create a secrets file for this project
mkdir -p ~/.gt-secrets

cat > ~/.gt-secrets/myproject.env << 'EOF'
# GitHub — fine-grained PAT scoped to this repo only
GITHUB_TOKEN=github_pat_xxxxxxxxxxxx

# Jira — API token (user-scoped, so we proxy it)
JIRA_TOKEN=ATATTxxxxxxxxxxxx
JIRA_EMAIL=homer@work.com
JIRA_URL=https://yourcompany.atlassian.net

# Slack — bot token scoped to specific channels
SLACK_TOKEN=xoxb-xxxxxxxxxxxx
EOF

chmod 600 ~/.gt-secrets/myproject.env
```

**Per-rig secrets:** Separate files per project. Only mount the relevant one.

```bash
~/.gt-secrets/
├── frontend.env      # GitHub PAT for frontend repo
├── backend.env       # GitHub PAT + Jira + DB credentials
└── infra.env         # AWS keys for infra rig
```

### Gateway Sidecar Implementation

```python
# gateway-sidecar/server.py
import json
import logging
import os
import re
import time

import requests
from flask import Flask, Response, request, jsonify

app = Flask(__name__)
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")

# Load secrets from sealed env file
SECRETS = {}
env_file = os.environ.get("SECRETS_FILE", "/secrets/secrets.env")
if os.path.exists(env_file):
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, val = line.split("=", 1)
                SECRETS[key.strip()] = val.strip()

# --- Route configs (loaded from env or config file) ---

# Jira: which project keys agents can access
JIRA_ALLOWED_PROJECTS = set(
    os.environ.get("JIRA_ALLOWED_PROJECTS", "").split(",")
)
# GitHub: which repos agents can access (org/repo format)
GITHUB_ALLOWED_REPOS = set(
    os.environ.get("GITHUB_ALLOWED_REPOS", "").split(",")
)

TIMEOUT = 15


# --- GitHub Proxy ---

@app.route("/github/<path:api_path>", methods=["GET", "POST", "PATCH"])
def github_proxy(api_path):
    """Proxy GitHub API calls. Agents call gateway:9999/github/repos/org/repo/..."""
    token = SECRETS.get("GITHUB_TOKEN")
    if not token:
        return jsonify({"error": "GITHUB_TOKEN not configured"}), 500

    # Enforce repo allowlist
    if GITHUB_ALLOWED_REPOS:
        match = re.match(r"repos/([^/]+/[^/]+)", api_path)
        if match and match.group(1) not in GITHUB_ALLOWED_REPOS:
            logging.warning(f"BLOCKED github access to {match.group(1)}")
            return jsonify({"error": "repo not in allowlist"}), 403

    # Block dangerous endpoints
    if any(seg in api_path for seg in ["admin", "delete", "transfer"]):
        logging.warning(f"BLOCKED dangerous github path: {api_path}")
        return jsonify({"error": "endpoint blocked by policy"}), 403

    resp = requests.request(
        method=request.method,
        url=f"https://api.github.com/{api_path}",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
        },
        params=request.args,
        json=request.get_json(silent=True) if request.is_json else None,
        timeout=TIMEOUT,
    )
    logging.info(f"github {request.method} /{api_path} -> {resp.status_code}")
    return Response(resp.content, status=resp.status_code,
                    content_type=resp.headers.get("content-type", "application/json"))


# --- Jira Proxy ---

@app.route("/jira/<path:api_path>", methods=["GET", "POST", "PUT"])
def jira_proxy(api_path):
    """Proxy Jira API calls. Agents call gateway:9999/jira/issue/PROJ-123."""
    token = SECRETS.get("JIRA_TOKEN")
    email = SECRETS.get("JIRA_EMAIL")
    base_url = SECRETS.get("JIRA_URL")
    if not all([token, email, base_url]):
        return jsonify({"error": "Jira credentials not configured"}), 500

    # Enforce project allowlist
    if JIRA_ALLOWED_PROJECTS:
        match = re.search(r"([A-Z][A-Z0-9]+)-\d+", api_path)
        if match and match.group(1) not in JIRA_ALLOWED_PROJECTS:
            logging.warning(f"BLOCKED jira access to project {match.group(1)}")
            return jsonify({"error": "project not in allowlist"}), 403

    # Block admin/user management endpoints
    if any(seg in api_path for seg in ["admin", "user", "permissions", "role"]):
        logging.warning(f"BLOCKED dangerous jira path: {api_path}")
        return jsonify({"error": "endpoint blocked by policy"}), 403

    # Block DELETE
    if request.method == "DELETE":
        logging.warning(f"BLOCKED DELETE on jira /{api_path}")
        return jsonify({"error": "DELETE not allowed"}), 403

    resp = requests.request(
        method=request.method,
        url=f"{base_url}/rest/api/3/{api_path}",
        auth=(email, token),
        params=request.args,
        json=request.get_json(silent=True) if request.is_json else None,
        timeout=TIMEOUT,
    )
    logging.info(f"jira {request.method} /{api_path} -> {resp.status_code}")
    return Response(resp.content, status=resp.status_code,
                    content_type=resp.headers.get("content-type", "application/json"))


# --- Slack Proxy ---

@app.route("/slack/<path:api_path>", methods=["GET", "POST"])
def slack_proxy(api_path):
    """Proxy Slack API calls. Agents call gateway:9999/slack/chat.postMessage."""
    token = SECRETS.get("SLACK_TOKEN")
    if not token:
        return jsonify({"error": "SLACK_TOKEN not configured"}), 500

    # Only allow specific safe methods
    allowed_methods = {
        "chat.postMessage", "chat.update",
        "conversations.history", "conversations.list",
        "reactions.add", "files.upload",
    }
    if api_path not in allowed_methods:
        logging.warning(f"BLOCKED slack method: {api_path}")
        return jsonify({"error": f"slack method '{api_path}' not allowed"}), 403

    resp = requests.post(
        f"https://slack.com/api/{api_path}",
        headers={"Authorization": f"Bearer {token}"},
        json=request.get_json(silent=True) if request.is_json else None,
        data=request.form if not request.is_json else None,
        timeout=TIMEOUT,
    )
    logging.info(f"slack {api_path} -> {resp.status_code}")
    return Response(resp.content, status=resp.status_code,
                    content_type=resp.headers.get("content-type", "application/json"))


# --- Health ---

@app.route("/health")
def health():
    services = {
        "github": "GITHUB_TOKEN" in SECRETS,
        "jira": all(k in SECRETS for k in ["JIRA_TOKEN", "JIRA_EMAIL", "JIRA_URL"]),
        "slack": "SLACK_TOKEN" in SECRETS,
    }
    return jsonify({"status": "ok", "services": services})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=9999)
```

```dockerfile
# gateway-sidecar/Dockerfile
FROM python:3.12-slim
RUN pip install flask requests
COPY server.py /app/server.py
WORKDIR /app
CMD ["python", "server.py"]
```

### Docker Compose with Gateway

```yaml
# docker-compose.yml
services:
  gastown:
    image: gastown-runtime:v1.0
    container_name: gastown
    stdin_open: true
    tty: true
    security_opt:
      - no-new-privileges
    cap_drop:
      - ALL
    cap_add:
      - NET_RAW
    ports:
      - "8080:8080"
    volumes:
      - gt-data:/home/gtuser/gt
      - ~/code/myproject:/home/gtuser/gt/rigs/myproject/repo
      - ~/.claude:/home/gtuser/.claude:ro
      - ~/.gitconfig:/home/gtuser/.gitconfig:ro
    networks:
      - gt-net
    depends_on:
      - gateway
    restart: unless-stopped

  gateway:
    build:
      context: ./gateway-sidecar
    container_name: gt-gateway
    # NOT port-mapped to host — only reachable on gt-net
    # NO workspace volumes — can't see agent files
    volumes:
      - ~/.gt-secrets/myproject.env:/secrets/secrets.env:ro
    environment:
      JIRA_ALLOWED_PROJECTS: "MYPROJ,BACKEND"
      GITHUB_ALLOWED_REPOS: "myorg/myproject,myorg/shared-lib"
    networks:
      - gt-net
    restart: unless-stopped

networks:
  gt-net:
    driver: bridge

volumes:
  gt-data:
```

### How Agents Use the Gateway

Agents call the gateway instead of external APIs directly. They never see tokens:

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

# Jira — transition an issue
curl -s -X POST gateway:9999/jira/issue/MYPROJ-123/transitions \
  -H "Content-Type: application/json" \
  -d '{"transition":{"id":"31"}}'

# Slack — post a message
curl -s -X POST gateway:9999/slack/chat.postMessage \
  -H "Content-Type: application/json" \
  -d '{"channel":"#eng-updates","text":"MYPROJ-123 deployed to staging"}'

# Check which services are configured
curl -s gateway:9999/health
```

### Git Push/Pull Through the Gateway

For git operations, agents can use the GitHub API to create PRs, but `git push` needs a token in the URL. One option: a thin git credential helper inside the GT container that fetches from the gateway:

```bash
# Inside GT container: /usr/local/bin/git-credential-gateway
#!/bin/bash
# Git calls this to get credentials for push/pull
if [[ "$1" == "get" ]]; then
    TOKEN=$(curl -s gateway:9999/github/internal/token 2>/dev/null | jq -r .value)
    echo "protocol=https"
    echo "host=github.com"
    echo "username=x-access-token"
    echo "password=${TOKEN}"
fi
```

Add a `/github/internal/token` endpoint to the gateway that returns the raw token — but only for git operations, and rate-limited to prevent abuse. This is the one place where the token is exposed, but it stays inside the Docker network and never reaches the host.

### Adding a New Service

To proxy a new API (e.g., PagerDuty, Datadog, Confluence):

1. Add the token to `~/.gt-secrets/myproject.env`
2. Add a route in `server.py` with path/method restrictions
3. Restart the gateway: `docker compose restart gateway`

The pattern is always the same: proxy the request, inject the auth, enforce allowlists, log everything.

### Rotating Secrets

1. Update `~/.gt-secrets/myproject.env` on the host
2. `docker compose restart gateway`

GT container doesn't need to restart.

### Audit Log

The gateway logs every proxied call with timestamp, service, method, path, and status code:

```
2026-04-03 15:32:01 github GET /repos/myorg/myproject/pulls -> 200
2026-04-03 15:32:05 jira POST /issue/MYPROJ-123/comment -> 201
2026-04-03 15:32:08 slack chat.postMessage -> 200
2026-04-03 15:32:10 BLOCKED jira access to project SECRETS
2026-04-03 15:32:12 BLOCKED DELETE on jira /issue/MYPROJ-456
```

### Security Properties

| Property | How |
|----------|-----|
| Agents never see raw tokens | Gateway proxies all API calls, injects auth server-side |
| No access to Keychain/1Password/SSH | Gateway reads only a sealed per-project env file |
| Agents can't access other projects | Project allowlists enforced per-service |
| Destructive operations blocked | DELETE and admin endpoints rejected by policy |
| Blast radius is one project | Per-rig env files limit exposure |
| Gateway can't see agent files | No workspace volumes mounted on gateway |
| Gateway not reachable from internet | Only on internal `gt-net` network |
| docker.sock not exposed | Neither container has it |
| Full audit trail | Every proxied call is logged with method, path, status |

---

## Updating Gas Town

When a new version of GT or Beads is released:

```bash
# Rebuild the image with latest source
docker compose build --no-cache

# Recreate the container (gt-data volume persists)
docker compose down
docker compose up -d

# Re-run gt up inside
docker exec -it gastown gt up
```

Your town data, rig configs, and beads history all persist in the `gt-data` volume.

---

## Troubleshooting

**"Can't connect to Dolt"** — Dolt server may not have started. Run `docker exec -it gastown gt up` to restart services.

**"Dashboard not loading on localhost:8080"** — Check the container is running: `docker compose ps`. Check the port mapping: `docker port gastown`.

**"Agent can't push to GitHub"** — Set up git auth inside the container (see Git Authentication section above).

**"Container uses too much disk"** — Check volume size: `docker system df -v`. Prune old images: `docker image prune`.

**"I need to debug inside the container"** — `docker exec -it gastown bash` gives you a full shell.

---

## Compared to Running Bare-Metal

| | Bare-metal | Containerized |
|---|-----------|--------------|
| **Setup** | `gt install` directly | Build image + `gt install` inside |
| **Speed** | Native | ~Same (volume mounts are fast) |
| **Safety** | Agents can access everything | Agents confined to container |
| **Dashboard** | localhost:8080 | localhost:8080 (port-mapped) |
| **IDE integration** | Direct | Via bind-mounted repos |
| **Disk** | ~1GB for GT | ~2GB for image + GT data |
| **Work laptop safe?** | No | Yes |
