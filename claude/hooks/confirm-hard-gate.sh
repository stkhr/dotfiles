#!/bin/bash
# PreToolUse (Bash): force a permission prompt ("ask") for hard-gated
# destructive / externally-visible operations (force push, --no-verify,
# branch deletion, gh pr close/merge/ready/comment/review, non-draft
# gh pr create). Detection is token-based grep, same style as the other
# hooks. On detection: exit 0 + permissionDecision "ask" (confirmation,
# not a hard block). Non-matching or unparsable input passes through
# silently so a gate bug never stalls normal work.

set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

REASONS=""
add_reason() {
  REASONS="${REASONS:+$REASONS / }$1"
}

GIT_PUSH_RE='(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push([[:space:]]|$)'
GIT_BRANCH_RE='(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+branch([[:space:]]|$)'

if echo "$COMMAND" | grep -qE "$GIT_PUSH_RE"; then
  if echo "$COMMAND" | grep -qE '(^|[[:space:]])(--force|--force-with-lease(=[^[:space:]]*)?|-f)([[:space:]]|$)'; then
    add_reason "force push"
  fi
  if echo "$COMMAND" | grep -qE '(^|[[:space:]])(--delete|-d)([[:space:]]|$)'; then
    add_reason "リモートブランチ削除"
  fi
fi

if echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])git[[:space:]]' \
  && echo "$COMMAND" | grep -qE '(^|[[:space:]])--no-verify([[:space:]]|$)'; then
  add_reason "--no-verify による hook スキップ"
fi

if echo "$COMMAND" | grep -qE "$GIT_BRANCH_RE" \
  && echo "$COMMAND" | grep -qE '(^|[[:space:]])(-D|-d|--delete)([[:space:]]|$)'; then
  add_reason "ブランチ削除"
fi

if echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+(close|merge|ready|comment|review)([[:space:]]|$)'; then
  add_reason "PR への外部影響操作 (close/merge/ready/comment/review)"
fi

if echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)' \
  && ! echo "$COMMAND" | grep -qE '(^|[[:space:]])(--draft|-d)([[:space:]]|$)'; then
  add_reason "非Draft PR の作成"
fi

[ -z "$REASONS" ] && exit 0

jq -n --arg reason "$REASONS" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: ("ハードゲート対象の操作を検知: " + $reason + "。実行にはユーザー承認が必要です。")
  }
}'
exit 0
