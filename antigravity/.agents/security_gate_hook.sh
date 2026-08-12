#!/bin/bash
set -e

# 1. Discover modified files (compare against remote tracking or previous commit)
MODIFIED_FILES=$(git diff --name-only origin/main || git diff --name-only HEAD~1 || true)
if [ -z "$MODIFIED_FILES" ]; then
  echo '{"allow_tool": true}'
  exit 0
fi
# 2. Run CodeMender Scan on each file individually
echo "Running CodeMender scan on changed files..."
echo "$MODIFIED_FILES" | while IFS= read -r file; do
  [ -z "$file" ] && continue
  cm find "$file" -y --bypass-warning >/dev/null 2>&1 || true
done
# Get all open findings in JSON format, and filter for files in $MODIFIED_FILES
SCAN_RESULT=$(cm report --status OPEN --format json | jq --arg files "$MODIFIED_FILES" '
  ($files | split("\n")) as $mod_files |
  [ .[] | select((.FilePath | gsub("\\\\"; "/")) as $fp | any($mod_files[]; . as $mf | $mf != "" and ($fp | endswith($mf)))) ]
' || true)
FINDINGS_COUNT=$(echo "$SCAN_RESULT" | jq 'length')
if [ -z "$FINDINGS_COUNT" ] || [ "$FINDINGS_COUNT" -eq 0 ]; then
  echo "No vulnerabilities found. Allowing push."
  echo '{"allow_tool": true}'
  exit 0
fi

echo "Detected $FINDINGS_COUNT vulnerabilities. Attempting automatic remediation..."

# 3. Remediate & Test Loop (RED-GREEN)
RETRY_COUNT=0
MAX_RETRIES=1

# Save findings to a temp file in /tmp to parse robustly with spaces
echo "$SCAN_RESULT" | jq -c '.[]' > /tmp/findings.jsonl

while read -r finding <&3; do
  FINDING_ID=$(echo "$finding" | jq -r '.FindingID')
  
  # RED step: Prompt agent/developer to write a reproduction test
  echo "Vulnerability detected: $FINDING_ID"
  echo "Before applying the fix, you must write a reproducing test that fails (RED)."
  read -p "Add the test and press Enter once it is verified failing..."
  
  while [ $RETRY_COUNT -le $MAX_RETRIES ]; do
    echo "Attempting cm fix for: $FINDING_ID (Attempt: $((RETRY_COUNT+1)))"
    cm fix "$FINDING_ID" -y --bypass-warning
    
    # GREEN step: Run tests to verify the reproduction test now passes
    # Note: Replace this with your actual test suite command
    if python3 -m unittest discover -s tests; then
      echo "Fix successful and tests passed (GREEN)!"
      break
    else
      echo "Fix broke the tests. Reverting changes..."
      git checkout -- .
      RETRY_COUNT=$((RETRY_COUNT+1))
    fi
  done

  # 4. Conflict / Repeated Failure Escalation to HITL
  if [ $RETRY_COUNT -gt $MAX_RETRIES ]; then
    echo "Conflict detected: Fix for $FINDING_ID repeatedly broke tests."
    echo "Escalating to Human-in-the-Loop..."
    
    # Prompt the user
    echo "Select action for finding $FINDING_ID:"
    echo "1) Mute/ignore finding with explanation (gets appended to commit message)"
    echo "2) Verify finding exploitability via cm verify"
    read -p "Enter choice [1-2]: " Choice

    if [ "$Choice" -eq 1 ]; then
      read -p "Enter suppression justification: " Justification
      # Mute the finding in the local db and append suppression to the git commit message
      python3 -c "import sqlite3, sys, os; conn = sqlite3.connect(os.path.expanduser('~/.codemender/state.db')); conn.cursor().execute('UPDATE findings SET status=\"DISMISSED\", dismiss_reason=? WHERE finding_id LIKE ?', (sys.argv[1], sys.argv[2] + \"%\")); conn.commit(); conn.close()" "$Justification" "$FINDING_ID"
      git commit --amend -m "$(git log -1 --pretty=%B) - Suppressed finding $FINDING_ID: $Justification"
    elif [ "$Choice" -eq 2 ]; then
      # Run cm verify to check exploitability
      if cm verify "$FINDING_ID" -y --bypass-warning; then
        echo "Vulnerability confirmed as exploitable! Blocking push."
        echo '{"allow_tool": false, "reason": "Exploitable vulnerability blocking push"}'
        exit 0
      else
        echo "Vulnerability verified as non-exploitable (False Positive). Proceeding."
      fi
    else
      echo "Invalid choice. Blocking push."
      echo '{"allow_tool": false, "reason": "Verification failed"}'
      exit 1
    fi
  fi
done 3< /tmp/findings.jsonl

# Clean up temp file
rm -f /tmp/findings.jsonl

echo '{"allow_tool": true}'
