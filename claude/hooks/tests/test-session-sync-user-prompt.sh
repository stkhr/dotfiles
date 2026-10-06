#!/bin/bash
set -uo pipefail

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

HOOK="$(cd "$(dirname "$0")/.." && pwd)/session-sync.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export OBSIDIAN_VAULT="$WORK/vault"
mkdir -p "$OBSIDIAN_VAULT"

{
  jq -nc '{type:"user", isSidechain:false, timestamp:"2026-07-30T04:00:00.000Z",
    message:{content:"typed prompt as a plain string"}}'
  jq -nc '{type:"user", isSidechain:false, timestamp:"2026-07-30T04:01:00.000Z",
    message:{content:"<task-notification>\n<task-id>b1</task-id>\n<status>completed</status>\n</task-notification>"}}'
  jq -nc '{type:"user", isSidechain:false, timestamp:"2026-07-30T04:01:10.000Z",
    message:{content:"<bash-input>cat config.txt</bash-input>"}}'
  jq -nc '{type:"user", isSidechain:false, timestamp:"2026-07-30T04:01:20.000Z",
    message:{content:"<bash-stdout>PLACEHOLDER_PASSWORD=not-a-real-value</bash-stdout><bash-stderr>warning: plain</bash-stderr>"}}'
  jq -nc '{type:"user", isSidechain:false, isCompactSummary:true, timestamp:"2026-07-30T04:01:30.000Z",
    message:{content:"This session is being continued from a previous conversation."}}'
  jq -nc '{type:"assistant", isSidechain:false, timestamp:"2026-07-30T04:02:00.000Z",
    message:{content:[{type:"text", text:"answer"}]}}'
} > "$WORK/transcript.jsonl"

jq -n --arg tp "$WORK/transcript.jsonl" --arg d "$WORK/proj" \
  '{session_id:"cccccccc-1111", transcript_path:$tp, cwd:$d}' | bash "$HOOK"

OUT=$(find "$OBSIDIAN_VAULT" -name 'proj--cccccccc.md' -exec cat {} +)

check() {
  local label="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label (want=$want got=$got)"
  fi
}

check "plain string prompt is recorded under User" "### User|typed prompt as a plain string" \
  "$(printf '%s\n' "$OUT" | grep -v '^$' | grep -A1 '^### User$' | paste -sd '|' -)"
check "task notification is not recorded" "0" "$(printf '%s\n' "$OUT" | grep -c 'task-id')"
check "shell command run with ! is not recorded" "0" "$(printf '%s\n' "$OUT" | grep -c 'cat config.txt')"
check "shell command output is not recorded" "0" "$(printf '%s\n' "$OUT" | grep -c -e 'PLACEHOLDER_PASSWORD' -e 'warning: plain')"
check "compact summary is not recorded" "0" "$(printf '%s\n' "$OUT" | grep -c 'being continued')"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
