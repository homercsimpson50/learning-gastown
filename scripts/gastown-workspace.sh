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
            write text "$FEED_CMD"
        end tell
    end tell

    -- Resize: make the window ~80% of screen
    tell current window
        set screenBounds to bounds of current window
        tell application "Finder"
            set screenSize to bounds of window of desktop
        end tell
    end tell
end tell

-- Resize window to 80% of screen using System Events
tell application "System Events"
    tell process "iTerm2"
        set frontWindow to front window
        set {screenW, screenH} to {1440, 900}
        try
            tell application "Finder"
                set screenSize to bounds of window of desktop
                set screenW to item 3 of screenSize
                set screenH to item 4 of screenSize
            end tell
        end try
        set targetW to (screenW * 0.8) as integer
        set targetH to (screenH * 0.8) as integer
        set targetX to ((screenW - targetW) / 2) as integer
        set targetY to ((screenH - targetH) / 2) as integer
        set position of frontWindow to {targetX, targetY}
        set size of frontWindow to {targetW, targetH}
    end tell
end tell
APPLESCRIPT

echo "Gas Town workspace launched"
