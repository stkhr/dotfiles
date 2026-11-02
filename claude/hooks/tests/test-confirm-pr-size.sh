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
REPO_EDGE="$WORK/repo-edge"
REPO_SMALL="$WORK/repo-small"
REPO_LOCK="$WORK/repo-lock"
REPO_SNAP="$WORK/repo-snap"
REPO_DEVELOP="$WORK/repo-develop"
PLAIN="$WORK/plain"

make_repo "$REPO_BIG" main src/big.txt 600
make_repo "$REPO_EDGE" main src/edge.txt 500
make_repo "$REPO_SMALL" main src/small.txt 10
make_repo "$REPO_LOCK" main package-lock.json 600
make_repo "$REPO_SNAP" main "src/__snapshots__/view.snap" 600
mkdir -p "$PLAIN"

# develop carries a 600-line file that main does not have; feature adds 10 lines on top.
git clone -q "$WORK/origin.git" "$REPO_DEVELOP"
GDEV="git -C $REPO_DEVELOP -c user.email=t@t -c user.name=t"
$GDEV checkout -q develop
seq 1 600 > "$REPO_DEVELOP/base.txt"
$GDEV add -A
$GDEV commit -q -m "develop base"
$GDEV push -q origin develop
$GDEV checkout -q -b feature
seq 1 10 > "$REPO_DEVELOP/small.txt"
$GDEV add -A
$GDEV commit -q -m "feature"

# NUL bytes make git count the file as binary ("-" in numstat).
REPO_BIN="$WORK/repo-bin"
git clone -q "$WORK/origin.git" "$REPO_BIN"
GBIN="git -C $REPO_BIN -c user.email=t@t -c user.name=t"
$GBIN checkout -q -b feature
seq 1 600 | tr '\n' '\0' > "$REPO_BIN/blob.bin"
$GBIN add -A
$GBIN commit -q -m "add blob"

# Cloned last: pushing to origin main must not move the other fixtures' origin/main.
REPO_RENAME="$WORK/repo-rename"
git clone -q "$WORK/origin.git" "$REPO_RENAME"
GREN="git -C $REPO_RENAME -c user.email=t@t -c user.name=t"
seq 1 600 > "$REPO_RENAME/old.txt"
$GREN add -A
$GREN commit -q -m "add old.txt"
$GREN push -q origin main
$GREN checkout -q -b feature
$GREN mv old.txt new.txt
$GREN commit -q -m "rename"

# A permissionDecision in the output must surface as its own value, never as "pass".
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
    decision=$(echo "$out" | jq -r '
      if (.hookSpecificOutput.permissionDecision // "") != "" then "decision:" + .hookSpecificOutput.permissionDecision
      elif (.systemMessage // "") != "" and (.hookSpecificOutput.additionalContext // "") != ""
        and .hookSpecificOutput.hookEventName == "PreToolUse" then "notice"
      else "malformed" end' 2>/dev/null)
    decision="${decision:-unparsable}"
  fi
  if [ "$decision" = "$expect" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL [expect=$expect got=$decision mode=$mode limit=${limit:-default} cwd=$cwd]: $cmd"
  fi
}

CREATE='gh pr create --draft --title "x" --body "y"'

# --- threshold against origin/HEAD (default 500 lines, exactly 500 is not over) ---
run_case notice default '' "$REPO_BIG"   "$CREATE"
run_case pass   default '' "$REPO_EDGE"  "$CREATE"
run_case pass   default '' "$REPO_SMALL" "$CREATE"
run_case notice default '' "$REPO_BIG"   'gh pr create -d -t "x" -b "y"'

# --- lockfiles, snapshots, binaries and pure renames are not counted ---
run_case pass default '' "$REPO_LOCK"   "$CREATE"
run_case pass default '' "$REPO_SNAP"   "$CREATE"
run_case pass default '' "$REPO_BIN"    "$CREATE"
run_case pass default '' "$REPO_RENAME" "$CREATE"

# --- --base selects the comparison branch ---
run_case notice default '' "$REPO_DEVELOP" "$CREATE"
run_case pass   default '' "$REPO_DEVELOP" 'gh pr create --draft --base develop --title "x"'
run_case pass   default '' "$REPO_DEVELOP" 'gh pr create --draft -B develop --title "x"'
run_case pass   default '' "$REPO_DEVELOP" 'gh pr create --draft --base=develop --title "x"'

# --- --base is read from the gh pr create segment only ---
run_case notice default '' "$REPO_BIG" 'gh pr create --draft --title "x" --body "measured with --base main2"'
run_case notice default '' "$REPO_BIG" 'gh pr create --draft --title "x" --body "fix -B handling"'
run_case notice default '' "$REPO_BIG" "git checkout -B tmp && $CREATE"
HEREDOC_CMD='gh pr create --draft --title "x" --body "$(cat <<EOF
--base develop
EOF
)"'
run_case notice default '' "$REPO_DEVELOP" "$HEREDOC_CMD"

# --- an unresolvable or quoted --base falls back to the default base ---
run_case notice default '' "$REPO_BIG"     'gh pr create --draft --base nope --title "x"'
run_case notice default '' "$REPO_DEVELOP" 'gh pr create --draft --base "develop" --title "x"'
out=$(jq -n --arg d "$REPO_BIG" \
  '{tool_input: {command: "gh pr create --draft --base nope --title \"x\""}, cwd: $d, permission_mode: "default"}' \
  | bash "$HOOK" 2>/dev/null)
if echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""' | grep -q 'base origin/main'; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL [unresolvable --base should report base origin/main]: $out"
fi

# --- both the user-facing and the Claude-facing text carry the measured numbers ---
out=$(jq -n --arg d "$REPO_BIG" \
  '{tool_input: {command: "gh pr create --draft --title \"x\""}, cwd: $d, permission_mode: "default"}' \
  | bash "$HOOK" 2>/dev/null)
if echo "$out" | jq -r '.systemMessage' | grep -q '600 行 / 1 ファイルが閾値 500 行' \
  && echo "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -q '600 行 / 1 ファイルが閾値 500 行'; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL [notice should carry 600 行 / 1 ファイル / 閾値 500]: $out"
fi

# --- gh pr create followed by a separator is still detected ---
run_case notice default '' "$REPO_BIG" 'gh pr create;echo done'
run_case notice default '' "$REPO_BIG" 'gh pr create|cat'

# --- PR_SIZE_LIMIT_LINES overrides the threshold ---
run_case pass   default 1000 "$REPO_BIG"   "$CREATE"
run_case notice default 5    "$REPO_SMALL" "$CREATE"
run_case notice default abc  "$REPO_BIG"   "$CREATE"
out=$(jq -n --arg d "$REPO_BIG" \
  '{tool_input: {command: "gh pr create --draft --title \"x\""}, cwd: $d, permission_mode: "default"}' \
  | PR_SIZE_LIMIT_LINES=abc bash "$HOOK" 2>/dev/null)
if echo "$out" | jq -r '.systemMessage' | grep -q '閾値 500 行'; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL [non-numeric PR_SIZE_LIMIT_LINES should fall back to 500]: $out"
fi

# --- the notice does not depend on permission_mode (unattended runs see it too) ---
run_case notice bypassPermissions '' "$REPO_BIG" "$CREATE"
run_case notice dontAsk           '' "$REPO_BIG" "$CREATE"
run_case notice auto              '' "$REPO_BIG" "$CREATE"
run_case notice acceptEdits       '' "$REPO_BIG" "$CREATE"
run_case notice ''                '' "$REPO_BIG" "$CREATE"

# --- the repo is taken from a leading cd, else the session cwd ---
run_case notice default '' "$PLAIN"    "cd $REPO_BIG && $CREATE"
run_case pass   default '' "$REPO_BIG" "cd $REPO_SMALL && $CREATE"
run_case notice default '' "$PLAIN"    "cd \"$REPO_BIG\" && $CREATE"

# --- nothing to report ---
run_case pass default '' "$PLAIN"    "$CREATE"
run_case pass default '' "$REPO_BIG" 'gh pr view 12'
run_case pass default '' "$REPO_BIG" 'gh pr list'
run_case pass default '' "$REPO_BIG" 'git log --oneline'
run_case pass default '' "$REPO_BIG" 'echo "gh pr create"'
run_case pass default '' "$REPO_BIG" ''

# --- pass: broken input must not crash or emit anything ---
out=$(echo 'not json' | bash "$HOOK" 2>/dev/null)
if [ -z "$out" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL [broken JSON should pass silently]"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
