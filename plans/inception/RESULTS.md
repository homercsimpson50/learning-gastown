# Inception Test Results

*In progress — 2026-04-04*

## Phase 0: Environment Safety — PASS

- Container `GT_OTEL_LOGS_URL` correctly points to `victoria-logs:9428` (sidecar)
- Host `GT_OTEL_LOGS_URL` points to `localhost:9428` (local brew VLogs)
- No env var cross-contamination
- Container VLogs mapped to host port 9429 to avoid conflict

## Phase 1: Build and Start — PASS

- Built `gastown:latest` from fork source (includes TUI + rig column + sort fix)
- All 3 containers running: gastown, gt-victoria-logs, gt-gateway
- GT workspace initialized, daemon running
- Telemetry flowing from container to container VLogs

## Phase 2: Tests — PASS (42/42)

All integration tests pass:
- Container health (3/3)
- GT core (5/5)
- Services (4/4)
- Beads system (3/3)
- Mayor (2/2)
- Inter-agent communication (2/2)
- VictoriaLogs observability (7/7)
- Gateway sidecar (5/5)
- Security controls (6/6) — includes new auth mount, SSH, host filesystem, env isolation tests
- Network isolation (5/5) — includes new SSH, /Users, and env var tests

## Phase 3: Simple Project (inception-test) — PASS

- Created `homercsimpson50/inception-test` on GitHub
- Seeded with README + go.mod
- Mounted into container as inception rig
- Containerized Claude Code (via API key in `--dangerously-skip-permissions -p` mode) built:
  - `main.go` — HTTP server with GET /health and GET /items
  - `main_test.go` — Tests using httptest
- `go test ./...` passes in container AND locally
- Pushed from container to GitHub — commit `85622f3`
- Local pull + verify: all clean

### Onboarding Issue Encountered

Claude Code's interactive onboarding wizard (theme selection, login method) blocked automated session startup. The workaround was using `claude -p` (print mode) with `--dangerously-skip-permissions` instead of GT's interactive session management. The existing OAuth credentials (synced from host `.claude`) were detected but the onboarding wizard still ran.

**Recommendation:** For containerized setups using API keys, either:
1. Pre-configure `~/.claude/settings.json` with `hasCompletedOnboarding: true` (if Claude Code respects it)
2. Use `claude -p` mode for automated work (reliable, bypasses onboarding)
3. Complete onboarding manually once, then let sessions resume

## Phase 4: Monorepo Test — IN PROGRESS

- Created `homercsimpson50/inception-monorepo` on GitHub
- Seeded with projects/01-api/, projects/02-cli/, shared/types.go
- Mounted into container as monorepo rig
- Claude Code building both projects...

## Phase 5: Security Verification — PASS

Tested from inside container:
- Cannot access host `~/.ssh` (No such file or directory)
- Cannot access host `/Users` (No such file or directory)
- GT_OTEL_LOGS_URL points to sidecar, not host localhost
- Capabilities minimal: CAP_CHOWN, CAP_SETGID, CAP_SETUID only
- no-new-privileges enabled
- PID limit: 512, Memory limit: 4GB
- Claude host settings mounted read-only at `.claude-host`
