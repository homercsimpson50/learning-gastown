#!/usr/bin/env bash
#
# Gas Town iTerm2 Workspace Launcher
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
        -- Start with one pane. Split it left | right.
        -- iTerm2: "split vertically" = side by side (left|right)
        -- iTerm2: "split horizontally" = top/bottom

        -- Step 1: Split into left (local mayor) | right
        tell current session
            set name to "local-mayor"
            set rightPane to (split vertically with default profile)
        end tell

        -- Step 2: Split right into top-right | bottom-right (feed)
        tell rightPane
            set feedPane to (split horizontally with default profile)
        end tell

        -- Step 3: Split top-right into gtc-mayor | shell
        tell rightPane
            set name to "gtc-mayor"
            set shellPane to (split vertically with default profile)
        end tell

        -- Name remaining panes
        tell shellPane
            set name to "code"
        end tell
        tell feedPane
            set name to "feed"
        end tell

        -- Send commands
        tell current session
            write text "cd ~/gt && echo '⚡ Starting local GT...' && gt daemon start 2>/dev/null; gt mayor attach"
        end tell
        tell rightPane
            write text "gtc attach"
        end tell
        tell shellPane
            write text "cd ~/code"
        end tell
        tell feedPane
            write text "cd ~/gt && $FEED_CMD"
        end tell
    end tell

    -- Resize window to ~90% of screen (1440x900 → 1296x810, centered)
    set bounds of current window to {72, 45, 1368, 855}

end tell
APPLESCRIPT

echo "Gas Town workspace launched"
