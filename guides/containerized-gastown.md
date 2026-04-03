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

Agents need to push/pull from GitHub. Options:

### Option 1: GitHub CLI (recommended)

```bash
# Inside the container
gh auth login
```

This stores a token inside the container's home directory (persists in the gt-data volume).

### Option 2: Git credential helper

Mount a read-only git credentials file:

```yaml
volumes:
  - ~/.git-credentials:/home/gtuser/.git-credentials:ro
```

### Option 3: SSH key (read-only)

```yaml
volumes:
  - ~/.ssh/id_ed25519:/home/gtuser/.ssh/id_ed25519:ro
  - ~/.ssh/known_hosts:/home/gtuser/.ssh/known_hosts:ro
```

**Note:** Mounting SSH keys gives agents access to everything those keys can access. Use a deploy key scoped to specific repos if possible.

---

## Secrets Management

The biggest risk with containerized agents isn't filesystem access — it's secrets. Even with bind-mounts locked down, agents need API keys, git tokens, and database credentials to do useful work. If those secrets live in the container's environment or filesystem, a rogue agent can read and exfiltrate them.

**Principle:** Agents should be able to *use* secrets without being able to *read* them directly.

### Architecture: Secrets Sidecar

```
┌─────────────────────────────────────────────────┐
│ Docker Network: gt-net (no docker.sock)         │
│                                                 │
│  ┌─────────────┐       ┌──────────────────┐     │
│  │  secrets     │       │  gastown         │     │
│  │  (sidecar)   │◄──────│  (GT + agents)   │     │
│  │              │ HTTP  │                  │     │
│  │  Reads from: │ :9999 │  Calls:          │     │
│  │  - Keychain  │       │  secrets:9999/   │     │
│  │  - .env file │       │  get?name=...    │     │
│  │  - 1Password │       │                  │     │
│  └─────────────┘       └──────────────────┘     │
│         │                                       │
│         │ (host access for keychain only)        │
└─────────│───────────────────────────────────────┘
          ▼
    macOS Keychain / 1Password / env file
```

The secrets sidecar:
- Runs in its own container on the same Docker network
- Has NO access to the workspace or GT data
- Exposes a simple HTTP API on the internal network (not port-mapped to host)
- Reads secrets from the host's macOS Keychain, 1Password CLI, or an encrypted `.env` file
- Agents in the GT container call `curl secrets:9999/get?name=GITHUB_TOKEN` and get the value
- Secrets are served on-demand, never stored in GT container's env or filesystem

### Docker Compose with Secrets Sidecar

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
      - secrets
    restart: unless-stopped

  secrets:
    build:
      context: ./secrets-sidecar
    container_name: gt-secrets
    # NO ports mapped to host — only accessible on gt-net
    # NO workspace volumes — can't see agent files
    volumes:
      # Mount macOS Keychain access (read-only)
      - /var/run/mach:/var/run/mach:ro
      # Or mount an encrypted env file
      - ./secrets.env:/secrets/secrets.env:ro
    networks:
      - gt-net
    restart: unless-stopped

networks:
  gt-net:
    driver: bridge

volumes:
  gt-data:
```

### Secrets Sidecar Implementation

A minimal Python Flask app that reads from an encrypted env file or macOS Keychain:

```python
# secrets-sidecar/server.py
from flask import Flask, request, jsonify
import os
import subprocess

app = Flask(__name__)

# Load secrets from encrypted env file
SECRETS = {}
env_file = os.environ.get("SECRETS_FILE", "/secrets/secrets.env")
if os.path.exists(env_file):
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, val = line.split("=", 1)
                SECRETS[key.strip()] = val.strip()

ALLOWED_SECRETS = set(os.environ.get("ALLOWED_SECRETS", "").split(","))

@app.route("/get")
def get_secret():
    name = request.args.get("name", "")
    if not name:
        return jsonify({"error": "name parameter required"}), 400
    if ALLOWED_SECRETS and name not in ALLOWED_SECRETS:
        return jsonify({"error": f"secret '{name}' not in allowlist"}), 403
    
    # Try env file first
    if name in SECRETS:
        return jsonify({"value": SECRETS[name]})
    
    # Try macOS Keychain (if available)
    try:
        result = subprocess.run(
            ["security", "find-generic-password", "-a", name, "-w"],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0:
            return jsonify({"value": result.stdout.strip()})
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    
    return jsonify({"error": f"secret '{name}' not found"}), 404

@app.route("/health")
def health():
    return jsonify({"status": "ok", "secrets_loaded": len(SECRETS)})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=9999)
```

```dockerfile
# secrets-sidecar/Dockerfile
FROM python:3.12-slim
RUN pip install flask
COPY server.py /app/server.py
ENV ALLOWED_SECRETS=""
CMD ["python", "/app/server.py"]
```

### Using Secrets from GT Agents

Inside the GT container, agents fetch secrets on-demand:

```bash
# Agent script or Claude command:
export GITHUB_TOKEN=$(curl -s secrets:9999/get?name=GITHUB_TOKEN | jq -r .value)
git push https://${GITHUB_TOKEN}@github.com/org/repo.git

# Or for one-time use (secret never stored in env):
curl -s secrets:9999/get?name=AWS_ACCESS_KEY_ID | jq -r .value | aws configure set aws_access_key_id /dev/stdin
```

### Allowlisting

The sidecar only serves secrets in the `ALLOWED_SECRETS` list:

```yaml
# docker-compose.yml
secrets:
  environment:
    ALLOWED_SECRETS: "GITHUB_TOKEN,ANTHROPIC_API_KEY,NPM_TOKEN"
```

If an agent tries to fetch a secret not in the list, it gets a 403.

### Why NOT to use macOS Keychain or 1Password directly

If the sidecar has full access to the Keychain or 1Password vault, a compromised agent could request *any* secret — not just the ones it needs. The allowlist helps, but a misconfiguration means full vault access. The sidecar should never have more access than the agent needs.

### Recommended: Sealed Secrets File (No Vault Access)

The safest approach: a flat file with *only* the secrets needed for this project, encrypted at rest, mounted read-only into the sidecar. The sidecar has no connection to any broader secrets store.

```bash
# On the host, create a secrets file for this project
mkdir -p ~/.gt-secrets

# Add only the secrets this project needs
cat > ~/.gt-secrets/myproject.env << 'EOF'
GITHUB_TOKEN=ghp_xxxxxxxxxxxx
NPM_TOKEN=npm_xxxxxxxxxxxx
EOF

# Lock down permissions
chmod 600 ~/.gt-secrets/myproject.env
```

The sidecar reads *only* this file. It has no access to Keychain, 1Password, `~/.ssh`, `~/.aws`, or anything else. If an agent compromises the sidecar, they get only the secrets you explicitly put in that file — nothing more.

```yaml
# docker-compose.yml — secrets sidecar
secrets:
  build:
    context: ./secrets-sidecar
  volumes:
    # ONLY this project's secrets file — nothing else
    - ~/.gt-secrets/myproject.env:/secrets/secrets.env:ro
  networks:
    - gt-net
```

**Per-rig secrets:** Create separate env files per project. Only mount the relevant one:

```bash
~/.gt-secrets/
├── frontend.env      # GITHUB_TOKEN for frontend repo
├── backend.env       # GITHUB_TOKEN + DB_PASSWORD for backend
└── infra.env         # AWS keys for infra rig
```

### Rotating Secrets

When you rotate a token:
1. Update the `.env` file on the host
2. Restart the sidecar: `docker compose restart secrets`

The GT container doesn't need to restart — next secret fetch gets the new value.

### Security Properties

| Property | How |
|----------|-----|
| Agents can't access unlisted secrets | Sidecar only has a flat file with explicit secrets |
| No access to Keychain/1Password/SSH | Sidecar has no vault connection or host access |
| Agents can't enumerate secrets | Sidecar only serves by exact name match |
| Blast radius is one project | Per-rig env files limit exposure |
| Secrets not in GT environment | Fetched on-demand via HTTP, not injected at startup |
| Sidecar can't see agent files | No workspace volumes mounted |
| Sidecar not reachable from internet | Only on internal `gt-net` network |
| docker.sock not exposed | Neither container has it |

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
