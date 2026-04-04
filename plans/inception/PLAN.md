# Inception: Local Mayor Builds Containerized Mayor's World

> "We need to go deeper." — Cobb

The local mayor (this session) orchestrates a fully containerized Gas Town,
gives it work, monitors it via the agent feed TUI, and verifies the output.
Like the movie: dreams within dreams, mayors within mayors.

---

## Phase 0: Environment Safety

**Problem:** `~/.zshrc` sets `GT_OTEL_LOGS_URL=http://localhost:9428/...` and
`GT_LOG_AGENT_OUTPUT=true`. If `docker compose exec` inherits these, the
containerized GT will try to reach the host's VLogs instead of its own sidecar.

**Fix:**
- Verify `docker-compose.yml` explicitly sets these env vars for the container
  (pointing to `victoria-logs:9428` — the sidecar)
- Use `docker compose exec -e GT_OTEL_LOGS_URL=... -e GT_LOG_AGENT_OUTPUT=...`
  or confirm Docker Compose env vars take precedence over inherited host env
- Test: run `docker compose exec gastown printenv GT_OTEL_LOGS_URL` and confirm
  it shows the container URL, not the host URL

---

## Phase 1: Build and Start Containerized Stack

1. Build the gastown Docker image from the fork source (includes TUI changes)
   ```
   cd ~/gt/gastown/polecats/rust/gastown
   docker build -t gastown:latest -f ~/learning-gastown/guides/containerized/Dockerfile .
   ```

2. Start the compose stack
   ```
   cd ~/learning-gastown/guides/containerized
   GIT_USER="Homer Simpson" GIT_EMAIL="homer.c.simpson50@gmail.com" docker compose up -d
   ```

3. Verify all three containers are running:
   - gastown (GT + agents)
   - gt-victoria-logs (telemetry)
   - gt-gateway (API proxy)

4. Verify VictoriaLogs sidecar is healthy from inside the container

---

## Phase 2: Run and Fix Tests

1. Run the existing integration tests:
   ```
   cd ~/learning-gastown/guides/containerized
   bash test-container.sh
   ```

2. Fix any failures (expected — the test suite was written before today's changes)

3. Add security-focused tests:
   - Verify container cannot read `~/.ssh/`, `~/.aws/`
   - Verify `GT_OTEL_LOGS_URL` inside container points to sidecar, not host
   - Verify outbound network basics (can reach GitHub, gateway reachable)
   - Verify resource limits are enforced (pids, memory, CPU)

4. All tests must pass before proceeding

---

## Phase 3: Create Test Repo — Simple Project

1. Create `homercsimpson50/inception-test` on GitHub
   ```
   gh repo create homercsimpson50/inception-test --public --description "Inception test: containerized GT builds this" --clone
   ```

2. Seed it with a minimal README and go.mod (or package.json — keep it simple)

3. Mount it into the container as a rig:
   ```yaml
   volumes:
     - ~/inception-test:/gt/rigs/inception/repo
   ```

4. Inside the container:
   ```
   gt rig add inception /gt/rigs/inception/repo --adopt
   ```

---

## Phase 4: Containerized Mayor Works on Simple Project

1. Auth: Pass ANTHROPIC_API_KEY to container (test-only; production uses OAuth)

2. Start the containerized mayor:
   ```
   docker compose exec gastown gt mayor start
   ```

3. Give it a task via bead:
   ```
   docker compose exec gastown bd create "Build a simple Go HTTP server that responds to GET /health with {\"status\":\"ok\"}" --label inception
   docker compose exec gastown gt sling <bead-id> inception
   ```

4. Monitor from local:
   ```
   # Watch the agent feed from the local TUI
   gt feed --agents
   # Or query VLogs directly for container events
   curl 'http://localhost:9428/select/logsql/query?query=*&limit=50'
   ```

5. Wait for completion, verify:
   - Polecat picks up the bead
   - Code is written to the mounted repo
   - Commit is made
   - Push succeeds (or at least commit exists locally)

6. Local verification:
   ```
   cd ~/inception-test
   git log --oneline -5
   go build ./...
   go test ./...
   ```

---

## Phase 5: Security Verification

1. From inside the container, verify isolation:
   ```
   docker compose exec gastown ls /home/agent/.ssh 2>&1  # should fail
   docker compose exec gastown cat /etc/shadow 2>&1       # should fail
   docker compose exec gastown ls /host-home 2>&1         # should not exist
   ```

2. Verify the containerized mayor cannot see the local mayor's workspace:
   ```
   docker compose exec gastown ls /Users 2>&1  # should fail
   ```

3. Verify resource limits:
   ```
   docker compose exec gastown cat /proc/self/cgroup  # check limits applied
   ```

---

## Phase 6: Monorepo Test

1. Create `homercsimpson50/inception-monorepo` on GitHub:
   ```
   gh repo create homercsimpson50/inception-monorepo --public --description "Monorepo inception test"
   ```

2. Seed with structure:
   ```
   inception-monorepo/
   ├── go.mod
   ├── projects/
   │   ├── 01-api/       # REST API service
   │   │   └── README.md
   │   └── 02-cli/       # CLI tool that calls the API
   │       └── README.md
   └── shared/
       └── types.go      # Shared types
   ```

3. Mount into container and add as rig:
   ```yaml
   volumes:
     - ~/inception-monorepo:/gt/rigs/monorepo/repo
   ```

4. Inside container, add the monorepo rig:
   ```
   gt rig add monorepo /gt/rigs/monorepo/repo --adopt
   ```

5. Create two beads and sling both:
   - Bead 1: "Build a REST API in projects/01-api/ with GET /items endpoint returning sample JSON"
   - Bead 2: "Build a CLI tool in projects/02-cli/ that fetches from the API and prints items"

6. Sling both to monorepo rig — polecats should work in parallel

7. Monitor via `gt feed --agents`, watch both polecats working simultaneously

8. Local verification:
   ```
   cd ~/inception-monorepo
   git log --oneline -10
   cd projects/01-api && go build ./...
   cd ../02-cli && go build ./...
   ```

---

## Phase 7: Documentation and Results

1. Write results to `plans/inception/RESULTS.md`:
   - What worked
   - What failed and how it was fixed
   - Screenshots/logs of the agent feed showing containerized agents
   - Security test results
   - Performance observations

2. Update CHRONICLE.md with inception test entry

3. Update containerized README if any setup steps changed

---

## Key Decisions (Pre-made)

- **Auth:** Use ANTHROPIC_API_KEY for container test (not OAuth — can't do browser flow from automation). Document as test-only.
- **Repos:** Public repos on homercsimpson50 — low risk, easy cleanup.
- **Language:** Go for test projects — gastown is Go, keeps it consistent.
- **Monitoring:** Use local `gt feed --agents` querying the container's VLogs (port-mapped to host).
- **Push:** Container agents push via `gh auth` with the existing CLI token, not the gateway.
- **Cleanup:** Leave repos and containers running for user to inspect. Don't delete anything.

---

## Risk Mitigations

| Risk | Mitigation |
|------|------------|
| Container build fails (missing deps) | Fall back to upstream Dockerfile, skip TUI changes |
| Container can't auth to Claude | Use API key as env var |
| .zshrc vars leak into container | Explicit env override in compose; verify with printenv |
| Monorepo polecats conflict | Separate worktrees per polecat (GT default behavior) |
| Tests fail on security checks | Fix the actual security issue, don't weaken the test |
| VLogs port conflict (local vs container) | Container VLogs on different host port (9429) |
