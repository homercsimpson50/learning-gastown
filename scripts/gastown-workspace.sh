#!/usr/bin/env bash
#
# Gas Town iTerm2 Workspace Launcher (AppleScript version)
#
# Sets up a 2x2 split layout:
#   Top-left:     Local Mayor (cd ~/gt && gt attach)
#   Top-right:    Container Mayor (gtc attach)
#   Bottom-left:  Shell (cd ~/code)
#   Bottom-right: Agent Feed (gtc feed --agents)
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

    -- Create a new window
    create window with default profile

    tell current session of current tab of current window

        -- Top-left: Local Mayor
        set name to "local-mayor"
        write text "cd ~/gt && echo '⚡ Starting local GT...' && gt daemon start 2>/dev/null; gt mayor attach"

        -- Split right → Top-right: Container Mayor
        tell (split horizontally with default profile)
            set name to "gtc-mayor"
            write text "gtc attach"
        end tell

    end tell

    -- Now we have two panes side by side. Split each vertically.
    tell current tab of current window

        -- Split top-left down → Bottom-left: Code shell
        tell session 1
            tell (split vertically with default profile)
                set name to "code"
                write text "cd ~/code"
            end tell
        end tell

        -- Split top-right down → Bottom-right: Agent Feed
        tell session 2
            tell (split vertically with default profile)
                set name to "feed"
                write text "$FEED_CMD"
            end tell
        end tell

    end tell
end tell
APPLESCRIPT

echo "Gas Town workspace launched in iTerm2"
