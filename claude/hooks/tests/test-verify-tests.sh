#!/bin/bash
# Tests for verify-tests.sh: loop guard, cwd from hook input, exit codes.
# Usage: bash claude/hooks/tests/test-verify-tests.sh
set -uo pipefail

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

HOOK="$(cd "$(dirname "$0")/.." && pwd)/verify-tests.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

make_repo() {
  local dir="$1" test_cmd="$2"
  mkdir -p "$dir"
  git init -q -b main "$dir"
  printf '{"name":"t","scripts":{"test":"%s"}}\n' "$test_cmd" > "$dir/package.json"
  git -C "$dir" add package.json
  git -C "$dir" -c user.email=t@t -c user.name=t commit -q -m init
}

FAILING="$WORK/failing"
PASSING="$WORK/passing"
make_repo "$FAILING" 'exit 1'
make_repo "$PASSING" 'exit 0'

run_case() {
  local expect="$1" label="$2" active="$3" cwd="$4"
  local out code got
  out=$(jq -n --argjson a "$active" --arg d "$cwd" '{stop_hook_active: $a, cwd: $d}' \
    | CLAUDE_PROJECT_DIR="$WORK/unrelated" bash "$HOOK" 2>/dev/null)
  code=$?
  got="pass"
  [ "$code" -eq 2 ] && got="block"
  if [ "$got" = "$expect" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL [expect=$expect got=$got]: $label"
  fi
  if [ -n "$out" ]; then
    FAIL=$((FAIL + 1))
    echo "FAIL [stdout must be empty]: $label"
  fi
}

# --- clean tree: nothing to verify ---
run_case pass "clean tree skips" false "$FAILING"

# --- dirty tree, failing tests: block ---
echo x > "$FAILING/dirty.txt"
run_case block "failing tests block" false "$FAILING"

# --- dirty tree, failing tests, already continuing from a stop hook: pass ---
run_case pass "stop_hook_active guard" true "$FAILING"

# --- dirty tree, passing tests: pass ---
echo x > "$PASSING/dirty.txt"
run_case pass "passing tests" false "$PASSING"

# --- cwd comes from hook input, not CLAUDE_PROJECT_DIR ---
mkdir -p "$WORK/unrelated"
run_case block "cwd from input wins over CLAUDE_PROJECT_DIR" false "$FAILING"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
