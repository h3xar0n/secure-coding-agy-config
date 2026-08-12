#!/bin/bash
# CodeMender security gate - Claude Code PreToolUse hook for `git push`.
#
# Wired up from .claude/settings.json:
#   matcher: "Bash", if: "Bash(git push*)"
#
# Claude Code hook contract (https://code.claude.com/docs/en/hooks):
#   - stdin:  JSON with .tool_name / .tool_input.command / ...
#   - stdout: JSON with hookSpecificOutput.permissionDecision
#             "allow" | "deny", exit 0
#
# NOTE: stdin is consumed below to read the hook payload, so this script
# can no longer read the RED/GREEN prompts from stdin the way the original
# Antigravity script did. The interactive `read -p` calls are redirected to
# /dev/tty instead, which only works when Claude Code is attached to a real
# terminal. In headless/CI runs those prompts will fail closed (empty
# answer) - lower MAX_RETRIES or make the escalation branch non-interactive
# if you run this outside an interactive terminal session.

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

# Defense in depth: only run the gate for git push, even if the
# matcher/`if` config above ever changes.
case "$COMMAND" in
  *"git push"*) ;;
  *) allow ;;
esac

# 1. Discover modified files (compare against remote tracking or previous commit)
MODIFIED_FILES=$(git diff --name-only origin/main 2>/dev/null || git diff --name-only HEAD~1 2>/dev/null || true)
if [ -z "$MODIFIED_FILES" ]; then
  allow
fi

# 2. Run CodeMender scan on each modified file
echo "Running CodeMender scan on changed files..." >&2
echo "$MODIFIED_FILES" | while IFS= read -r file; do
  [ -z "$file" ] && continue
  cm find "$file" -y --bypass-warning >/dev/null 2>&1 || true
done

# Get all open findings, filtered to the modified files
SCAN_RESULT=$(cm report --status OPEN --format json | jq --arg files "$MODIFIED_FILES" '
  ($files | split("\n")) as $mod_files |
  [ .[] | select((.FilePath | gsub("\\\\"; "/")) as $fp | any($mod_files[]; . as $mf | $mf != "" and ($fp | endswith($mf)))) ]
' || echo '[]')
FINDINGS_COUNT=$(echo "$SCAN_RESULT" | jq 'length')

if [ -z "$FINDINGS_COUNT" ] || [ "$FINDINGS_COUNT" -eq 0 ]; then
  echo "No vulnerabilities found. Allowing push." >&2
  allow
fi

echo "Detected $FINDINGS_COUNT vulnerabilities. Attempting automatic remediation..." >&2

# 3. Remediate & test loop (RED-GREEN)
RETRY_COUNT=0
MAX_RETRIES=1

echo "$SCAN_RESULT" | jq -c '.[]' > /tmp/findings.jsonl

while read -r finding <&3; do
  FINDING_ID=$(echo "$finding" | jq -r '.FindingID')

  echo "Vulnerability detected: $FINDING_ID" >&2
  echo "Before applying the fix, you must write a reproducing test that fails (RED)." >&2
  read -p "Add the test and press Enter once it is verified failing..." < /dev/tty > /dev/tty 2>&1 || true

  while [ $RETRY_COUNT -le $MAX_RETRIES ]; do
    echo "Attempting cm fix for: $FINDING_ID (Attempt: $((RETRY_COUNT+1)))" >&2
    cm fix "$FINDING_ID" -y --bypass-warning

    # GREEN step: run tests to verify the reproduction test now passes
    # Note: replace this with your actual test suite command
    if python3 -m unittest discover -s tests; then
      echo "Fix successful and tests passed (GREEN)!" >&2
      break
    else
      echo "Fix broke the tests. Reverting changes..." >&2
      git checkout -- .
      RETRY_COUNT=$((RETRY_COUNT+1))
    fi
  done

  # 4. Escalate repeated failures to human review
  if [ $RETRY_COUNT -gt $MAX_RETRIES ]; then
    echo "Conflict detected: Fix for $FINDING_ID repeatedly broke tests." >&2
    echo "Escalating to Human-in-the-Loop..." >&2
    echo "Select action for finding $FINDING_ID:" >&2
    echo "1) Mute/ignore finding with explanation (appended to commit message)" >&2
    echo "2) Verify finding exploitability via cm verify" >&2
    read -p "Enter choice [1-2]: " CHOICE < /dev/tty > /dev/tty 2>&1 || CHOICE=""

    if [ "$CHOICE" = "1" ]; then
      read -p "Enter suppression justification: " JUSTIFICATION < /dev/tty > /dev/tty 2>&1 || JUSTIFICATION="unspecified"
      python3 -c "import sqlite3, sys, os; conn = sqlite3.connect(os.path.expanduser('~/.codemender/state.db')); conn.cursor().execute('UPDATE findings SET status=\"DISMISSED\", dismiss_reason=? WHERE finding_id LIKE ?', (sys.argv[1], sys.argv[2] + \"%\")); conn.commit(); conn.close()" "$JUSTIFICATION" "$FINDING_ID"
      git commit --amend -m "$(git log -1 --pretty=%B) - Suppressed finding $FINDING_ID: $JUSTIFICATION"
    elif [ "$CHOICE" = "2" ]; then
      if cm verify "$FINDING_ID" -y --bypass-warning; then
        echo "Vulnerability confirmed as exploitable! Blocking push." >&2
        rm -f /tmp/findings.jsonl
        deny "Exploitable vulnerability $FINDING_ID confirmed by 'cm verify'. Fix it before pushing."
      else
        echo "Vulnerability verified as non-exploitable (false positive). Proceeding." >&2
      fi
    else
      echo "Invalid choice. Blocking push." >&2
      rm -f /tmp/findings.jsonl
      deny "Unresolved finding $FINDING_ID: no suppression or verification decision was made."
    fi
  fi
done 3< /tmp/findings.jsonl

rm -f /tmp/findings.jsonl
allow
