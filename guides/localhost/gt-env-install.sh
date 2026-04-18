#!/usr/bin/env bash
# gt-env-install — add Gas Town env vars (and ~/.local/bin to PATH) to your shell rc.
#
# Detects $SHELL and installs into the right rc file, idempotently. Re-running
# replaces the previous block. Pass --uninstall to remove it.
#
# Vars installed:
#   GT_TOWN_ROOT           where your gt town lives (default: ~/gt)
#   GT_VLOGS_QUERY_URL     VictoriaLogs LogsQL query endpoint (for `gt feed`/`gt log`)
#   GT_OTEL_LOGS_URL       OTLP logs endpoint (so spawned agents push to VictoriaLogs)

set -euo pipefail

TOWN_ROOT="${GT_TOWN_ROOT:-$HOME/gt}"
VLOGS_QUERY="${GT_VLOGS_QUERY_URL:-http://localhost:9428/select/logsql/query}"
VLOGS_OTEL="${GT_OTEL_LOGS_URL:-http://localhost:9428/insert/opentelemetry/v1/logs}"

BEGIN_MARK="# >>> gas-town env (managed by gt-env-install) >>>"
END_MARK="# <<< gas-town env (managed by gt-env-install) <<<"

usage() {
  sed -n '2,9p' "$0" | sed 's/^# *//'
  echo
  echo "Usage: gt-env-install [--shell zsh|bash|ksh|fish] [--uninstall] [--dry-run]"
}

# ---- args ----
SHELL_OVERRIDE=""
ACTION="install"
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --shell)     SHELL_OVERRIDE="$2"; shift 2 ;;
    --uninstall) ACTION="uninstall"; shift ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- detect shell + rc file ----
shell_name="${SHELL_OVERRIDE:-$(basename "${SHELL:-/bin/bash}")}"
case "$shell_name" in
  zsh)        RC="$HOME/.zshrc";              SYNTAX="posix" ;;
  bash)
    # bash uses .bash_profile on macOS login shells, .bashrc elsewhere.
    if [[ "$(uname -s)" == "Darwin" && -f "$HOME/.bash_profile" ]]; then
      RC="$HOME/.bash_profile"
    else
      RC="$HOME/.bashrc"
    fi
    SYNTAX="posix"
    ;;
  ksh|ksh93|mksh) RC="$HOME/.kshrc";          SYNTAX="posix" ;;
  sh|dash)    RC="$HOME/.profile";             SYNTAX="posix" ;;
  fish)       RC="$HOME/.config/fish/config.fish"; SYNTAX="fish" ;;
  *)
    echo "warning: unknown shell '$shell_name', falling back to ~/.profile (POSIX)" >&2
    RC="$HOME/.profile"; SYNTAX="posix"
    ;;
esac

mkdir -p "$(dirname "$RC")"
[[ -f "$RC" ]] || : > "$RC"

# ---- compose block ----
if [[ "$SYNTAX" == "fish" ]]; then
  read -r -d '' BLOCK <<EOF || true
$BEGIN_MARK
set -gx GT_TOWN_ROOT "$TOWN_ROOT"
set -gx GT_VLOGS_QUERY_URL "$VLOGS_QUERY"
set -gx GT_OTEL_LOGS_URL "$VLOGS_OTEL"
if not contains "\$HOME/.local/bin" \$PATH
    set -gx PATH "\$HOME/.local/bin" \$PATH
end
$END_MARK
EOF
else
  read -r -d '' BLOCK <<EOF || true
$BEGIN_MARK
export GT_TOWN_ROOT="$TOWN_ROOT"
export GT_VLOGS_QUERY_URL="$VLOGS_QUERY"
export GT_OTEL_LOGS_URL="$VLOGS_OTEL"
case ":\$PATH:" in
  *":\$HOME/.local/bin:"*) ;;
  *) export PATH="\$HOME/.local/bin:\$PATH" ;;
esac
$END_MARK
EOF
fi

# ---- idempotent strip + insert ----
strip_block() {
  # delete any existing managed block
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    $0==b {inblk=1; next}
    inblk && $0==e {inblk=0; next}
    !inblk {print}
  ' "$RC"
}

stripped="$(strip_block)"

if [[ "$ACTION" == "uninstall" ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] would remove gas-town block from $RC"
  else
    printf '%s\n' "$stripped" > "$RC"
    echo "✓ removed gas-town env block from $RC"
  fi
  exit 0
fi

new_contents="${stripped%$'\n'}"$'\n\n'"$BLOCK"$'\n'

if [[ $DRY_RUN -eq 1 ]]; then
  echo "[dry-run] target rc: $RC"
  echo "[dry-run] block to write:"
  printf '%s\n' "$BLOCK" | sed 's/^/    /'
  exit 0
fi

# Backup once if no managed block existed before.
if ! grep -qF "$BEGIN_MARK" "$RC" 2>/dev/null; then
  cp "$RC" "$RC.gt-backup.$(date +%Y%m%d%H%M%S)"
fi

printf '%s' "$new_contents" > "$RC"
echo "✓ installed gas-town env block in $RC (shell: $shell_name)"
echo
echo "Vars set:"
echo "  GT_TOWN_ROOT=$TOWN_ROOT"
echo "  GT_VLOGS_QUERY_URL=$VLOGS_QUERY"
echo "  GT_OTEL_LOGS_URL=$VLOGS_OTEL"
echo "  PATH prepended with: \$HOME/.local/bin"
echo
echo "Activate now in this shell:"
case "$SYNTAX" in
  fish) echo "  source $RC" ;;
  *)    echo "  source $RC    # or open a new terminal" ;;
esac
echo
echo "Next steps to start Gas Town and watch logs:"
echo "  1) brew services start victorialogs   # if it's not already running"
echo "  2) gt start                           # boots Deacon + Mayor (Witnesses lazy)"
echo "  3) gt mayor attach                    # opens the Mayor tmux session"
echo "  4) (in another terminal)  gtf -a      # agents view: tool-call observability"
echo "                            gtf log -f  # tail spawn/wake/handoff/done events"
