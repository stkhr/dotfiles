#!/bin/bash
# Table-driven tests for confirm-pr-size.sh.
# Usage: bash claude/hooks/tests/test-confirm-pr-size.sh
set -uo pipefail

# Hermetic against the machine's git config (init.defaultBranch etc.)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

HOOK="$(cd "$(dirname "$0")/.." && pwd)/confirm-pr-size.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

git init -q -b main "$WORK/seed"
SEED="git -C $WORK/seed -c user.email=t@t -c user.name=t"
$SEED commit -q --allow-empty -m init
$SEED branch -q develop
git clone -q --bare "$WORK/seed" "$WORK/origin.git"

# Clone (so origin/HEAD exists), then commit N changed lines on a branch.
make_repo() {
  local dir="$1" base="$2" file="$3" lines="$4"
  git clone -q "$WORK/origin.git" "$dir"
  local g="git -C $dir -c user.email=t@t -c user.name=t"
  $g checkout -q "$base"
  $g checkout -q -b feature
  mkdir -p "$(dirname "$dir/$file")"
  seq 1 "$lines" > "$dir/$file"
  $g add -A
  $g commit -q -m "add $file"
}

REPO_BIG="$WORK/repo-big"
REPO_SMALL="$WORK/repo-small"
REPO_LOCK="$WORK/repo-lock"
REPO_SNAP="$WORK/repo-snap"
REPO_DEVELOP="$WORK/repo-develop"
PLAIN="$WORK/plain"

make_repo "$REPO_BIG" main src/big.txt 500
make_repo "$REPO_SMALL" main src/small.txt 10
make_repo "$REPO_LOCK" main package-lock.json 500
make_repo "$REPO_SNAP" main "src/__snapshots__/view.snap" 500
mkdir -p "$PLAIN"

# develop carries a 500-line file that main does not have; feature adds 10 lines on top.
git clone -q "$WORK/origin.git" "$REPO_DEVELOP"
GDEV="git -C $REPO_DEVELOP -c user.email=t@t -c user.name=t"
$GDEV checkout -q develop
seq 1 500 > "$REPO_DEVELOP/base.txt"
$GDEV add -A
$GDEV commit -q -m "develop base"
$GDEV push -q origin develop
$GDEV checkout -q -b feature
seq 1 10 > "$REPO_DEVELOP/small.txt"
$GDEV add -A
$GDEV commit -q -m "feature"

run_case() {
  local expect="$1" mode="$2" limit="$3" cwd="$4" cmd="$5"
  local input out decision
  input=$(jq -n --arg c "$cmd" --arg d "$cwd" --arg m "$mode" \
    '{tool_input: {command: $c}, cwd: $d, permission_mode: $m}')
  if [ -n "$limit" ]; then
    out=$(echo "$input" | PR_SIZE_LIMIT_LINES="$limit" bash "$HOOK" 2>/dev/null)
  else
    out=$(echo "$input" | bash "$HOOK" 2>/dev/null)
  fi
  if [ -z "$out" ]; then
    decision="pass"
  else
    decision=$(echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "pass"' 2>/dev/null)
  fi
  if [ "$decision" = "$expect" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL [expect=$expect got=$decision mode=$mode limit=${limit:-default} cwd=$cwd]: $cmd"
  fi
}

CREATE='gh pr create --draft --title "x" --body "y"'

# --- threshold against origin/HEAD (default 400 lines) ---
run_case ask  default '' "$REPO_BIG"   "$CREATE"
run_case pass default '' "$REPO_SMALL" "$CREATE"
run_case ask  default '' "$REPO_BIG"   'gh pr create -d -t "x" -b "y"'

# --- lockfiles and snapshots are not counted ---
run_case pass default '' "$REPO_LOCK" "$CREATE"
run_case pass default '' "$REPO_SNAP" "$CREATE"

# --- --base selects the comparison branch ---
run_case ask  default '' "$REPO_DEVELOP" "$CREATE"
run_case pass default '' "$REPO_DEVELOP" 'gh pr create --draft --base develop --title "x"'
run_case pass default '' "$REPO_DEVELOP" 'gh pr create --draft -B develop --title "x"'
run_case pass default '' "$REPO_DEVELOP" 'gh pr create --draft --base=develop --title "x"'

# --- PR_SIZE_LIMIT_LINES overrides the threshold ---
run_case pass default 1000 "$REPO_BIG"   "$CREATE"
run_case ask  default 5    "$REPO_SMALL" "$CREATE"
run_case ask  default abc  "$REPO_BIG"   "$CREATE"

# --- unattended permission modes pass through ---
run_case pass bypassPermissions '' "$REPO_BIG" "$CREATE"
run_case pass dontAsk           '' "$REPO_BIG" "$CREATE"
run_case ask  auto              '' "$REPO_BIG" "$CREATE"
run_case ask  acceptEdits       '' "$REPO_BIG" "$CREATE"
run_case ask  ''                '' "$REPO_BIG" "$CREATE"

# --- the repo is taken from a leading cd, else the session cwd ---
run_case ask  default '' "$PLAIN"    "cd $REPO_BIG && $CREATE"
run_case pass default '' "$REPO_BIG" "cd $REPO_SMALL && $CREATE"
run_case ask  default '' "$PLAIN"    "cd \"$REPO_BIG\" && $CREATE"

# --- nothing to gate ---
run_case pass default '' "$PLAIN"    "$CREATE"
run_case pass default '' "$REPO_BIG" 'gh pr view 12'
run_case pass default '' "$REPO_BIG" 'gh pr list'
run_case pass default '' "$REPO_BIG" 'git log --oneline'
run_case pass default '' "$REPO_BIG" 'echo "gh pr create"'
run_case pass default '' "$REPO_BIG" ''

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
