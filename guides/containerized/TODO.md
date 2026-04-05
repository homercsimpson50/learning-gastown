# Containerized Gas Town — TODO

## AWS Bedrock credential support

**Priority:** High
**Context:** Work laptops cannot use personal Claude Pro/Max subscriptions. AWS Bedrock is the approved path for Claude access in corporate environments.

### Requirements

- Add Bedrock as a first-class auth option alongside OAuth (`/login`)
- Support env vars in `docker-compose.yml`:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
  - `AWS_SESSION_TOKEN` (for assumed roles)
  - `AWS_REGION` / `AWS_DEFAULT_REGION`
  - `CLAUDE_CODE_USE_BEDROCK=1` (or equivalent)
- Entrypoint should detect Bedrock env vars and skip keyring/OAuth setup
- Document in README under Claude Code Authentication section
- Pass Bedrock creds as env vars (no host filesystem mounting needed)
- Test that Claude Code works with Bedrock backend inside the container

### Notes

- Claude Code supports Bedrock via `CLAUDE_CODE_USE_BEDROCK=1` env var
- No `/login` needed when using Bedrock — credentials come from env vars or AWS config
- Bedrock creds are short-lived and auto-expire — low exfiltration risk (see SECURITY.md C1)
- The keyring/gnome-keyring setup becomes optional (only needed for OAuth flow)
- Gateway sidecar could potentially proxy Bedrock credentials too (like it does for GitHub/Jira)

---

## Agent observability TUI (`gt feed --agents`) — DONE

**Status:** Working. Pushed to fork, tested live with containerized GT.

Completed:
- ~~Push the feature branch~~ → on `homercsimpson50/gastown@feat/agent-observability-tui`
- ~~Test inside the containerized setup end-to-end~~ → works via `gtcfeed --agents`
- ~~LLM-summarized log lines~~ → AI summary panel via Ollama (`s` key)
- ~~Polish the TUI layout and key bindings~~ → rig column, rig filter, split-screen summary
- Upstream PR to `gastownhall/gastown` — pending (need repo write access)

### Remaining polish

- Fix Claude Code onboarding theme picker (appears after `gtc down`/`up` despite `hasCompletedOnboarding: true`)
- Capture user-typed prompts in feed (fix deployed to fork, needs image rebuild)
- Summary log persistence (JSONL file or SQLite)
- Pin column headers in feed view
