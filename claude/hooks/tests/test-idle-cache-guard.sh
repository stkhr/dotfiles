#!/bin/bash
# Tests for idle-cache-guard.sh: a typed prompt into a large session idle past the cache TTL is held once.
# Usage: bash claude/hooks/tests/test-idle-cache-guard.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/idle-cache-guard.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# assistant <seconds_ago> <cache_read> <cache_creation> [entrypoint] [tool_name]
assistant() {
  jq -cn --argjson ago "$1" --argjson read "$2" --argjson create "$3" \
    --arg ep "${4:-cli}" --arg tool "${5:-}" '{
    type: "assistant",
    entrypoint: $ep,
    timestamp: ((now - $ago) | strftime("%Y-%m-%dT%H:%M:%S.000Z")),
    message: {
      id: "msg_\($ago)",
      role: "assistant",
      model: "claude-opus-5-5",
      content: (if $tool == "" then [{type: "text", text: "done"}]
                else [{type: "tool_use", id: "toolu_1", name: $tool, input: {}}] end),
      usage: {input_tokens: 3, cache_creation_input_tokens: $create,
              cache_read_input_tokens: $read, output_tokens: 120}
    }
  }'
}

system_record() {
  jq -cn --arg st "$1" '{type: "system", subtype: $st, entrypoint: "cli",
    timestamp: ((now - 7300) | strftime("%Y-%m-%dT%H:%M:%S.000Z"))}'
}

# run_hook <transcript> <prompt> <session_id> [scratchpad_dir]
run_hook() {
  jq -n --arg t "$1" --arg p "$2" --arg s "$3" --arg d "${4:-}" '{
    session_id: $s, transcript_path: $t, cwd: "/tmp",
    hook_event_name: "UserPromptSubmit", prompt: $p
  } + (if $d == "" then {} else {scratchpad_dir: $d} end)' | bash "$HOOK"
}

expect_block() {
  local label="$1" out="$2"
  if [ "$(printf '%s' "$out" | jq -r '.decision // empty' 2>/dev/null)" = "block" ] \
    && printf '%s' "$out" | jq -r '.reason' | grep -qF '/clear'; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL [expected block]: $label -> $out"
  fi
}

expect_pass() {
  local label="$1" out="$2"
  if [ -z "$out" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL [expected pass]: $label -> $out"
  fi
}

N=0
case_setup() {
  N=$((N + 1))
  T="$WORK/t$N.jsonl"
  D="$WORK/scratch$N"
  mkdir -p "$D"
  : > "$T"
  local line
  for line in "$@"; do
    printf '%s\n' "$line" >> "$T"
  done
}

case_setup "$(assistant 9000 300000 0)" "$(assistant 7200 450000 50000)"
expect_block "typed prompt after 2h idle on a 500k context" "$(run_hook "$T" "続きをお願い" s1 "$D")"
expect_pass "resubmitting the same prompt goes through" "$(run_hook "$T" "続きをお願い" s1 "$D")"
printf '%s\n' "$(assistant 4000 500000 0)" >> "$T"
expect_block "a newer response that is also stale is held again" "$(run_hook "$T" "次" s1 "$D")"

case_setup "$(assistant 7200 200000 150000)"
expect_block "context counts cache read plus cache creation" "$(run_hook "$T" "go" s2 "$D")"

case_setup "$(assistant 3000 500000 0)"
expect_pass "50 minutes idle is still within the cache TTL" "$(run_hook "$T" "go" s3 "$D")"

case_setup "$(assistant 7200 250000 0)"
expect_pass "a 250k context is not worth holding" "$(run_hook "$T" "go" s4 "$D")"

case_setup "$(assistant 7200 500000 0)"
expect_pass "slash commands go through" "$(run_hook "$T" "/compact" s5 "$D")"
expect_pass "background task notifications go through" \
  "$(run_hook "$T" "<task-notification>
<task-id>b1</task-id>
<status>completed</status>
</task-notification>" s5 "$D")"
expect_pass "messages from other sessions go through" \
  "$(run_hook "$T" 'Another Claude session sent a message: <agent-message from="a1">done</agent-message>' s5 "$D")"

case_setup "$(system_record scheduled_task_fire)" "$(assistant 7200 500000 0)"
expect_pass "sessions with scheduled task fires go through" "$(run_hook "$T" "WAF の定期チェック" s6 "$D")"

case_setup "$(assistant 9000 400000 0 cli CronCreate)" "$(assistant 7200 500000 0)"
expect_pass "sessions that created a cron go through" "$(run_hook "$T" "定期チェック" s7 "$D")"

case_setup "$(assistant 9000 400000 0 cli ScheduleWakeup)" "$(assistant 7200 500000 0)"
expect_pass "sessions that scheduled a wakeup go through" "$(run_hook "$T" "loop" s8 "$D")"

tools_loaded='{"type":"attachment","attachment":{"type":"prompt_snapshot","tools":[{"name":"CronCreate","description":"Schedule a prompt","schema":{"name":"CronCreate"}},{"name":"ScheduleWakeup","description":"Schedule when to resume","schema":{"name":"ScheduleWakeup"}}]}}'
deferred_listed='{"type":"attachment","attachment":{"type":"deferred_tools_delta","addedNames":["CronCreate","ScheduleWakeup"],"addedLines":["CronCreate","ScheduleWakeup"]}}'
case_setup "$tools_loaded" "$deferred_listed" "$(assistant 7200 500000 0)"
expect_block "scheduling tools that are only available do not exempt the session" "$(run_hook "$T" "go" s13 "$D")"

case_setup "$(assistant 7300 500000 0)" "$(system_record compact_boundary)"
expect_pass "a compaction after the last response goes through" "$(run_hook "$T" "go" s9 "$D")"

case_setup "$(assistant 7200 500000 0 sdk-py)"
expect_pass "non-CLI sessions go through" "$(run_hook "$T" "go" s10 "$D")"

expect_pass "a missing transcript goes through" "$(run_hook "$WORK/none.jsonl" "go" s11 "$D")"

case_setup "$(assistant 7200 500000 0)"
mkdir -p "$WORK/tmp"
expect_block "without scratchpad_dir the first prompt is held" "$(TMPDIR="$WORK/tmp" run_hook "$T" "go" s12)"
expect_pass "without scratchpad_dir the resubmit goes through" "$(TMPDIR="$WORK/tmp" run_hook "$T" "go" s12)"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
