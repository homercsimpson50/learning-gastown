#!/usr/bin/env bash
#
# Gas Town iTerm2 Workspace Launcher (AppleScript version)
#
# Layout:
#   ┌──────────┬──────────┬──────────┐
#   │          │ gtc      │ shell    │
#   │  local   │ mayor    │ ~/code   │
#   │  mayor   ├──────────┴──────────┤
#   │  (tall)  │ gtc feed --agents   │
#   │          │ (wide)              │
#   └──────────┴─────────────────────┘
#
# Usage:
#   ./gastown-workspace.sh          # Full workspace
#   ./gastown-workspace.sh --ai     # Include AI summary in feed
#
# Requires: iTerm2

set -euo pipefail

FEED_CMD="gtc feed --agents"
if [ "${1:-}" = "--ai" ]; then
    FEED_CMD="gtc feed --agents --ai"
fi

osascript <<APPLESCRIPT
tell application "iTerm2"
    activate

    create window with default profile

    tell current tab of current window

        -- Pane 1 (full window): Local Mayor
        tell current session
            set name to "local-mayor"
            write text "cd ~/gt && echo '⚡ Starting local GT...' && gt daemon start 2>/dev/null; gt mayor attach"

            -- Split right → right half
            set rightPane to (split horizontally with default profile)
        end tell

        -- Pane 2 (right half): will become top-center (gtc mayor)
        tell rightPane
            set name to "gtc-mayor"
            write text "gtc attach"

            -- Split right pane horizontally → top-right (shell)
            set topRight to (split horizontally with default profile)
        end tell

        -- Pane 3 (top-right): Shell
        tell topRight
            set name to "code"
            write text "cd ~/code"
        end tell

        -- Split pane 2 (gtc mayor) vertically down → bottom-right (feed)
        -- But we want bottom-right to span under both top-center and top-right
        -- So split topRight vertically instead (it will merge visually)
        tell rightPane
            set bottomRight to (split vertically with default profile)
        end tell

        -- Pane 4 (bottom-right wide): Agent Feed
        tell bottomRight
            set name to "feed"
            write text "$FEED_CMD"
        end tell

    end tell
end tell
APPLESCRIPT

echo "Gas Town workspace launched in iTerm2"
