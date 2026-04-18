#!/usr/bin/env bash
# gtf — gt with the env Gas Town's log/feed commands need, baked in.
#
# Usage:
#   gtf                        → gt feed         (full TUI)
#   gtf -a                     → gt feed -a      (agents view: tool-call observability)
#   gtf -p                     → gt feed -p      (problems view)
#   gtf plain                  → gt feed --plain (text stream, no TUI)
#   gtf log [args...]          → gt log [args]   (e.g. gtf log -f, gtf log --agent gastown/mayor)
#   gtf raw <any gt args...>   → gt <args>       (passthrough with env set)

set -euo pipefail

export GT_TOWN_ROOT="${GT_TOWN_ROOT:-/Users/homer/gt}"
export GT_VLOGS_QUERY_URL="${GT_VLOGS_QUERY_URL:-http://localhost:9428/select/logsql/query}"
export GT_OTEL_LOGS_URL="${GT_OTEL_LOGS_URL:-http://localhost:9428/insert/opentelemetry/v1/logs}"

GT_BIN="${GT_BIN:-/Users/homer/.local/bin/gt}"

# Sanity check: VictoriaLogs reachable?
if ! curl -fsS -o /dev/null --max-time 1 "http://localhost:9428/health" 2>/dev/null; then
  echo "warning: VictoriaLogs not reachable at http://localhost:9428 — feed may be empty" >&2
fi

case "${1:-}" in
  ""|feed)        shift || true; exec "$GT_BIN" feed "$@" ;;
  -a|agents)      shift; exec "$GT_BIN" feed -a "$@" ;;
  -p|problems)    shift; exec "$GT_BIN" feed -p "$@" ;;
  plain)          shift; exec "$GT_BIN" feed --plain "$@" ;;
  log)            shift; exec "$GT_BIN" log "$@" ;;
  raw)            shift; exec "$GT_BIN" "$@" ;;
  -h|--help|help)
    sed -n '2,12p' "$0" | sed 's/^# *//'
    exit 0
    ;;
  *)
    # Unknown first arg → assume passthrough to gt feed
    exec "$GT_BIN" feed "$@"
    ;;
esac
