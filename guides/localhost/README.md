# Localhost Gas Town Setup

This guide is for running Gas Town **on your local machine** (not in containers — see
`../containerized/` for that). It covers:

1. The env vars `gt` needs so feed/log commands can read VictoriaLogs.
2. An installer that adds those vars to your shell rc (zsh / bash / ksh / fish).
3. A wrapper (`gtf`) for the most common feed/log invocations.
4. The minimal sequence to start Gas Town and watch agent activity.

---

## What you get

| File | Purpose |
| --- | --- |
| `gt-env-install.sh` | Idempotent installer that writes a marked block into your shell rc. |
| `gtf.sh` | Convenience wrapper around `gt feed` / `gt log` with env baked in. |
| `start-workspace.sh` | One command to open the 3-pane iTerm2 workspace (service, mayor, feed). |

All are safe to re-run. The installer keeps a timestamped backup of your rc the first
time it touches it.

---

## Crisp MVP — get it running with logs in ~5 commands

```sh
# 1) one-time install (run from a clone of this repo)
brew install victorialogs && brew services start victorialogs
install -m 0755 guides/localhost/gtf.sh            ~/.local/bin/gtf
install -m 0755 guides/localhost/gt-env-install.sh ~/.local/bin/gt-env-install
install -m 0755 guides/localhost/start-workspace.sh ~/.local/bin/gt-workspace
gt-env-install                # adds env vars to your shell rc

# 2) pick up the env in this shell (or open a new terminal)
exec $SHELL -l

# 3) launch the workspace
gt-workspace                  # opens iTerm2 with 3 panes (service / mayor / feed)
```

That's it. Inside the new iTerm2 window:

- **Left** — boots the town with `gt start` and tails `gt log -f`. Watch services
  spawn (deacon → mayor → witnesses).
- **Top right** — auto-attaches to the Mayor's tmux session after a 4s delay.
  Type to talk to the Mayor; `Ctrl-B D` detaches without killing it.
- **Bottom right** — `gtf -a` agent observability TUI. As the Mayor (or any
  polecat) makes tool calls, they show up here.

If the bottom-right pane stays empty after the Mayor has clearly done something:
the Mayor was started before `GT_OTEL_LOGS_URL` was exported. Fix:

```sh
gt mayor restart              # respawns Mayor with the env you have now
```

---

## Why is this needed?

`gt feed` and `gt log` query VictoriaLogs (the local logs DB) using these vars:

- `GT_TOWN_ROOT` — where your town lives (e.g. `~/gt`). Without it, `gt` walks up
  from the current directory.
- `GT_VLOGS_QUERY_URL` — VictoriaLogs LogsQL endpoint, default
  `http://localhost:9428/select/logsql/query`.
- `GT_OTEL_LOGS_URL` — OTLP logs endpoint that **spawned agents** use to push their
  tool-call traces into VictoriaLogs, default
  `http://localhost:9428/insert/opentelemetry/v1/logs`. Without it, agents start fine
  but their per-tool events never reach the feed.

Inside an active Mayor session those vars come from the harness; in a brand-new
terminal they don't. That's the whole problem this guide fixes.

---

## Prereqs

```sh
# VictoriaLogs (the logs DB the feed reads from)
brew install victorialogs
brew services start victorialogs   # auto-starts at login afterwards

# verify
curl -fsS http://localhost:9428/health && echo OK
```

Gas Town itself (the `gt` binary) is assumed already installed at `~/.local/bin/gt`.

---

## Install

```sh
# 1) drop these scripts into ~/.local/bin (or anywhere on PATH)
install -m 0755 gt-env-install.sh ~/.local/bin/gt-env-install
install -m 0755 gtf.sh            ~/.local/bin/gtf

# 2) install env vars into your shell rc (auto-detects $SHELL)
gt-env-install                    # default: ~/gt as town root
gt-env-install --dry-run          # preview only, no writes
gt-env-install --shell zsh        # force a shell
gt-env-install --uninstall        # remove the managed block

# 3) pick up the new vars in this shell
exec $SHELL -l                    # or open a new terminal
```

The installer detects the right rc file:

| Shell | RC file |
| --- | --- |
| zsh | `~/.zshrc` |
| bash | `~/.bash_profile` (macOS) or `~/.bashrc` |
| ksh / mksh | `~/.kshrc` |
| sh / dash | `~/.profile` |
| fish | `~/.config/fish/config.fish` |

It writes a block delimited by markers, so re-running just replaces it cleanly.

---

## Start Gas Town and attach to the Mayor

```sh
# 1) make sure VictoriaLogs is up
brew services start victorialogs

# 2) boot the town: Deacon (watchdog) + Mayor (coordinator)
gt start                          # Witnesses/Refineries start lazily
# or, eagerly start Witnesses+Refineries for every registered rig:
gt start --all

# 3) attach to the Mayor's tmux session
gt mayor attach                   # detach with C-b d (default tmux prefix)

# Useful checks
gt mayor status                   # is the Mayor running?
gt agents                         # list all live Gas Town agent sessions
```

When `gt start` (and downstream `gt mayor start`, polecat spawns, etc.) launch
Claude, they pass `GT_OTEL_LOGS_URL` through to the child as
`OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` — that's how the Mayor's tool calls become
events visible in `gt feed -a`. If that var isn't exported in the shell where you
ran `gt start`, the Mayor starts fine but **its events won't show up** in the feed.
That's the most common "feed is empty" cause; the installer above fixes it.

---

## Watch the feed

Use `gtf` (the wrapper):

```sh
gtf                       # full TUI: agents tree, convoys, event stream
gtf -a                    # agents view: tool-call observability (Read/Edit/Bash…)
gtf -p                    # problems view: stuck/GUPP-violation agents
gtf plain                 # plain text event stream, no TUI
gtf log -f                # tail spawn/wake/handoff/done events
gtf log --agent gastown/mayor       # mayor only
gtf log --agent gastown/polecats    # polecats only
gtf log --type spawn --since 1h     # filtered town-event log
```

Inside the TUI: `j`/`k` scroll, `tab` switches panels, `1`/`2`/`3` jump panels,
`a` toggles agents view, `p` toggles problems view, `/` filters, `q` quits.

---

## Verifying end-to-end

```sh
# 1) VictoriaLogs is alive
curl -fsS http://localhost:9428/health && echo OK

# 2) something has been written to it
gtf log -n 5

# 3) agents are reporting tool calls (after Mayor has done anything)
gtf -a
```

If `gtf -a` is empty even though the Mayor is running:

- Check the Mayor's spawning shell had `GT_OTEL_LOGS_URL` set
  (`gt mayor restart` after sourcing the rc fixes this).
- Check VictoriaLogs is reachable: `curl http://localhost:9428/health`.
- `gtf log -f` should still show *town* events (spawn/wake/handoff) even when
  per-tool OTLP events are missing — those come from `.events.jsonl`, not VLogs.
  If even those are empty, VictoriaLogs/town root config is wrong.

---

## Uninstall

```sh
gt-env-install --uninstall    # removes the managed block from your rc
rm ~/.local/bin/gtf ~/.local/bin/gt-env-install
brew services stop victorialogs   # optional
```
