#!/bin/bash
# Table-driven tests for protect-main-branch.sh.
# Usage: bash claude/hooks/tests/test-protect-main-branch.sh
set -uo pipefail

# Hermetic against the machine's git config (init.defaultBranch etc.)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

HOOK="$(cd "$(dirname "$0")/.." && pwd)/protect-main-branch.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

make_repo() {
  local dir="$1" branch="$2"
  git init -q -b main "$dir"
  git -C "$dir" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  [ "$branch" != "main" ] && git -C "$dir" checkout -q -b "$branch"
}

REPO_MAIN="$WORK/repo-main"
REPO_FEAT="$WORK/repo-feat"
REPO_SPACE="$WORK/repo with space"
make_repo "$REPO_MAIN" main
make_repo "$REPO_FEAT" feature
make_repo "$REPO_SPACE" main

run_case() {
  local expect="$1" cwd="$2" cmd="$3"
  jq -n --arg c "$cmd" --arg d "$cwd" '{tool_input: {command: $c}, cwd: $d}' | bash "$HOOK" >/dev/null 2>&1
  local code=$?
  local got="pass"
  [ "$code" -eq 2 ] && got="block"
  if [ "$got" = "$expect" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL [expect=$expect got=$got cwd=$cwd]: $cmd"
  fi
}

# --- cwd judgment (existing behavior) ---
run_case block "$REPO_MAIN" 'git commit -m "x"'
run_case pass  "$REPO_FEAT" 'git commit -m "x"'
run_case pass  "$REPO_MAIN" 'echo hello'
run_case pass  "$REPO_MAIN" 'git status'
run_case block "$REPO_MAIN" 'git commit;echo done'

# --- branch created in the same command, BEFORE the commit ---
run_case pass "$REPO_MAIN" 'git checkout -b feat/x && git commit -m "x"'
run_case pass "$REPO_MAIN" 'git switch -c feat/x && git commit -m "x"'
run_case pass "$REPO_MAIN" 'git switch --create feat/x && git commit -m "x"'
run_case block "$REPO_MAIN" 'git switch feat/x && git commit -m "x"'

# --- branch creation AFTER the commit does not protect it ---
run_case block "$REPO_MAIN" 'git commit -m "x" && git checkout -b feat/next'
run_case block "$REPO_MAIN" 'git commit -m "see git checkout -b docs"'

# --- git -C <path>: judge the target repo, not the session cwd ---
run_case block "$REPO_FEAT" "git -C $REPO_MAIN commit -m 'x'"
run_case pass  "$REPO_MAIN" "git -C $REPO_FEAT commit -m 'x'"
run_case pass  "$REPO_MAIN" "git -C $REPO_FEAT add -A && git -C $REPO_FEAT commit -m 'x'"
run_case block "$REPO_FEAT" "git -C \"$REPO_SPACE\" commit -m 'x'"

# --- every -C commit target is judged, not only the first ---
run_case block "$REPO_FEAT" "git -C $REPO_FEAT commit -m 'x' && git -C $REPO_MAIN commit -m 'x'"

# --- cd <path> && git commit: judge the target repo ---
run_case pass  "$REPO_MAIN" "cd $REPO_FEAT && git add -A && git commit -m 'x'"
run_case block "$REPO_FEAT" "cd $REPO_MAIN && git commit -m 'x'"
run_case block "$REPO_FEAT" "cd \"$REPO_SPACE\" && git commit -m 'x'"

# --- cd AFTER the commit does not decide its repo ---
run_case block "$REPO_MAIN" "git commit -m 'x'; cd $REPO_FEAT"
run_case pass  "$REPO_MAIN" "cd $REPO_FEAT && git commit -m 'x' && cd $REPO_MAIN"

# --- relative path resolution against cwd ---
run_case pass  "$REPO_MAIN" 'git -C ../repo-feat commit -m "x"'
run_case block "$REPO_FEAT" 'cd ../repo-main && git commit -m "x"'

# --- unresolvable target falls back to cwd judgment ---
run_case block "$REPO_MAIN" 'git -C /nonexistent-dir-xyz commit -m "x"'
run_case pass  "$REPO_FEAT" 'git -C /nonexistent-dir-xyz commit -m "x"'

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
