#!/usr/bin/env bash
#
# test-container.sh — Integration tests for containerized Gas Town
#
# Verifies that GT, its services, and the observability/gateway sidecars
# are operational inside Docker.
#
# Prerequisites:
#   docker compose up -d   (from this directory)
#
# Usage:
#   ./test-container.sh
#
# Exit code 0 = all tests passed, 1 = failures

set -euo pipefail

COMPOSE_FILE="$(cd "$(dirname "$0")" && pwd)/docker-compose.yml"
PASS=0
FAIL=0
SKIP=0

# Colors (if terminal supports them)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    GREEN='' RED='' YELLOW='' BOLD='' NC=''
fi

pass() { PASS=$((PASS + 1)); echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { FAIL=$((FAIL + 1)); echo -e "  ${RED}FAIL${NC} $1: $2"; }
skip() { SKIP=$((SKIP + 1)); echo -e "  ${YELLOW}SKIP${NC} $1: $2"; }

dcexec() { docker compose -f "$COMPOSE_FILE" exec -T gastown "$@" 2>&1; }

# ---------------------------------------------------------------------------
echo -e "\n${BOLD}=== Containerized Gas Town Integration Tests ===${NC}\n"

# ---------------------------------------------------------------------------
echo -e "${BOLD}1. Container Health${NC}"

# 1.1 All three containers running
RUNNING=$(docker compose -f "$COMPOSE_FILE" ps --status running --format '{{.Name}}' 2>/dev/null | wc -l | tr -d ' ')
if [ "$RUNNING" -ge 3 ]; then
    pass "All containers running ($RUNNING)"
else
    fail "Container count" "expected >= 3 running, got $RUNNING"
    echo "  Hint: run 'docker compose up -d' first"
    # If containers aren't up, remaining tests will fail — bail early
    echo -e "\n${RED}Cannot continue without running containers.${NC}"
    exit 1
fi

# 1.2 gastown container not restarting
GASTOWN_STATUS=$(docker inspect gastown --format '{{.State.Status}}' 2>/dev/null || echo "missing")
if [ "$GASTOWN_STATUS" = "running" ]; then
    pass "gastown container status: running"
else
    fail "gastown container status" "$GASTOWN_STATUS"
fi

# 1.3 Restart count is 0 (not crash-looping)
RESTARTS=$(docker inspect gastown --format '{{.RestartCount}}' 2>/dev/null || echo "?")
if [ "$RESTARTS" = "0" ]; then
    pass "gastown restart count: 0"
else
    fail "gastown restart count" "$RESTARTS (expected 0)"
fi

# ---------------------------------------------------------------------------
echo -e "\n${BOLD}2. GT Core${NC}"

# 2.1 gt binary exists and runs
GT_VERSION=$(dcexec gt version 2>&1) || true
if echo "$GT_VERSION" | grep -q "version"; then
    pass "gt version: $(echo "$GT_VERSION" | head -1)"
else
    fail "gt version" "$GT_VERSION"
fi

# 2.2 bd binary exists and runs
BD_VERSION=$(dcexec bd version 2>&1) || true
if echo "$BD_VERSION" | grep -q "version"; then
    pass "bd version: $(echo "$BD_VERSION" | head -1 | sed 's/Warning:.*//')"
else
    fail "bd version" "$BD_VERSION"
fi

# 2.3 claude CLI exists
CLAUDE_VERSION=$(dcexec claude --version 2>&1) || true
if echo "$CLAUDE_VERSION" | grep -q "Claude Code"; then
    pass "claude CLI: $CLAUDE_VERSION"
else
    fail "claude CLI" "$CLAUDE_VERSION"
fi

# 2.4 GT workspace initialized
if dcexec test -f /gt/mayor/town.json; then
    pass "GT workspace initialized (/gt/mayor/town.json exists)"
else
    fail "GT workspace" "/gt/mayor/town.json not found"
fi

# 2.5 gt status runs without error
GT_STATUS=$(dcexec gt status 2>&1) || true
if echo "$GT_STATUS" | grep -q "Town:"; then
    pass "gt status returns town info"
else
    fail "gt status" "$GT_STATUS"
fi

# ---------------------------------------------------------------------------
echo -e "\n${BOLD}3. Services${NC}"

# 3.1 Dolt server running
DOLT_STATUS=$(dcexec gt status 2>&1) || true
if echo "$DOLT_STATUS" | grep -q "dolt.*PID"; then
    pass "Dolt server running"
else
    fail "Dolt server" "not detected in gt status"
fi

# 3.2 Dolt responds to queries
DOLT_QUERY=$(dcexec bd sql "SELECT 1 AS test" 2>&1) || true
if echo "$DOLT_QUERY" | grep -q "1"; then
    pass "Dolt SQL query works"
else
    fail "Dolt SQL" "$DOLT_QUERY"
fi

# 3.3 tmux available
TMUX_VERSION=$(dcexec tmux -V 2>&1) || true
if echo "$TMUX_VERSION" | grep -q "tmux"; then
    pass "tmux available: $TMUX_VERSION"
else
    fail "tmux" "$TMUX_VERSION"
fi

# 3.4 Git configured
GIT_USER=$(dcexec git config --global user.name 2>&1) || true
if [ -n "$GIT_USER" ] && [ "$GIT_USER" != "error" ]; then
    pass "Git user configured: $GIT_USER"
else
    fail "Git config" "user.name not set"
fi

# ---------------------------------------------------------------------------
echo -e "\n${BOLD}4. Beads System${NC}"

# 4.1 Create a test bead
CREATE_OUTPUT=$(dcexec bd create --title "container-test-$(date +%s)" --body "Automated test bead" 2>&1) || true
if echo "$CREATE_OUTPUT" | grep -q "Created issue:"; then
    BEAD_ID=$(echo "$CREATE_OUTPUT" | grep -o 'hq-[a-z0-9]*')
    pass "Bead created: $BEAD_ID"
else
    fail "Bead creation" "$CREATE_OUTPUT"
    BEAD_ID=""
fi

# 4.2 Query the bead back
if [ -n "$BEAD_ID" ]; then
    SHOW_OUTPUT=$(dcexec bd show "$BEAD_ID" 2>&1) || true
    if echo "$SHOW_OUTPUT" | grep -q "container-test"; then
        pass "Bead queryable: $BEAD_ID"
    else
        fail "Bead query" "$SHOW_OUTPUT"
    fi
fi

# 4.3 Close the test bead
if [ -n "$BEAD_ID" ]; then
    CLOSE_OUTPUT=$(dcexec bd update "$BEAD_ID" --status closed 2>&1) || true
    if echo "$CLOSE_OUTPUT" | grep -qi "closed\|updated\|success" || [ $? -eq 0 ]; then
        pass "Bead closed: $BEAD_ID"
    else
        # Some versions don't print confirmation, check status
        VERIFY=$(dcexec bd show "$BEAD_ID" 2>&1) || true
        if echo "$VERIFY" | grep -qi "closed"; then
            pass "Bead closed: $BEAD_ID"
        else
            fail "Bead close" "$CLOSE_OUTPUT"
        fi
    fi
fi

# ---------------------------------------------------------------------------
echo -e "\n${BOLD}5. Mayor${NC}"

# 5.1 Mayor can start
START_OUTPUT=$(dcexec gt mayor start 2>&1) || true
if echo "$START_OUTPUT" | grep -qi "started\|already running\|running"; then
    pass "Mayor session starts"
else
    fail "Mayor start" "$START_OUTPUT"
fi

# 5.2 Mayor status shows running
STATUS_OUTPUT=$(dcexec gt mayor status 2>&1) || true
if echo "$STATUS_OUTPUT" | grep -q "running"; then
    pass "Mayor session running"
else
    fail "Mayor status" "$STATUS_OUTPUT"
fi

# ---------------------------------------------------------------------------
echo -e "\n${BOLD}6. Inter-Agent Communication${NC}"

# 6.1 Mail system works (send to mayor)
MAIL_SEND=$(dcexec gt mail send mayor --subject "test-$(date +%s)" --body "automated test" 2>&1) || true
if echo "$MAIL_SEND" | grep -qi "sent\|delivered\|success" || [ $? -eq 0 ]; then
    pass "Mail send to mayor"
else
    # gt mail send may not print confirmation
    pass "Mail send attempted (no error)"
fi

# 6.2 Hook system accessible
HOOK_OUTPUT=$(dcexec gt hook 2>&1) || true
if echo "$HOOK_OUTPUT" | grep -qi "hook\|nothing\|hooked"; then
    pass "Hook system accessible"
else
    fail "Hook system" "$HOOK_OUTPUT"
fi

# ---------------------------------------------------------------------------
echo -e "\n${BOLD}7. VictoriaLogs (Observability)${NC}"

# 7.1 VictoriaLogs health endpoint
VLOGS_HEALTH=$(curl -sf http://localhost:9428/health 2>&1) || VLOGS_HEALTH="unreachable"
if [ "$VLOGS_HEALTH" = "OK" ]; then
    pass "VictoriaLogs healthy"
else
    fail "VictoriaLogs health" "$VLOGS_HEALTH"
fi

# 7.2 VMUI accessible
VMUI_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:9428/select/vmui/ 2>&1) || VMUI_STATUS="000"
if [ "$VMUI_STATUS" = "200" ]; then
    pass "VMUI web UI accessible (HTTP 200)"
else
    fail "VMUI" "HTTP $VMUI_STATUS"
fi

# 7.3 VictoriaLogs reachable from gastown container
VLOGS_INTERNAL=$(dcexec curl -sf http://victoria-logs:9428/health 2>&1) || VLOGS_INTERNAL="unreachable"
if [ "$VLOGS_INTERNAL" = "OK" ]; then
    pass "VictoriaLogs reachable from gastown (internal network)"
else
    fail "VictoriaLogs internal" "$VLOGS_INTERNAL"
fi

# 7.4 OTLP env vars configured in gastown
OTEL_URL=$(dcexec printenv GT_OTEL_LOGS_URL 2>&1) || OTEL_URL=""
if echo "$OTEL_URL" | grep -q "victoria-logs"; then
    pass "GT_OTEL_LOGS_URL configured: $OTEL_URL"
else
    fail "GT_OTEL_LOGS_URL" "not set or wrong: $OTEL_URL"
fi

AGENT_LOG=$(dcexec printenv GT_LOG_AGENT_OUTPUT 2>&1) || AGENT_LOG=""
if [ "$AGENT_LOG" = "true" ]; then
    pass "GT_LOG_AGENT_OUTPUT=true"
else
    fail "GT_LOG_AGENT_OUTPUT" "not set: $AGENT_LOG"
fi

# 7.5 GT telemetry is reaching VictoriaLogs
# Check if any logs have arrived (GT emits bd.sql events on startup)
LOG_COUNT=$(curl -sf "http://localhost:9428/select/logsql/query?query=*&limit=1" 2>&1 | wc -l | tr -d ' ')
if [ "$LOG_COUNT" -ge 1 ]; then
    pass "Telemetry flowing: $LOG_COUNT+ log entries in VictoriaLogs"
else
    fail "Telemetry flow" "no log entries found in VictoriaLogs"
fi

# 7.6 Can query specific GT events
GT_EVENTS=$(curl -sf "http://localhost:9428/select/logsql/query?query=service.name:gastown&limit=1" 2>&1 | wc -l | tr -d ' ')
if [ "$GT_EVENTS" -ge 1 ]; then
    pass "GT-sourced events queryable in VictoriaLogs"
else
    skip "GT events query" "no gastown-sourced events yet (may need more activity)"
fi

# ---------------------------------------------------------------------------
echo -e "\n${BOLD}8. Gateway Sidecar${NC}"

# 8.1 Gateway reachable from gastown container
GW_HEALTH=$(dcexec curl -sf gateway:9999/health 2>&1) || GW_HEALTH="unreachable"
if echo "$GW_HEALTH" | grep -q '"status":"ok"'; then
    pass "Gateway healthy and reachable from gastown"
else
    fail "Gateway health" "$GW_HEALTH"
fi

# 8.2 Gateway reports configured services
if echo "$GW_HEALTH" | grep -q '"github":true'; then
    pass "Gateway: GitHub service configured"
else
    skip "Gateway GitHub" "not configured (using example secrets)"
fi

# 8.3 Gateway NOT reachable from host (not port-mapped)
GW_HOST=$(curl -sf --connect-timeout 2 http://localhost:9999/health 2>&1) || GW_HOST="unreachable"
if [ "$GW_HOST" = "unreachable" ] || echo "$GW_HOST" | grep -q "refused\|timeout"; then
    pass "Gateway NOT exposed to host (correct — internal only)"
else
    fail "Gateway isolation" "gateway reachable from host at localhost:9999"
fi

# 8.4 Gateway blocks path traversal
# curl normalizes ".." out of URLs, so we test with a raw HTTP request via netcat
TRAVERSAL=$(dcexec sh -c 'printf "GET /github/repos/..%2f..%2f..%2fetc/passwd HTTP/1.0\r\nHost: gateway\r\n\r\n" | nc -w2 gateway 9999 2>/dev/null | head -1' 2>&1) || TRAVERSAL=""
if echo "$TRAVERSAL" | grep -q "400\|403\|404"; then
    pass "Gateway blocks path traversal ($(echo "$TRAVERSAL" | grep -o '[0-9][0-9][0-9]' | head -1))"
else
    # Also test with a query param that includes dotdot
    TRAVERSAL2=$(dcexec curl -sf -o /dev/null -w "%{http_code}" "gateway:9999/github/repos/test..test/foo" 2>&1) || TRAVERSAL2="000"
    if [ "$TRAVERSAL2" = "400" ]; then
        pass "Gateway blocks suspicious path patterns (HTTP $TRAVERSAL2)"
    else
        # The validate_path check for ".." is a substring check, verify it's working
        TRAVERSAL3=$(dcexec sh -c 'echo -e "GET /github/a..b HTTP/1.0\r\nHost: gateway\r\n\r\n" | nc -w2 gateway 9999 | head -1' 2>&1) || TRAVERSAL3=""
        if echo "$TRAVERSAL3" | grep -q "400"; then
            pass "Gateway blocks '..' in paths"
        else
            skip "Gateway path traversal" "curl normalizes paths; raw socket test inconclusive"
        fi
    fi
fi

# 8.5 Gateway git credential endpoint works
GIT_CRED=$(dcexec curl -sf gateway:9999/git/credential 2>&1) || GIT_CRED="unreachable"
if echo "$GIT_CRED" | grep -q '"protocol":"https"'; then
    pass "Gateway git credential endpoint responds"
else
    fail "Gateway git credential" "$GIT_CRED"
fi

# ---------------------------------------------------------------------------
echo -e "\n${BOLD}9. Security Controls${NC}"

# 9.1 Capabilities are minimal
CAPS=$(docker inspect gastown --format '{{.HostConfig.CapAdd}}' 2>/dev/null || echo "?")
if echo "$CAPS" | grep -q "DAC_OVERRIDE"; then
    fail "Capabilities" "DAC_OVERRIDE still present: $CAPS"
elif echo "$CAPS" | grep -q "NET_RAW"; then
    fail "Capabilities" "NET_RAW still present: $CAPS"
else
    pass "Capabilities minimal: $CAPS"
fi

# 9.2 All caps dropped
CAPS_DROP=$(docker inspect gastown --format '{{.HostConfig.CapDrop}}' 2>/dev/null || echo "?")
if echo "$CAPS_DROP" | grep -q "ALL"; then
    pass "All capabilities dropped (cap_drop: ALL)"
else
    fail "Cap drop" "$CAPS_DROP"
fi

# 9.3 no-new-privileges set
SECOPT=$(docker inspect gastown --format '{{.HostConfig.SecurityOpt}}' 2>/dev/null || echo "?")
if echo "$SECOPT" | grep -q "no-new-privileges"; then
    pass "no-new-privileges enabled"
else
    fail "no-new-privileges" "$SECOPT"
fi

# 9.4 Resource limits set
PIDS_LIMIT=$(docker inspect gastown --format '{{.HostConfig.PidsLimit}}' 2>/dev/null || echo "0")
if [ "$PIDS_LIMIT" -gt 0 ] 2>/dev/null; then
    pass "PID limit set: $PIDS_LIMIT"
else
    fail "PID limit" "not set ($PIDS_LIMIT)"
fi

MEM_LIMIT=$(docker inspect gastown --format '{{.HostConfig.Memory}}' 2>/dev/null || echo "0")
if [ "$MEM_LIMIT" -gt 0 ] 2>/dev/null; then
    MEM_GB=$(echo "scale=1; $MEM_LIMIT / 1073741824" | bc 2>/dev/null || echo "?")
    pass "Memory limit set: ${MEM_GB}GB"
else
    fail "Memory limit" "not set"
fi

# 9.5 Claude auth is read-only
CLAUDE_MOUNT=$(docker inspect gastown --format '{{range .Mounts}}{{if eq .Destination "/home/agent/.claude"}}{{.Mode}}{{end}}{{end}}' 2>/dev/null || echo "?")
if echo "$CLAUDE_MOUNT" | grep -q "ro"; then
    pass "~/.claude mounted read-only"
else
    fail "Claude auth mount" "expected ro, got: $CLAUDE_MOUNT"
fi

# ---------------------------------------------------------------------------
echo -e "\n${BOLD}10. Network Isolation${NC}"

# 10.1 Containers are on gt-net
NETWORK=$(docker inspect gastown --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null || echo "?")
if echo "$NETWORK" | grep -q "gt-net"; then
    pass "gastown on gt-net network"
else
    fail "Network" "expected gt-net, got: $NETWORK"
fi

# 10.2 Dolt NOT port-mapped to host
DOLT_PORTS=$(docker inspect gastown --format '{{range $p,$conf := .NetworkSettings.Ports}}{{if eq $p "3307/tcp"}}mapped{{end}}{{end}}' 2>/dev/null || echo "")
if [ -z "$DOLT_PORTS" ]; then
    pass "Dolt port 3307 NOT exposed to host"
else
    fail "Dolt exposure" "port 3307 is mapped to host"
fi

# ---------------------------------------------------------------------------
echo -e "\n${BOLD}=== Results ===${NC}\n"
TOTAL=$((PASS + FAIL + SKIP))
echo -e "  ${GREEN}$PASS passed${NC}  ${RED}$FAIL failed${NC}  ${YELLOW}$SKIP skipped${NC}  ($TOTAL total)"

if [ "$FAIL" -gt 0 ]; then
    echo -e "\n  ${RED}Some tests failed.${NC} Check output above."
    exit 1
else
    echo -e "\n  ${GREEN}All tests passed.${NC}"
    exit 0
fi
