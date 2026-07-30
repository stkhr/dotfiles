#!/bin/bash
# Tests for verify-completion-claims.sh push verification (upstream-aware).
# Usage: bash claude/hooks/tests/test-verify-completion-claims.sh
set -uo pipefail

# Hermetic against the machine's git config (branch.autosetupmerge etc.)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

HOOK="$(cd "$(dirname "$0")/.." && pwd)/verify-completion-claims.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

git init -q --bare "$WORK/origin.git"
git init -q -b main "$WORK/repo"
GIT="git -C $WORK/repo -c user.email=t@t -c user.name=t"
$GIT remote add origin "$WORK/origin.git"
$GIT commit -q --allow-empty -m init

make_transcript() {
  local text="$1" out="$WORK/transcript.jsonl"
  jq -nc --arg t "$text" \
    '{type: "assistant", message: {content: [{type: "text", text: $t}]}}' > "$out"
  echo "$out"
}

run_case() {
  local expect="$1" label="$2" text="$3"
  local transcript
  transcript=$(make_transcript "$text")
  jq -n --arg tp "$transcript" --arg d "$WORK/repo" \
    '{stop_hook_active: false, transcript_path: $tp, cwd: $d}' | bash "$HOOK" >/dev/null 2>&1
  local code=$?
  local got="pass"
  [ "$code" -eq 2 ] && got="block"
  if [ "$got" = "$expect" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL [expect=$expect got=$got]: $label"
  fi
}

# --- no claim: never blocks ---
run_case pass "no claim" '調査を続けます'

# --- local branch name differs from remote name, upstream set, pushed ---
$GIT checkout -q -b 'worktree-feat+x'
$GIT commit -q --allow-empty -m work
$GIT push -q -u origin 'worktree-feat+x:feat/x' 2>/dev/null
run_case pass "upstream-tracked rename push" 'feat/x を pushしました'

# --- upstream set but local has unpushed commits ---
$GIT commit -q --allow-empty -m more
run_case block "unpushed commit behind upstream" 'pushしました'

# --- no upstream, same-name branch pushed ---
$GIT checkout -q -b same-name
$GIT push -q origin same-name 2>/dev/null
run_case pass "same-name fallback pushed" 'pushしました'

# --- no upstream, branch never pushed ---
$GIT checkout -q -b never-pushed
run_case block "never pushed" 'pushしました'

# --- upstream pointing at a local branch is ignored (same-name fallback) ---
$GIT checkout -q -b local-track
$GIT branch -q --set-upstream-to=main local-track
run_case block "local-branch upstream falls back to same-name" 'pushしました'

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
