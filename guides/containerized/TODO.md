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
- Consider mounting `~/.aws/credentials` read-only as an alternative to env vars
- Test that Claude Code works with Bedrock backend inside the container

### Notes

- Claude Code supports Bedrock via `CLAUDE_CODE_USE_BEDROCK=1` env var
- No `/login` needed when using Bedrock — credentials come from env vars or AWS config
- The keyring/gnome-keyring setup becomes optional (only needed for OAuth flow)
- Gateway sidecar could potentially proxy Bedrock credentials too (like it does for GitHub/Jira)

---

## Agent observability TUI (`gt feed --agents`)

**Priority:** High
**Context:** The agent feed TUI (`gt feed --agents`) shows real-time agent tool-call activity inside the container. Polecat rust built the initial version on branch `feat/agent-observability-tui` but it still needs work.

### Remaining work

- Push the feature branch (blocked on repo write access — see mail thread `hq-wisp-2ux`)
- Test inside the containerized setup end-to-end with VictoriaLogs
- LLM-summarized log lines — compress raw tool calls into human-readable one-liners
- Polish the TUI layout and key bindings
- Upstream PR to `gastownhall/gastown` once stable

### Notes

- Source: `homercsimpson50/gastown@feat/agent-observability-tui`
- Requires VictoriaLogs + `GT_OTEL_LOGS_URL` + `GT_LOG_AGENT_OUTPUT=true` (already in compose)
- The README documents usage under Observability > Agent Observability TUI
