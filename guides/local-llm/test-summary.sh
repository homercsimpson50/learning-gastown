#!/usr/bin/env bash
#
# test-summary.sh — Test local LLM summarization of agent feed events
#
# Prerequisites:
#   brew install ollama
#   brew services start ollama
#   ollama pull qwen2.5:3b
#
# Usage:
#   ./test-summary.sh                    # Uses sample events
#   ./test-summary.sh --live [vlogs-url] # Pulls real events from VictoriaLogs

set -euo pipefail

MODEL="${OLLAMA_MODEL:-qwen2.5:3b}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
VLOGS_URL="${GT_VLOGS_QUERY_URL:-http://localhost:9428/select/logsql/query}"

# Sample agent events (used when --live is not set)
SAMPLE_EVENTS='
16:27:32 inception rust    Ran: go test ./...
16:27:28 inception rust    Committed: git add main.go main_test.go
16:27:26 inception rust    Wrote main_test.go (3 tests for /version endpoint)
16:27:21 inception rust    Wrote main.go (added GET /version handler)
16:27:14 hq        mayor   Slung hq-57r to monorepo rig
16:27:07 hq        mayor   Listed polecats for monorepo rig
16:27:05 hq        mayor   Read HANDOFF.md from learning-gastown
16:26:55 inception witness  Patrol: checked agent health, all nominal
'

fetch_live_events() {
    local url="$1"
    local events
    events=$(curl -sf "${url}?query=_msg:agent.event+AND+event_type:tool_use&limit=20" 2>/dev/null) || {
        echo "Error: Cannot reach VictoriaLogs at $url" >&2
        exit 1
    }

    # Extract timestamp, session, and content from JSONL
    echo "$events" | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        e = json.loads(line)
        ts = e.get('_time','')[:19].split('T')[1] if 'T' in e.get('_time','') else '??:??:??'
        session = e.get('session','unknown')
        content = e.get('content','')[:100]
        print(f'{ts} {session:20s} {content}')
    except: pass
" 2>/dev/null
}

echo "=== Local LLM Agent Summary Test ==="
echo "Model: $MODEL"
echo "Ollama: $OLLAMA_URL"
echo ""

# Check Ollama is running
if ! curl -sf "$OLLAMA_URL/api/tags" >/dev/null 2>&1; then
    echo "Error: Ollama not running. Start with: brew services start ollama"
    exit 1
fi

# Check model is available
if ! ollama list 2>/dev/null | grep -q "$MODEL"; then
    echo "Error: Model $MODEL not found. Pull with: ollama pull $MODEL"
    exit 1
fi

# Get events
if [ "${1:-}" = "--live" ]; then
    LIVE_URL="${2:-$VLOGS_URL}"
    echo "Fetching live events from $LIVE_URL..."
    EVENTS=$(fetch_live_events "$LIVE_URL")
    if [ -z "$EVENTS" ]; then
        echo "No events found. Using sample events instead."
        EVENTS="$SAMPLE_EVENTS"
    fi
else
    echo "Using sample events (pass --live for real VictoriaLogs events)"
    EVENTS="$SAMPLE_EVENTS"
fi

echo ""
echo "--- Events ---"
echo "$EVENTS"
echo ""
echo "--- Summarizing... ---"

# Call Ollama API (OpenAI-compatible)
PROMPT="You are an AI agent activity summarizer. Given these recent agent tool-call events from a software development system, write a 2-3 sentence summary of what is happening. Be concise and specific. Focus on what work is being done, by whom, and the current status.

Events:
$EVENTS

Summary:"

RESPONSE=$(curl -sf "$OLLAMA_URL/api/generate" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg model "$MODEL" --arg prompt "$PROMPT" '{model: $model, prompt: $prompt, stream: false}')" \
    2>/dev/null)

SUMMARY=$(echo "$RESPONSE" | jq -r '.response // "Error: no response"')
DURATION=$(echo "$RESPONSE" | jq -r '.total_duration // 0' | awk '{printf "%.1f", $1/1000000000}')
TOKENS=$(echo "$RESPONSE" | jq -r '.eval_count // 0')

echo ""
echo "$SUMMARY"
echo ""
echo "--- Stats ---"
echo "Time: ${DURATION}s | Tokens: $TOKENS | Model: $MODEL"
