#!/bin/bash
# Test harness for the Antigravity security gate hooks. Mirrors
# claude-code/.claude/hooks/tests/run_tests.sh, adapted for Antigravity's
# hook envelope ({"allow_tool": ...} instead of Claude Code's
# hookSpecificOutput.permissionDecision) and its lack of a stdin JSON
# payload (Antigravity's hooks.json matcher already scopes the hook to
# `git push*`, so the script itself doesn't need to detect the command).
#
# Usage: ./run_tests.sh [path-to-agents-dir]

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_DIR="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"
MOCK_BIN="$SCRIPT_DIR/mocks"

PASS_COUNT=0
FAIL_COUNT=0

log_fail() { echo "  FAIL: $1"; }

setup_repo() {
  local dir
  dir=$(mktemp -d)
  (
    cd "$dir" || exit 1
    git init -q
    git config user.email "dev@example.com"
    git config user.name "Test Dev"
    git config core.autocrlf false
    echo "print('hello')" > README.txt
    git add README.txt
    git commit -q -m "initial"
    echo "# a file that a scanner will flag" > vuln.py
    git add vuln.py
    git commit -q -m "add vuln.py"
  )
  echo "$dir"
}

run_hook() {
  local script="$1" repo="$2"
  local state_dir
  state_dir=$(mktemp -d)
  (
    cd "$repo" || exit 1
    # Antigravity's hook contract doesn't consume stdin for a JSON
    # payload (unlike Claude Code), so `read -p` prompts read real stdin.
    # Feed enough blank-line "just pressed Enter" answers to get through
    # the RED confirmation and/or the escalation menu without a real
    # tty; an unrecognized/empty escalation choice is expected to fail
    # closed (deny), which is exactly what these tests check for.
    PATH="$MOCK_BIN:$PATH" \
    MOCK_STATE_DIR="$state_dir" \
    MOCK_FILE="vuln.py" \
    SECURITY_GATE_STATE_DB="$repo/.codemender-test/state.db" \
    bash "$script" > "$repo/.hook_stdout" 2> "$repo/.hook_stderr" < <(printf '\n\n\n\n\n')
    echo $? > "$repo/.hook_exit"
  )
  rm -rf "$state_dir"
}

decision() {
  jq -r 'if .allow_tool == true then "allow" elif .allow_tool == false then "deny" else "MISSING" end' \
    "$1/.hook_stdout" 2>/dev/null
}

reason() {
  jq -r '.reason // ""' "$1/.hook_stdout" 2>/dev/null
}

log_events() {
  local repo="$1"
  [ -f "$repo/.security-gate/findings-log.ndjson" ] || { echo ""; return; }
  jq -r '.event' "$repo/.security-gate/findings-log.ndjson" 2>/dev/null | tr '\n' ','
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS_COUNT=$((PASS_COUNT+1))
  else
    FAIL_COUNT=$((FAIL_COUNT+1))
    log_fail "$desc (expected [$expected], got [$actual])"
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS_COUNT=$((PASS_COUNT+1))
  else
    FAIL_COUNT=$((FAIL_COUNT+1))
    log_fail "$desc (expected to contain [$needle], got [$haystack])"
  fi
}

cleanup_repo() { rm -rf "$1"; }

# --- test cases (same coverage as the Claude Code harness) --------------

test_cm_pass_no_findings() {
  local repo; repo=$(setup_repo)
  MOCK_CM_REPORT_MODE=clean run_hook "$AGENTS_DIR/security_gate_hook.sh" "$repo"
  assert_eq "cm: clean scan allows" "allow" "$(decision "$repo")"
  cleanup_repo "$repo"
}

test_cm_error_blocks_by_default() {
  local repo; repo=$(setup_repo)
  MOCK_CM_REPORT_MODE=error run_hook "$AGENTS_DIR/security_gate_hook.sh" "$repo"
  assert_eq "cm: scan error blocks by default" "deny" "$(decision "$repo")"
  assert_contains "cm: error reason mentions scan failure" "$(reason "$repo")" "failed to run"
  assert_contains "cm: error logged as ERROR" "$(log_events "$repo")" "ERROR"
  cleanup_repo "$repo"
}

test_cm_error_allow_on_error_true() {
  local repo; repo=$(setup_repo)
  SECURITY_GATE_ALLOW_ON_ERROR=true MOCK_CM_REPORT_MODE=error \
    run_hook "$AGENTS_DIR/security_gate_hook.sh" "$repo"
  assert_eq "cm: scan error allows when opted in" "allow" "$(decision "$repo")"
  assert_contains "cm: error still logged even when allowed through" "$(log_events "$repo")" "ERROR"
  cleanup_repo "$repo"
}

test_cm_advisory_low_severity_does_not_block() {
  local repo; repo=$(setup_repo)
  MOCK_CM_REPORT_MODE=low run_hook "$AGENTS_DIR/security_gate_hook.sh" "$repo"
  assert_eq "cm: low-severity finding does not block" "allow" "$(decision "$repo")"
  assert_contains "cm: low-severity finding logged as ADVISORY" "$(log_events "$repo")" "ADVISORY"
  cleanup_repo "$repo"
}

test_cm_blocking_high_severity_autofix_commits() {
  local repo; repo=$(setup_repo)
  SECURITY_GATE_TEST_CMD=true MOCK_CM_REPORT_MODE=high \
    run_hook "$AGENTS_DIR/security_gate_hook.sh" "$repo"
  assert_eq "cm: high-severity finding auto-fixed allows" "allow" "$(decision "$repo")"
  assert_contains "cm: fix logged as FIXED" "$(log_events "$repo")" "FIXED"
  local last_msg
  last_msg=$(cd "$repo" && git log -1 --pretty=%B)
  assert_contains "cm: fix was actually committed" "$last_msg" "F1"
  cleanup_repo "$repo"
}

test_cm_blocking_retries_exhausted_no_tty_fails_closed() {
  local repo; repo=$(setup_repo)
  SECURITY_GATE_TEST_CMD=false MOCK_CM_REPORT_MODE=high \
    run_hook "$AGENTS_DIR/security_gate_hook.sh" "$repo"
  assert_eq "cm: unfixable finding + no tty denies" "deny" "$(decision "$repo")"
  assert_contains "cm: unresolved finding logged as BLOCKED" "$(log_events "$repo")" "BLOCKED"
  cleanup_repo "$repo"
}

test_cm_large_fix_diff_escalates_not_autocommitted() {
  local repo; repo=$(setup_repo)
  SECURITY_GATE_TEST_CMD=true MOCK_CM_REPORT_MODE=high MOCK_CM_FIX_LARGE=true \
  SECURITY_GATE_LARGE_FIX_LINES=10 \
    run_hook "$AGENTS_DIR/security_gate_hook.sh" "$repo"
  assert_eq "cm: oversized fix diff escalates + denies (no tty)" "deny" "$(decision "$repo")"
  local vuln_status
  vuln_status=$(cd "$repo" && git status --porcelain -- vuln.py)
  assert_eq "cm: no dangling uncommitted fix left in vuln.py after escalation deny" "" "$vuln_status"
  cleanup_repo "$repo"
}

test_cm_mixed_severity_fixes_blocking_logs_advisory() {
  local repo; repo=$(setup_repo)
  SECURITY_GATE_TEST_CMD=true MOCK_CM_REPORT_MODE=mixed \
    run_hook "$AGENTS_DIR/security_gate_hook.sh" "$repo"
  assert_eq "cm: mixed severities still allow after fix" "allow" "$(decision "$repo")"
  assert_contains "cm: mixed severities log FIXED" "$(log_events "$repo")" "FIXED"
  assert_contains "cm: mixed severities log ADVISORY" "$(log_events "$repo")" "ADVISORY"
  cleanup_repo "$repo"
}

test_semgrep_pass_no_findings() {
  local repo; repo=$(setup_repo)
  MOCK_SEMGREP_MODE=clean run_hook "$AGENTS_DIR/security_gate_hook_semgrep.sh" "$repo"
  assert_eq "semgrep: clean scan allows" "allow" "$(decision "$repo")"
  cleanup_repo "$repo"
}

test_semgrep_error_blocks_by_default() {
  local repo; repo=$(setup_repo)
  MOCK_SEMGREP_MODE=error run_hook "$AGENTS_DIR/security_gate_hook_semgrep.sh" "$repo"
  assert_eq "semgrep: scan error blocks by default" "deny" "$(decision "$repo")"
  assert_contains "semgrep: error logged as ERROR" "$(log_events "$repo")" "ERROR"
  cleanup_repo "$repo"
}

test_semgrep_error_allow_on_error_true() {
  local repo; repo=$(setup_repo)
  SECURITY_GATE_ALLOW_ON_ERROR=true MOCK_SEMGREP_MODE=error \
    run_hook "$AGENTS_DIR/security_gate_hook_semgrep.sh" "$repo"
  assert_eq "semgrep: scan error allows when opted in" "allow" "$(decision "$repo")"
  cleanup_repo "$repo"
}

test_semgrep_advisory_low_severity_does_not_block() {
  local repo; repo=$(setup_repo)
  MOCK_SEMGREP_MODE=low run_hook "$AGENTS_DIR/security_gate_hook_semgrep.sh" "$repo"
  assert_eq "semgrep: INFO severity does not block" "allow" "$(decision "$repo")"
  assert_contains "semgrep: INFO severity logged as ADVISORY" "$(log_events "$repo")" "ADVISORY"
  cleanup_repo "$repo"
}

test_semgrep_blocking_high_severity_denies() {
  local repo; repo=$(setup_repo)
  MOCK_SEMGREP_MODE=high run_hook "$AGENTS_DIR/security_gate_hook_semgrep.sh" "$repo"
  assert_eq "semgrep: ERROR severity blocks" "deny" "$(decision "$repo")"
  assert_contains "semgrep: deny reason includes finding detail" "$(reason "$repo")" "Rule: x"
  cleanup_repo "$repo"
}

# --- run -----------------------------------------------------------------

for t in \
  test_cm_pass_no_findings \
  test_cm_error_blocks_by_default \
  test_cm_error_allow_on_error_true \
  test_cm_advisory_low_severity_does_not_block \
  test_cm_blocking_high_severity_autofix_commits \
  test_cm_blocking_retries_exhausted_no_tty_fails_closed \
  test_cm_large_fix_diff_escalates_not_autocommitted \
  test_cm_mixed_severity_fixes_blocking_logs_advisory \
  test_semgrep_pass_no_findings \
  test_semgrep_error_blocks_by_default \
  test_semgrep_error_allow_on_error_true \
  test_semgrep_advisory_low_severity_does_not_block \
  test_semgrep_blocking_high_severity_denies \
; do
  echo "-- $t"
  "$t"
done

echo ""
echo "$PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
