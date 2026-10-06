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

SID_A="aaaaaaaa-1111-2222-3333-444444444444"
SID_B="bbbbbbbb-1111-2222-3333-444444444444"

message() {
  jq -nc --arg ty "$1" --arg t "$2" --arg c "$3" '{type:$ty, isSidechain:false,
    cwd:$c, timestamp:"2026-07-30T04:00:00.000Z",
    message:{content:[{type:"text", text:$t}]}}'
}

run_hook() {
  jq -n --arg s "$1" --arg tp "$2" --arg d "$3" --arg m "${4:-}" \
    '{session_id:$s, transcript_path:$tp, cwd:$d}
     + (if $m == "" then {} else {last_assistant_message:$m} end)' | bash "$HOOK"
}

files_named() { find "$OBSIDIAN_VAULT" -type f -name "$1" | wc -l | tr -d ' '; }

check() {
  local label="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label (want=$want got=$got)"
  fi
}

TA="$WORK/a.jsonl"
message user 'first question' "$WORK/proj" > "$TA"
message assistant 'first answer' "$WORK/proj" >> "$TA"
run_hook "$SID_A" "$TA" "$WORK/proj"
message user 'second question' "$WORK/wt" >> "$TA"
message assistant 'second answer' "$WORK/wt" >> "$TA"
run_hook "$SID_A" "$TA" "$WORK/wt"

FILE_A=$(find "$OBSIDIAN_VAULT" -type f -name 'proj--aaaaaaaa.md')
check "session file is named from the starting cwd and sid8" "1" "$(files_named 'proj--aaaaaaaa.md')"
check "moving into a worktree does not create another file" "1" "$(find "$OBSIDIAN_VAULT" -type f | wc -l | tr -d ' ')"
check "rerun overwrites instead of appending a second block" "1" "$(grep -c '^<!-- session: ' "$FILE_A")"
check "rerun keeps the latest transcript" "1" "$(grep -c '^second answer$' "$FILE_A")"

TB="$WORK/b.jsonl"
message user 'other tab question' "$WORK/proj" > "$TB"
run_hook "$SID_B" "$TB" "$WORK/proj"
check "another session in the same repo gets its own file" "1" "$(files_named 'proj--bbbbbbbb.md')"
check "another session does not write into the first session's file" "0" "$(grep -c 'other tab question' "$FILE_A")"

run_hook "$SID_A" "$TA" "$WORK/wt" 'final conclusion ghp_AbCdEfGhIjKlMnOpQrStUvWxYz0123456789'
check "missing final message is appended as the last block" "### Assistant|final conclusion [MASKED_GITHUB_TOKEN]" \
  "$(grep -v -e '^$' -e '^---$' "$FILE_A" | tail -n 2 | paste -sd '|' -)"
check "appended final message is masked" "0" "$(grep -c 'ghp_AbCdEfGhIjKlMnOp' "$FILE_A")"

run_hook "$SID_A" "$TA" "$WORK/wt" 'second answer'
check "final message already in the transcript is not duplicated" "1" "$(grep -c '^second answer$' "$FILE_A")"

TC="$WORK/c.jsonl"
message user 'first task' "$WORK/proj" > "$TC"
message assistant 'Done.' "$WORK/proj" >> "$TC"
message user 'second task' "$WORK/proj" >> "$TC"
run_hook "cccccccc-1111" "$TC" "$WORK/proj" 'Done.'
FILE_C=$(find "$OBSIDIAN_VAULT" -type f -name 'proj--cccccccc.md')
check "final message equal to an earlier turn's reply is still appended" "### User|second task|### Assistant|Done." \
  "$(grep -v -e '^$' -e '^---$' "$FILE_C" | tail -n 4 | paste -sd '|' -)"

TD="$WORK/d.jsonl"
message user 'explain' "$WORK/proj" > "$TD"
for part in 'part one.' 'part two.'; do
  jq -nc --arg t "$part" --arg c "$WORK/proj" '{type:"assistant", isSidechain:false, cwd:$c,
    timestamp:"2026-07-30T04:00:00.000Z", message:{id:"msg_split", content:[{type:"text", text:$t}]}}' >> "$TD"
done
run_hook "dddddddd-1111" "$TD" "$WORK/proj" 'part one.part two.'
FILE_D=$(find "$OBSIDIAN_VAULT" -type f -name 'proj--dddddddd.md')
check "final message split across transcript lines is not duplicated" "1" "$(grep -c 'part two' "$FILE_D")"

TE="$WORK/e.jsonl"
message user 'question' "$WORK/03_プロジェクト進捗・戦略" > "$TE"
run_hook "eeeeeeee-1111" "$TE" "$WORK/03_プロジェクト進捗・戦略"
check "non-ASCII letters in the project name are kept" "1" "$(files_named '03_プロジェクト進捗_戦略--eeeeeeee.md')"

TF="$WORK/f.jsonl"
message user 'question' "$WORK/Obsidian Vault" > "$TF"
run_hook "ffffffff-1111" "$TF" "$WORK/Obsidian Vault"
check "spaces in the project name become underscores" "1" "$(files_named 'Obsidian_Vault--ffffffff.md')"

TG="$WORK/g.jsonl"
message user 'question' "$WORK/a❤️b" > "$TG"
run_hook "gggggggg-1111" "$TG" "$WORK/a❤️b"
check "marks left over from a replaced character are dropped" "1" "$(files_named 'a_b--gggggggg.md')"

NFD_PU=$(printf '\xe3\x83\x95\xe3\x82\x9a')
TH="$WORK/h.jsonl"
message user 'question' "$WORK/$NFD_PU" > "$TH"
run_hook "hhhhhhhh-1111" "$TH" "$WORK/$NFD_PU"
check "decomposed kana keep their combining mark" "1" "$(files_named "$NFD_PU--hhhhhhhh.md")"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
