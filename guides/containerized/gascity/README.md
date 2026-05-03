# Running Gas City in Containers

A containerized setup for [Gas City](https://github.com/gastownhall/gascity)
modeled after the sibling [Gas Town container guide](../README.md). Run the
orchestration-builder SDK with full agent autonomy *inside* a Docker
container, while your host filesystem, SSH keys, AWS creds, and browser
profiles stay out of reach.

---

## Why Containerize Gas City?

Same reason as Gas Town: agents run with `--dangerously-skip-permissions`.
On a personal laptop with throwaway repos that's fine. On a work machine
with corporate VPN and credentials, one rogue agent can do real damage.

Gas City also adds a **machine-wide supervisor** managed by launchd
(macOS) or systemd (Linux) — that's a great default for personal use, but
it means the agents have a long-lived foothold on your host. The
container collapses that into one process you can `docker compose down`
to fully evict.

---

## What's different from the Gas Town container?

If you've used the sibling guide, the differences are minimal:

| Aspect | Gas Town | Gas City |
|---|---|---|
| Binary | `gt` | `gc` |
| Workspace | `gt install /gt --git` (mayor + rigs) | `gc init` (city + rigs) |
| Config | implicit | declarative `city.toml` + `pack.toml` |
| Supervisor | runs as part of the gt processes | separate `gc supervisor run` (foreground in container) |
| Image base | `docker/sandbox-templates:claude-code` | same |
| Volumes | `/gt` workspace | `/city` workspace |
| Code mount | `/gt/rigs-host` | `/city/rigs-host` |
| Host credentials sync | identical | identical |

The Dockerfile and compose file mirror the gastown ones almost line-for-line
on purpose — same security model (drop ALL caps, no-new-privileges,
resource limits, read-only host-credential staging) and same persistence
pattern (Docker volumes for state, bind mount for code).

---

## Architecture

```
Your Laptop (host)
  │
  ├── Terminal → docker compose exec gascity bash
  ├── Terminal → docker compose exec gascity gc cities
  ├── IDE → edit rig repos directly  (bind-mounted from host)
  │
  └── Docker Compose project: "gascity"
       │
       └── Container: gascity
            ├── gc, bd                (pre-built binaries on PATH)
            ├── tmux                  (agent sessions)
            ├── dolt sql-server       (beads database, internal)
            ├── claude CLI            (agent runtime)
            │
            ├── /city/                (city workspace — persistent volume)
            │   ├── city.toml         (declarative city config)
            │   ├── pack.toml         (pack manifest)
            │   ├── .gc/              (city runtime state)
            │   ├── agents/
            │   ├── formulas/
            │   ├── orders/
            │   └── overlays/
            │
            ├── /city/rigs-host/      (bind-mounted ~/code from host)
            │
            ├── /city/.dolt-data/     (separate volume — VirtioFS-safe)
            │
            └── /home/agent/.claude   (persistent volume, keyring-backed)
```

### Why one container

The Gas City supervisor coordinates all agents in one process and uses
local IPC (filesystem, dolt, tmux) for inter-agent communication.
Splitting agents across containers would break that. The container
boundary isolates **Gas City from your host**, not agents from each other.

---

## Prerequisites

- Docker Desktop or compatible (tested on Docker Desktop for Mac).
- The gascity source repo cloned locally:
  ```bash
  cd ~/code && git clone https://github.com/gastownhall/gascity.git gascity-src
  ```
- (Optional) ~/.claude with a working Claude Code login on the host —
  the container will sync your credentials so you don't have to log in
  again inside the container.
- (Optional) `gh auth login` on the host — the container will sync the
  credentials so `git push` from agents works.

---

## Quick start

```bash
# 1. Build the image (one-time, ~5 min on first run for Go + deps)
cd ~/code/gascity-src
docker build -t gascity:latest \
    -f ~/code/learning-gastown/guides/containerized/gascity/Dockerfile .

# 2. Bring up the stack
cd ~/code/learning-gastown/guides/containerized/gascity
GIT_USER="Your Name" GIT_EMAIL="you@example.com" docker compose up -d

# 3. Verify
docker compose exec gascity gc version
docker compose exec gascity gc doctor

# 4. Add a rig from your host's ~/code
docker compose exec gascity bash -c \
    "cd /city/rigs-host/<your-repo> && gc rig add ."

# 5. Drive Gas City from inside the container
docker compose exec gascity bash
# inside:
gc cities
gc formula
gc bd ready
```

To stop everything:

```bash
docker compose down
# or wipe state too:
docker compose down -v
```

---

## What runs where

| Component | Where | Why |
|---|---|---|
| `gc` CLI | `/app/gascity/bin/gc` (on PATH) | Single static Go binary; built during image build. |
| `bd` (beads) | installed by upstream installer in image | Default `gc init` provider; needs dolt 1.86.1+. |
| `dolt` | installed by upstream installer | Backs `bd` storage; data on a Docker volume. |
| `gc supervisor run` | container CMD | Foreground equivalent of `gc start` (no launchd in container). |
| Claude Code | `claude` from base image | The actual coding-agent runtime. |
| GNOME Keyring | started in entrypoint | Lets `claude` persist OAuth credentials via libsecret. |

---

## Volumes & persistence

Same pattern as the gastown container:

| Volume | Path in container | Purpose |
|---|---|---|
| `city-workspace` | `/city` | The city scaffold + runtime state. Lose this and `gc init` re-runs. |
| `dolt-data` | `/city/.dolt-data` | Beads database files. Kept off the bind mount because VirtioFS fsync semantics can corrupt the dolt journal. |
| `claude-data` | `/home/agent/.claude` | Claude Code credentials, sessions, history. |
| `claude-state` / `claude-share` | `/home/agent/.local/state/claude` / `.local/share/claude` | Theme picker / lockfiles / version bookkeeping. Without these, the theme picker pops every restart. |
| (bind) | `/city/rigs-host` ← `${GCC_CODE_DIR:-~/code}` | Your code, mounted read-write. Agents add rigs out of subdirectories here. |
| (bind, ro) | `/home/agent/.claude-host` ← `~/.claude` | Read-only staging; entrypoint copies into the writable volume above. |
| (bind, ro) | `/home/agent/.config/gh-host` ← `~/.config/gh` | Same idea for `gh` CLI credentials. |

---

## Security posture

Identical to the Gas Town container:

- `cap_drop: [ALL]` plus only `CHOWN`, `SETUID`, `SETGID` for the keyring +
  process bookkeeping.
- `no-new-privileges:true` so a compromised process can't `sudo` its way
  out.
- `pids: 512`, `memory: 4G`, `cpus: 4` — caps fork bombs and runaway
  Claude sessions.
- Host SSH keys, AWS credentials, browser profiles, `~/.config` (other
  than gh) are **not** mounted. Agents physically cannot read them.
- Host `~/.claude` is mounted read-only at `/home/agent/.claude-host`;
  the entrypoint copies the few files needed into a writable volume so
  you keep your Max subscription / OAuth without giving agents write
  access to your host config.

If you want even tighter isolation, see the gastown guide's `SECURITY.md`
— the "Three Walls" reasoning applies verbatim.

---

## Knobs

| Env var | Default | Purpose |
|---|---|---|
| `GIT_USER` | `TestUser` | Configures git + dolt user.name (idempotent each start). |
| `GIT_EMAIL` | `test@example.com` | Same for user.email. |
| `GC_PROVIDER` | `claude-code` | Coding-agent runtime registered into the city. Other valid values: `codex`, `gemini`, `exec`. |
| `GCC_CODE_DIR` | `~/code` | Host directory bind-mounted at `/city/rigs-host`. |

---

## Troubleshooting

**`gc start` fails with "missing required dependencies: dolt"**
The container has dolt + flock pre-installed; this should not happen
inside the container. If it does, the dolt installer likely failed
during image build — re-run `docker build` and watch its output.

**`claude` keeps re-prompting for login**
The keyring volume (`claude-data`) is missing or fresh. If you've never
logged in on the host either, run `claude` once interactively *inside*
the container to authenticate.

**Dolt journal errors after `docker compose down`**
The `dolt-data` volume should always be on a Docker volume, never on a
macOS bind mount. The compose file already does this — don't change it.

**`gc rig add` says path not found**
Rigs must be added from inside the container. Use the bind-mounted path
under `/city/rigs-host`, not the host path.

---

## Files

```
gascity/
├── Dockerfile           # builds gascity:latest from upstream source
├── docker-compose.yml   # one-service stack with security + volumes
└── README.md            # you are here
```

This guide intentionally does not ship sidecars (VictoriaLogs, gateway).
Gas City's telemetry story is still maturing — start it bare, and add
sidecars later if you want them. The gastown guide's
`docker-compose.yml` is a good reference for the sidecar shape.
