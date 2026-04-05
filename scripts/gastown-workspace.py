#!/usr/bin/env python3
"""
Gas Town iTerm2 Workspace Launcher

Sets up a 2x2 split layout in iTerm2:

  ┌─────────────────────┬─────────────────────┐
  │  Local Mayor        │  Container Mayor    │
  │  cd ~/gt            │  gtc attach         │
  │  gt up; gt attach   │                     │
  ├─────────────────────┼─────────────────────┤
  │  Shell              │  Agent Feed         │
  │  cd ~/code          │  gtc feed           │
  │                     │  --agents --ai      │
  └─────────────────────┴─────────────────────┘

Usage:
  ./gastown-workspace.py          # Full workspace (all 4 panes)
  ./gastown-workspace.py --no-ai  # Skip Ollama/AI summary

Requires iTerm2 with Python API enabled:
  iTerm2 → Preferences → General → Magic → Enable Python API
"""

import iterm2
import sys
import asyncio

# Pane commands
LOCAL_MAYOR = 'cd ~/gt && echo "Starting local GT..." && gt daemon start 2>/dev/null; gt mayor attach'
CONTAINER_MAYOR = 'gtc attach'
CODE_SHELL = 'cd ~/code'
AGENT_FEED = 'gtc feed --agents'
AGENT_FEED_AI = 'gtc feed --agents --ai'


async def main(connection):
    app = await iterm2.async_get_app(connection)

    # Use AI flag
    use_ai = "--no-ai" not in sys.argv
    feed_cmd = AGENT_FEED_AI if use_ai else AGENT_FEED

    # Create a new window with the first pane (top-left: local mayor)
    window = await iterm2.Window.async_create(connection)
    top_left = window.current_tab.current_session

    # Set the window title
    await top_left.async_set_name("mayor - local gt (tmux)")

    # Split top-left horizontally → top-right (container mayor)
    top_right = await top_left.async_split_pane(vertical=True)
    await top_right.async_set_name("docker-compose")

    # Split top-left vertically → bottom-left (code shell)
    bottom_left = await top_left.async_split_pane(vertical=False)
    await bottom_left.async_set_name("code")

    # Split top-right vertically → bottom-right (agent feed)
    bottom_right = await top_right.async_split_pane(vertical=False)
    await bottom_right.async_set_name("GT Feed [AGENTS]")

    # Small delay to let panes initialize
    await asyncio.sleep(0.5)

    # Send commands to each pane
    await bottom_left.async_send_text(CODE_SHELL + '\n')
    await top_left.async_send_text(LOCAL_MAYOR + '\n')

    # Start container stack first, wait, then attach
    await top_right.async_send_text(CONTAINER_MAYOR + '\n')

    # Agent feed — give containers a moment to start
    await asyncio.sleep(1)
    await bottom_right.async_send_text(feed_cmd + '\n')


# Run via iTerm2 Python API
iterm2.run_until_complete(main)
