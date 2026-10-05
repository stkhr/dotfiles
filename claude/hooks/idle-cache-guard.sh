#!/bin/bash
# UserPromptSubmit hook: hold a typed prompt once when a large session has sat idle past the prompt cache TTL.

set -uo pipefail

IDLE_SECONDS=3600
MIN_CONTEXT_TOKENS=300000

INPUT=$(cat)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
STATE_DIR=$(printf '%s' "$INPUT" | jq -r '.scratchpad_dir // empty' 2>/dev/null)

# The hook input carries no prompt origin, so automated turns are told apart by their text.
case "$PROMPT" in
  /* | "<"* | "Another Claude session sent a message:"*) exit 0 ;;
esac

[ -f "$TRANSCRIPT" ] || exit 0

read -r LAST_TS IDLE CONTEXT <<EOF
$(tail -n 500 "$TRANSCRIPT" | jq -rnR '
  [inputs | fromjson?
   | select((.type == "assistant" and .message.usage != null and .message.model != "<synthetic>")
       or .subtype == "compact_boundary")]
  | last // empty
  | select(.type == "assistant" and .entrypoint == "cli")
  | .message.usage as $u
  | [.timestamp,
     (now - (.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) | floor),
     (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0))]
  | @tsv' 2>/dev/null)
EOF

[ -n "${LAST_TS:-}" ] || exit 0
if [ "$IDLE" -lt "$IDLE_SECONDS" ] || [ "$CONTEXT" -lt "$MIN_CONTEXT_TOKENS" ]; then
  exit 0
fi

# Scheduled fires reach this hook looking like typed prompts, so a session that schedules anything is never held.
SCHEDULED=$(grep -E 'scheduled_task_fire|CronCreate|ScheduleWakeup' "$TRANSCRIPT" | jq -nR '
  [inputs | fromjson?
   | select(.subtype == "scheduled_task_fire"
       or (.type == "assistant"
           and any(.message.content[]?; .type == "tool_use" and (.name == "CronCreate" or .name == "ScheduleWakeup"))))]
  | length > 0' 2>/dev/null)
if [ "$SCHEDULED" = "true" ]; then
  exit 0
fi

# macOS tmp_cleaner can delete the scratchpad of a session left open for days.
[ -d "$STATE_DIR" ] || STATE_DIR=""
MARKER="${STATE_DIR:-${TMPDIR:-/tmp}}/idle-cache-guard-${SESSION_ID}"
if [ "$(cat "$MARKER" 2>/dev/null)" = "$LAST_TS" ]; then
  exit 0
fi
{ printf '%s' "$LAST_TS" > "$MARKER"; } 2>/dev/null || exit 0

if [ "$IDLE" -ge 172800 ]; then
  ELAPSED="$((IDLE / 86400)) 日"
else
  ELAPSED="$((IDLE / 3600)) 時間"
fi

REASON="前回の応答から約 ${ELAPSED}経ち、プロンプトキャッシュが切れています。このまま送るとコンテキスト約 $((CONTEXT / 1000))k tokens をキャッシュに書き直します。
/clear で新しく始めるか、/compact で要約してから続けてください(/compact も履歴全体を1回読み直します)。
このまま続ける場合は、同じ内容をもう一度送信してください。"

jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'
exit 0
