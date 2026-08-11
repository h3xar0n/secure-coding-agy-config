#!/bin/bash
set -e

# 1. Discover modified files (compare against remote tracking or previous commit)
MODIFIED_FILES=$(git diff --name-only origin/main || git diff --name-only HEAD~1 || true)
if [ -z "$MODIFIED_FILES" ]; then
  echo '{"allow_tool": true}'
  exit 0
fi

# 2. Run Semgrep Scan on modified files
FILES_TO_SCAN=()
for file in $MODIFIED_FILES; do
  if [ -f "$file" ]; then
    FILES_TO_SCAN+=("$file")
  fi
done

if [ ${#FILES_TO_SCAN[@]} -eq 0 ]; then
  echo '{"allow_tool": true}'
  exit 0
fi

echo "Running Semgrep scan on: ${FILES_TO_SCAN[*]}" >&2

# Run semgrep scan using JSON format
SEMGREP_OUTPUT=$(semgrep scan --config auto --json "${FILES_TO_SCAN[@]}" 2>/dev/null || true)

FINDINGS_COUNT=$(echo "$SEMGREP_OUTPUT" | jq '.results | length' 2>/dev/null || echo 0)

if [ "$FINDINGS_COUNT" -eq 0 ]; then
  echo "No vulnerabilities found. Allowing push." >&2
  echo '{"allow_tool": true}'
  exit 0
fi

# 3. Format findings description for the agent
FINDINGS_DESC=$(echo "$SEMGREP_OUTPUT" | jq -r '
  .results[] | 
  "File: \(.path) Line: \(.start.line)\nRule: \(.check_id)\nDescription: \(.extra.message)\nSeverity: \(.extra.severity)\n---"
')

echo "Detected $FINDINGS_COUNT vulnerabilities." >&2
echo "$FINDINGS_DESC" >&2

# Return allow_tool: false with detailed reason so the agent knows what to fix
REASON="Semgrep detected $FINDINGS_COUNT security issues in your changes. You must fix them before pushing:\n$FINDINGS_DESC"

jq -n --arg reason "$REASON" '{allow_tool: false, reason: $reason}'
