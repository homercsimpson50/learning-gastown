# Inception Handoff: Local Mayor → Containerized Mayor

## Context

The local mayor built and tested the containerized Gas Town stack. The
infrastructure works (42/42 tests pass, code builds inside containers, pushes
to GitHub work). But the actual "inception" — a containerized mayor
autonomously orchestrating polecats — was blocked by Claude Code's interactive
onboarding wizard in tmux sessions.

This document tells the containerized mayor what to finish.

---

## What's Already Done (don't redo)

### Infrastructure
- `gastown:latest` Docker image built from fork source (includes TUI + rig column)
- 3 containers running: gastown, gt-victoria-logs (:9429 on host), gt-gateway
- 42/42 integration tests pass (`bash test-container.sh`)
- GT daemon running, both rigs registered

### Repos (already created and seeded on GitHub)
- `homercsimpson50/inception-test` — has working Go HTTP server (built by `claude -p`)
- `homercsimpson50/inception-monorepo` — has working API + CLI (built by `claude -p`)

### Rigs (already added inside the container)
- `inception` rig → mounted from `~/code/inception-test`
- `monorepo` rig → mounted from `~/code/inception-monorepo`

### Auth
- `gh` CLI is authenticated inside the container
- `gh auth setup-git` has been run (git push works)
- `ANTHROPIC_API_KEY` is in the container environment

---

## What the Containerized Mayor Needs to Do

### Task 1: Prove Autonomous Polecat Execution

The local mayor had to use `claude -p` as a workaround. You need to prove that
GT's normal workflow works: mayor creates bead → slings to rig → polecat picks
it up → polecat writes code → polecat commits → polecat completes the bead.

**Steps:**
1. Create a new bead for the inception rig:
   ```
   bd create "Add a GET /version endpoint to main.go that returns {\"version\":\"1.0.0\",\"built_by\":\"containerized-gt\"}. Add a test for it. Run go test." --repo inception
   ```
2. Sling it:
   ```
   gt sling <bead-id> inception
   ```
3. The polecat should auto-start (daemon is running), pick up the work, and complete it
4. If the polecat gets stuck at Claude Code onboarding:
   - Try completing the onboarding manually (select Dark mode → Enter, then select API key or subscription login)
   - Or restart the session after completing onboarding once
5. Once the polecat completes, push the changes:
   ```
   # From the polecat's worktree or mayor's clone
   git push origin HEAD:main
   ```

### Task 2: Prove Parallel Polecats on Monorepo

Two polecats should work on the monorepo simultaneously on different projects.

**Steps:**
1. Create two beads:
   ```
   bd create "Add GET /items/:id endpoint to projects/01-api/main.go that returns a single item by ID, or 404 if not found. Add tests." --repo monorepo
   bd create "Add a --format flag to projects/02-cli/main.go supporting 'table' (default) and 'json' output formats. Add tests." --repo monorepo
   ```
2. Sling both to monorepo:
   ```
   gt sling <bead-1-id> monorepo
   gt sling <bead-2-id> monorepo
   ```
3. Two polecats should spawn and work in parallel
4. Monitor with `gt feed --agents` (press `a` to toggle agents view, `r` to filter by rig)
5. When both complete, push:
   ```
   git push origin HEAD:main
   ```

### Task 3: Verify from Agent Feed

While polecats are working, run `gt feed --agents` and confirm:
- Events appear from both polecats (tool calls: Read, Write, Edit, Bash)
- Rig column shows "monorepo" for both
- The `r` key filters between rigs

### Task 4: Run Tests to Verify Code Quality

After polecats complete, verify the code is correct:
```
cd /gt/inception/polecats/*/inception && go test ./...
cd /gt/monorepo/mayor/rig && go test ./...
```

---

## Write Results Here

Write your results to:
```
/gt/rigs/learning/repo/plans/inception/CONTAINER-MAYOR-RESULTS.md
```

Include:
- Which tasks succeeded/failed
- Whether polecats started autonomously or needed manual intervention
- Screenshot or copy-paste of `gt feed --agents` output showing polecat activity
- Any errors encountered and how you resolved them
- `gt status` output showing the final state of rigs and agents

---

## How Homer Starts the Containerized Mayor

```bash
# Rebuild image first (entrypoint now syncs OAuth credentials from host)
cd ~/gt/gastown/polecats/rust/gastown
docker build -t gastown:latest -f ~/code/learning-gastown/guides/containerized/Dockerfile .

# Start with all repos mounted (gtc handles the override file)
gtc up --repo ~/code/inception-test --repo ~/code/inception-monorepo --repo ~/code/learning-gastown

# Attach to the containerized mayor
gtc attach

# Once inside, tell the mayor:
# "Read /gt/rigs/learning/repo/plans/inception/HANDOFF.md and execute all tasks.
#  Write results to /gt/rigs/learning/repo/plans/inception/CONTAINER-MAYOR-RESULTS.md"

# Ctrl-B D to detach
```

The updated entrypoint syncs `.credentials.json` from the host, so the
container inherits your Google OAuth / Max subscription. No browser login
or onboarding should be needed.

If onboarding still appears (first time only, persists in volume after):
1. Select Dark mode → Enter
2. Select "Claude account with subscription" → Enter

---

## Success Criteria

The inception test is complete when:
- [ ] At least one polecat autonomously completed a bead (no `claude -p` workaround)
- [ ] Two polecats worked on monorepo simultaneously
- [ ] `gt feed --agents` showed real-time tool calls from containerized agents
- [ ] All code pushed to GitHub repos
- [ ] All `go test` pass
- [ ] CONTAINER-MAYOR-RESULTS.md exists with findings
