#!/usr/bin/env bash
#
# start-workspace.sh — open a local Gas Town workspace in iTerm2.
#
# Layout (matches the screenshot in the localhost guide):
#
#   ┌──────────────┬──────────────────────────────────┐
#   │              │  mayor attach (gt mayor attach)  │
#   │  gt start +  │                                  │
#   │  log tail    ├──────────────────────────────────┤
#   │  (gtf log -f)│                                  │
#   │              │  gtf -a  (agent observability)   │
#   │              │                                  │
#   └──────────────┴──────────────────────────────────┘
#
# Left pane:        boots the town with `gt start`, then tails the lifecycle log
#                   (spawn / wake / handoff / done) so you can see services come up.
# Top-right:        attaches the Mayor's tmux session (Ctrl-B D to detach).
# Bottom-right:     `gtf -a` agent observability feed (tool calls per agent).
#
# Usage:
#   ./start-workspace.sh           # plain agents feed
#   ./start-workspace.sh --ai      # agents feed with Ollama AI summary panel

set -euo pipefail

FEED_CMD="gtf -a"
if [[ "${1:-}" == "--ai" ]]; then
    FEED_CMD="gtf -a --ai"   # only works if your gt build supports --ai
fi

# Sanity: make sure the wrapper exists. (Installed by guides/localhost setup.)
if ! command -v gtf >/dev/null 2>&1; then
    echo "error: 'gtf' not found on PATH. Install it first:" >&2
    echo "  install -m 0755 $(dirname "$0")/gtf.sh ~/.local/bin/gtf" >&2
    echo "  install -m 0755 $(dirname "$0")/gt-env-install.sh ~/.local/bin/gt-env-install" >&2
    echo "  gt-env-install && exec \$SHELL -l" >&2
    exit 1
fi

osascript <<APPLESCRIPT
tell application "iTerm2"
    activate
    create window with default profile

    tell current tab of current window
        -- Step 1: split current pane left | right.
        --         left = "service" (gt start + log tail)
        --         right = "mayor"  (gt mayor attach)
        tell current session
            set name to "service"
            set rightPane to (split vertically with default profile)
        end tell

        -- Step 2: split the right pane top / bottom.
        --         top    = mayor (already current right pane after split)
        --         bottom = feed
        tell rightPane
            set name to "mayor"
            set feedPane to (split horizontally with default profile)
        end tell

        tell feedPane
            set name to "feed"
        end tell

        -- Step 3: send commands to each pane.
        -- Left pane (service): boot the town, then tail the lifecycle log.
        --   `gt start` is idempotent — safe to re-run.
        --   The trailing `gtf log -f` keeps the pane alive showing town events.
        tell current session
            write text "cd ~/gt && gt start && echo && echo '── town up; tailing gt log ─────────' && gtf log -f"
        end tell

        -- Top-right (mayor): attach to the Mayor's tmux session.
        --   Small sleep so `gt start` has time to spawn the Mayor first.
        tell rightPane
            write text "cd ~/gt && sleep 4 && gt mayor attach"
        end tell

        -- Bottom-right (feed): agent observability TUI.
        --   Small sleep so the Mayor has emitted at least one event.
        tell feedPane
            write text "cd ~/gt && sleep 6 && $FEED_CMD"
        end tell
    end tell

    -- Resize to ~90% of a 1440x900 screen, centered.
    set bounds of current window to {72, 45, 1368, 855}
end tell
APPLESCRIPT

echo "✓ workspace launched"
