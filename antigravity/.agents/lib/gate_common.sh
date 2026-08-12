#!/bin/bash
# Shared helpers for the Antigravity security gate hooks (CodeMender and
# Semgrep variants). Sourced, not executed directly. This is a port of
# claude-code/.claude/hooks/lib/gate_common.sh - same logic, different
# hook envelope ({"allow_tool": ...} instead of Claude Code's
# hookSpecificOutput.permissionDecision). See threat_model.md at the repo
# root for the design (PASS / ADVISORY / ERROR / BLOCKED outcomes,
# severity-based fail-open, and why `cm verify` is never called on the
# happy path).

# --- Config (override via env, or Antigravity's hook env config) ---
: "${SECURITY_GATE_BLOCK_SEVERITY:=HIGH}"        # findings at/above this rank block; below are advisory
: "${SECURITY_GATE_ALLOW_ON_ERROR:=false}"       # true = let the push through when the scanner itself fails to run
: "${SECURITY_GATE_LARGE_FIX_LINES:=50}"         # cm fix diffs bigger than this escalate instead of auto-committing
: "${SECURITY_GATE_MAX_RETRIES:=1}"
: "${SECURITY_GATE_TEST_CMD:=python3 -m unittest discover -s tests}"
: "${SECURITY_GATE_NOTIFY_CMD:=}"                # optional; receives a JSON event on stdin (e.g. a Slack/ticket webhook wrapper)
: "${SECURITY_GATE_STATE_DB:=$HOME/.codemender/state.db}"

_gate_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

: "${SECURITY_GATE_LOG:=$(_gate_repo_root)/.security-gate/findings-log.ndjson}"

# --- Antigravity hook envelope ---
allow() {
  echo '{"allow_tool": true}'
  exit 0
}

deny() {
  local reason="$1"
  jq -n --arg reason "$reason" '{allow_tool: false, reason: $reason}'
  exit 0
}

# --- Severity ---
# Normalizes both CodeMender-style (CRITICAL/HIGH/MEDIUM/LOW) and
# Semgrep-style (ERROR/WARNING/INFO) severities to a common 1-4 rank.
# Unrecognized severities rank as 4 (blocking) - fail-safe, not fail-open,
# for the one axis we can't verify against real tool output.
severity_rank() {
  case "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')" in
    CRITICAL) echo 4 ;;
    HIGH|ERROR) echo 3 ;;
    MEDIUM|WARNING) echo 2 ;;
    LOW|INFO) echo 1 ;;
    *) echo 4 ;;
  esac
}

is_blocking_severity() {
  [ "$(severity_rank "$1")" -ge "$(severity_rank "$SECURITY_GATE_BLOCK_SEVERITY")" ]
}

# --- Audit log ---
# log_event EVENT TOOL EXTRA_JSON
#   EVENT: PASS | ADVISORY | ERROR | BLOCKED | FIXED
#   TOOL:  codemender | semgrep
#   EXTRA_JSON: a jq object literal merged into the record (e.g. findings, reason)
# Best-effort: a logging failure must never itself block or crash the hook.
log_event() {
  local event="$1" tool="$2" extra="$3"
  # NOTE: deliberately not `extra="${3:-{}}"` - bash doesn't brace-match
  # inside a ${var:-word} default, so that idiom parses as `${3:-{}` plus
  # a stray literal `}` appended after every non-empty $3, producing
  # invalid JSON that jq would silently reject below.
  [ -z "$extra" ] && extra="{}"
  mkdir -p "$(dirname "$SECURITY_GATE_LOG")" 2>/dev/null || true
  if ! jq -n \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg event "$event" \
    --arg tool "$tool" \
    --arg actor "$(git config user.email 2>/dev/null || echo unknown)" \
    --arg commit "$(git rev-parse --short HEAD 2>/dev/null || echo unknown)" \
    --argjson extra "$extra" \
    '{ts:$ts, event:$event, tool:$tool, actor:$actor, commit:$commit} + $extra' \
    >> "$SECURITY_GATE_LOG" 2>/dev/null; then
    echo "(warning: failed to write audit log entry to $SECURITY_GATE_LOG - continuing anyway, a logging failure must not block or silently pass a push)" >&2
  fi
}

# notify EVENT MESSAGE EXTRA_JSON
# Always prints a loud stderr banner; also invokes SECURITY_GATE_NOTIFY_CMD
# with a JSON payload on stdin if set, so another team/channel can be
# looped in without depending on the developer to relay it themselves.
# A failing notify command is logged, not fatal.
notify() {
  local event="$1" message="$2" extra="$3"
  [ -z "$extra" ] && extra="{}"
  {
    echo ""
    echo "==== SECURITY GATE: $event ===="
    echo "$message"
    echo "================================"
  } >&2
  if [ -n "$SECURITY_GATE_NOTIFY_CMD" ]; then
    local payload
    payload=$(jq -n --arg event "$event" --arg message "$message" --argjson extra "$extra" \
      '{event:$event, message:$message} + $extra')
    if ! echo "$payload" | sh -c "$SECURITY_GATE_NOTIFY_CMD" >/dev/null 2>&1; then
      echo "(notify command failed - see $SECURITY_GATE_LOG for the record)" >&2
    fi
  fi
}

# handle_scan_error TOOL REASON
# The scanner itself couldn't produce a result (missing binary, auth
# failure, crash, unparseable output) - this must never be treated the
# same as "scan ran and found nothing" (see threat_model.md T1).
handle_scan_error() {
  local tool="$1" reason="$2"
  log_event "ERROR" "$tool" "$(jq -n --arg r "$reason" '{reason:$r}')"
  notify "ERROR" "Security scan ($tool) could not run: $reason" "{}"
  if [ "$SECURITY_GATE_ALLOW_ON_ERROR" = "true" ]; then
    echo "SECURITY_GATE_ALLOW_ON_ERROR=true - allowing push despite scan failure (logged above)." >&2
    allow
  fi
  deny "Security scan ($tool) failed to run: $reason
Push blocked because the gate could not confirm the code is clean (not because a vulnerability was found).
Set SECURITY_GATE_ALLOW_ON_ERROR=true to let scan failures through if that's the intended policy - not recommended by default.
See $SECURITY_GATE_LOG for the record."
}

# Read a newline-separated file list into an array without word-splitting
# on spaces (fixes a real bug in the previous `for f in $MODIFIED_FILES`
# loop - filenames with spaces silently broke it).
read_lines_into_array() {
  local __arr_name="$1" __input="$2"
  local __line
  eval "$__arr_name=()"
  while IFS= read -r __line; do
    [ -z "$__line" ] && continue
    eval "$__arr_name+=(\"\$__line\")"
  done <<< "$__input"
}
