#!/usr/bin/env python3
"""
Gas Town iTerm2 Workspace Launcher

Layout:
  ┌──────────┬──────────┬──────────┐
  │          │ gtc      │ shell    │
  │  local   │ mayor    │ ~/code   │
  │  mayor   ├──────────┴──────────┤
  │  (tall)  │ gtc feed --agents   │
  │          │ (wide)              │
  └──────────┴─────────────────────┘

Usage:
  ./gastown-workspace.py          # Full workspace
  ./gastown-workspace.py --no-ai  # Skip Ollama/AI summary

Requires iTerm2 with Python API enabled:
  iTerm2 → Preferences → General → Magic → Enable Python API
"""

import iterm2
import sys
import asyncio

LOCAL_MAYOR = 'cd ~/gt && echo "Starting local GT..." && gt daemon start 2>/dev/null; gt mayor attach'
CONTAINER_MAYOR = 'gtc attach'
CODE_SHELL = 'cd ~/code'
AGENT_FEED = 'gtc feed --agents'
AGENT_FEED_AI = 'gtc feed --agents --ai'


async def main(connection):
    app = await iterm2.async_get_app(connection)

    use_ai = "--no-ai" not in sys.argv
    feed_cmd = AGENT_FEED_AI if use_ai else AGENT_FEED

    # Create window — starts as single pane (local mayor)
    window = await iterm2.Window.async_create(connection)
    left = window.current_tab.current_session
    await left.async_set_name("local-mayor")

    # Split left vertically → right half
    right_top = await left.async_split_pane(vertical=True)
    await right_top.async_set_name("gtc-mayor")

    # Split right-top vertically → top-right (shell)
    top_right = await right_top.async_split_pane(vertical=True)
    await top_right.async_set_name("code")

    # Split right-top horizontally down → bottom-right (feed, wide)
    bottom_right = await right_top.async_split_pane(vertical=False)
    await bottom_right.async_set_name("feed")

    await asyncio.sleep(0.5)

    # Send commands
    await left.async_send_text(LOCAL_MAYOR + '\n')
    await right_top.async_send_text(CONTAINER_MAYOR + '\n')
    await top_right.async_send_text(CODE_SHELL + '\n')
    await asyncio.sleep(1)
    await bottom_right.async_send_text(feed_cmd + '\n')


iterm2.run_until_complete(main)
