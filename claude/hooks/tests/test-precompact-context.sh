#!/bin/bash
# Tests for precompact-context.sh: the summarized tree is the hook cwd, not CLAUDE_PROJECT_DIR.
# Usage: bash claude/hooks/tests/test-precompact-context.sh
set -uo pipefail

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

HOOK="$(cd "$(dirname "$0")/.." && pwd)/precompact-context.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

git init -q -b main "$WORK/launch"
git -C "$WORK/launch" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git init -q -b feat/x "$WORK/worktree"
git -C "$WORK/worktree" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
echo x > "$WORK/worktree/dirty.txt"

OUT=$(jq -n --arg d "$WORK/worktree" '{cwd: $d}' \
  | CLAUDE_PROJECT_DIR="$WORK/launch" bash "$HOOK" \
  | jq -r '.hookSpecificOutput.additionalContext')

check() {
  local label="$1" needle="$2"
  if printf '%s' "$OUT" | grep -qF "$needle"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL [missing]: $label"
  fi
}

check "branch of hook cwd" 'Branch: feat/x'
check "uncommitted change of hook cwd" 'dirty.txt'

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
