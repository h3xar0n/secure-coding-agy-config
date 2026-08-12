#!/bin/bash
# Semgrep security gate - Claude Code PreToolUse hook for `git push`.
# Open-source alternative to security_gate_hook.sh for when CodeMender
# access isn't available. Wired up from .claude/settings.semgrep.json
# (rename that file to settings.json to activate it).
#
# Unlike the CodeMender script, this one never prompts interactively: it
# just reports findings back to Claude via permissionDecisionReason, and
# the agent is expected to fix them itself (guided by the secure-coding
# and test-driven-development skills) before pushing again.

set -e

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

allow() {
  jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow"}}'
  exit 0
}

deny() {
  local reason="$1"
  jq -n --arg reason "$reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
}

case "$COMMAND" in
  *"git push"*) ;;
  *) allow ;;
esac

# 1. Discover modified files (compare against remote tracking or previous commit)
MODIFIED_FILES=$(git diff --name-only origin/main 2>/dev/null || git diff --name-only HEAD~1 2>/dev/null || true)
if [ -z "$MODIFIED_FILES" ]; then
  allow
fi

# 2. Run Semgrep scan on modified files
FILES_TO_SCAN=()
for file in $MODIFIED_FILES; do
  [ -f "$file" ] && FILES_TO_SCAN+=("$file")
done

if [ ${#FILES_TO_SCAN[@]} -eq 0 ]; then
  allow
fi

echo "Running Semgrep scan on: ${FILES_TO_SCAN[*]}" >&2
SEMGREP_OUTPUT=$(semgrep scan --config auto --json "${FILES_TO_SCAN[@]}" 2>/dev/null || true)
FINDINGS_COUNT=$(echo "$SEMGREP_OUTPUT" | jq '.results | length' 2>/dev/null || echo 0)

if [ "$FINDINGS_COUNT" -eq 0 ]; then
  echo "No vulnerabilities found. Allowing push." >&2
  allow
fi

# 3. Format findings for the agent
FINDINGS_DESC=$(echo "$SEMGREP_OUTPUT" | jq -r '
  .results[] |
  "File: \(.path) Line: \(.start.line)\nRule: \(.check_id)\nDescription: \(.extra.message)\nSeverity: \(.extra.severity)\n---"
')

echo "Detected $FINDINGS_COUNT vulnerabilities." >&2
echo "$FINDINGS_DESC" >&2

REASON="Semgrep detected $FINDINGS_COUNT security issue(s) in your changes. Fix them (using the secure-coding and test-driven-development skills) before pushing:
$FINDINGS_DESC"

deny "$REASON"
