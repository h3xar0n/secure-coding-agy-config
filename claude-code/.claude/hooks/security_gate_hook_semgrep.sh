#!/bin/bash
# Semgrep security gate - Claude Code PreToolUse hook for `git push`.
# Open-source alternative to security_gate_hook.sh for when CodeMender
# access isn't available. Wired up from .claude/settings.semgrep.json
# (rename that file to settings.json to activate it).
#
# Unlike the CodeMender script, this one never prompts interactively and
# never auto-fixes: it just reports findings back to Claude via
# permissionDecisionReason, and the agent is expected to fix them itself
# (guided by the secure-coding and test-driven-development skills) before
# pushing again.
#
# Outcome model (see threat_model.md at the repo root):
#   PASS      - scan ran, no findings.
#   ADVISORY  - scan ran, findings below SECURITY_GATE_BLOCK_SEVERITY.
#               Push proceeds; logged and (if configured) sent to
#               SECURITY_GATE_NOTIFY_CMD so another team can follow up.
#   ERROR     - semgrep itself could not produce a result (missing
#               binary, crash, unparseable output). NEVER treated as "0
#               findings" - blocks by default (SECURITY_GATE_ALLOW_ON_ERROR
#               =true to opt out).
#   BLOCKED   - findings at/above the block threshold - push denied with
#               the finding details so the agent can fix and retry.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/gate_common.sh
source "$SCRIPT_DIR/lib/gate_common.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

case "$COMMAND" in
  *"git push"*) ;;
  *) allow ;;
esac

command -v semgrep >/dev/null 2>&1 || handle_scan_error "semgrep" "the 'semgrep' CLI is not on PATH"

# 1. Discover modified files (compare against remote tracking or previous commit)
MODIFIED_FILES=$(git diff --name-only origin/main 2>/dev/null || git diff --name-only HEAD~1 2>/dev/null || true)
if [ -z "$MODIFIED_FILES" ]; then
  allow
fi

# NUL/space-safe file list (the previous `for file in $MODIFIED_FILES`
# word-split on spaces in filenames).
read_lines_into_array MODIFIED_FILES_ARR "$MODIFIED_FILES"
FILES_TO_SCAN=()
for file in "${MODIFIED_FILES_ARR[@]}"; do
  [ -f "$file" ] && FILES_TO_SCAN+=("$file")
done

if [ ${#FILES_TO_SCAN[@]} -eq 0 ]; then
  allow
fi

echo "Running Semgrep scan on: ${FILES_TO_SCAN[*]}" >&2
SEMGREP_ERR_FILE=$(mktemp)
if SEMGREP_OUTPUT=$(semgrep scan --config auto --json "${FILES_TO_SCAN[@]}" 2>"$SEMGREP_ERR_FILE"); then
  SEMGREP_EXIT=0
else
  SEMGREP_EXIT=$?
fi
if [ $SEMGREP_EXIT -ne 0 ] || ! echo "$SEMGREP_OUTPUT" | jq -e . >/dev/null 2>&1; then
  ERR_DETAIL=$(tail -c 500 "$SEMGREP_ERR_FILE" 2>/dev/null)
  rm -f "$SEMGREP_ERR_FILE"
  handle_scan_error "semgrep" "semgrep exited $SEMGREP_EXIT: ${ERR_DETAIL:-no output}"
fi
rm -f "$SEMGREP_ERR_FILE"

FINDINGS_COUNT=$(echo "$SEMGREP_OUTPUT" | jq '.results | length' 2>/dev/null || echo 0)
if [ "$FINDINGS_COUNT" -eq 0 ]; then
  echo "No vulnerabilities found. Allowing push." >&2
  allow
fi

# 2. Split findings by severity.
BLOCKING_JSON=$(echo "$SEMGREP_OUTPUT" | jq -c '.results[]' | while IFS= read -r r; do
  SEV=$(echo "$r" | jq -r '.extra.severity // "UNKNOWN"')
  RANK=$(severity_rank "$SEV")
  THRESH=$(severity_rank "$SECURITY_GATE_BLOCK_SEVERITY")
  [ "$RANK" -ge "$THRESH" ] && echo "$r"
done | jq -s '.')
ADVISORY_JSON=$(echo "$SEMGREP_OUTPUT" | jq -c '.results[]' | while IFS= read -r r; do
  SEV=$(echo "$r" | jq -r '.extra.severity // "UNKNOWN"')
  RANK=$(severity_rank "$SEV")
  THRESH=$(severity_rank "$SECURITY_GATE_BLOCK_SEVERITY")
  [ "$RANK" -lt "$THRESH" ] && echo "$r"
done | jq -s '.')

ADV_COUNT=$(echo "$ADVISORY_JSON" | jq 'length')
if [ "$ADV_COUNT" -gt 0 ]; then
  log_event "ADVISORY" "semgrep" "$(jq -n --argjson f "$ADVISORY_JSON" '{findings:$f}')"
  notify "ADVISORY" "$ADV_COUNT finding(s) below the $SECURITY_GATE_BLOCK_SEVERITY block threshold were pushed without blocking. Review $SECURITY_GATE_LOG." \
    "$(jq -n --argjson f "$ADVISORY_JSON" '{findings:$f}')"
fi

BLOCK_COUNT=$(echo "$BLOCKING_JSON" | jq 'length')
if [ "$BLOCK_COUNT" -eq 0 ]; then
  echo "Only advisory-severity findings (below $SECURITY_GATE_BLOCK_SEVERITY). Allowing push." >&2
  allow
fi

# 3. Format blocking findings for the agent and deny.
FINDINGS_DESC=$(echo "$BLOCKING_JSON" | jq -r '
  .[] |
  "File: \(.path) Line: \(.start.line)\nRule: \(.check_id)\nDescription: \(.extra.message)\nSeverity: \(.extra.severity)\n---"
')

echo "Detected $BLOCK_COUNT blocking-severity vulnerabilit(y/ies)." >&2
echo "$FINDINGS_DESC" >&2

log_event "BLOCKED" "semgrep" "$(jq -n --argjson f "$BLOCKING_JSON" '{findings:$f}')"

REASON="Semgrep detected $BLOCK_COUNT security issue(s) at/above the $SECURITY_GATE_BLOCK_SEVERITY threshold in your changes. Fix them (using the secure-coding and test-driven-development skills) before pushing:
$FINDINGS_DESC"

deny "$REASON"
