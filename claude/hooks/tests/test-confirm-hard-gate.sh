#!/bin/bash
# Table-driven tests for confirm-hard-gate.sh.
# Usage: bash claude/hooks/tests/test-confirm-hard-gate.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/confirm-hard-gate.sh"
PASS=0
FAIL=0

run_case() {
  local expect="$1" cmd="$2"
  local out decision
  out=$(jq -n --arg c "$cmd" '{tool_input: {command: $c}}' | bash "$HOOK" 2>/dev/null)
  if [ -z "$out" ]; then
    decision="pass"
  else
    decision=$(echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "pass"' 2>/dev/null)
  fi
  if [ "$decision" = "$expect" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL [expect=$expect got=$decision]: $cmd"
  fi
}

# --- ask: force push ---
run_case ask 'git push --force origin main'
run_case ask 'git push origin main --force'
run_case ask 'git push -f'
run_case ask 'git push --force-with-lease origin feature'
run_case ask 'git push --force-with-lease=refs/heads/x origin x'
run_case ask 'cd /tmp && git push -f origin main'

# --- ask: --no-verify ---
run_case ask 'git commit --no-verify -m "x"'
run_case ask 'git push --no-verify'

# --- ask: branch deletion ---
run_case ask 'git branch -D feature-x'
run_case ask 'git branch -d merged-branch'
run_case ask 'git branch --delete feature-x'
run_case ask 'git push origin --delete feature-x'
run_case ask 'git push -d origin feature-x'

# --- ask: gh pr external operations ---
run_case ask 'gh pr close 12'
run_case ask 'gh pr merge 12 --squash'
run_case ask 'gh pr ready 12'
run_case ask 'gh pr comment 12 --body "hi"'
run_case ask 'gh pr review 12 --approve'

# --- ask: non-draft pr create ---
run_case ask 'gh pr create --title "x" --body "y"'

# --- pass: normal operations ---
run_case pass 'git push origin main'
run_case pass 'git push -n origin main'
run_case pass 'git push --dry-run origin main'
run_case pass 'git push -u origin feature-x'
run_case pass 'gh pr create --draft --title "x" --body "y"'
run_case pass 'gh pr create -d -t "x" -b "y"'
run_case pass 'gh pr view 12'
run_case pass 'gh pr checks'
run_case pass 'gh pr list'
run_case pass 'git branch feature-x'
run_case pass 'git branch --show-current'
run_case pass 'git commit -m "feat: x"'
run_case pass 'ls -la'
run_case pass ''

# --- pass: broken input must not crash or ask ---
out=$(echo 'not json' | bash "$HOOK" 2>/dev/null)
if [ -z "$out" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL [broken JSON should pass silently]"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
