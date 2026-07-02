#!/bin/bash
# PreToolUse (Bash): force a permission prompt ("ask") for hard-gated
# destructive / externally-visible operations (force push, --no-verify,
# branch deletion, gh pr close/merge/ready/comment/review, non-draft
# gh pr create). On detection: exit 0 + permissionDecision "ask"
# (confirmation, not a hard block). Non-matching or unparsable input
# passes through silently so a gate bug never stalls normal work.
#
# Quoted strings are stripped before matching so flags inside message
# bodies (--body "fix -d handling") neither trigger nor bypass the gate;
# the accepted cost is that a gated command fully wrapped in quotes
# (bash -c "git push -f") is not detected. Each ;/&/|-separated segment
# is evaluated independently so a flag from one command (rm -f) never
# attaches to another (git push).

set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

STRIPPED=$(echo "$COMMAND" | sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g")

REASONS=""
add_reason() {
  case "$REASONS" in
    *"$1"*) return ;;
  esac
  REASONS="${REASONS:+$REASONS / }$1"
}

GIT_PUSH_RE='(^|[[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push([[:space:]]|$)'
GIT_BRANCH_RE='(^|[[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+branch([[:space:]]|$)'

check_segment() {
  local seg="$1"

  if echo "$seg" | grep -qE "$GIT_PUSH_RE"; then
    # +refspec is force push by another spelling; " :ref" (empty source) is
    # a delete. "HEAD:main" has no space before ":" and stays untouched.
    if echo "$seg" | grep -qE '(^|[[:space:]])(--force|--force-with-lease(=[^[:space:]]*)?|-f)([[:space:]]|$)' \
      || echo "$seg" | grep -qE '[[:space:]]\+[^[:space:]]'; then
      add_reason "force push"
    fi
    if echo "$seg" | grep -qE '(^|[[:space:]])(--delete|-d)([[:space:]]|$)' \
      || echo "$seg" | grep -qE '[[:space:]]:[^[:space:]]'; then
      add_reason "リモートブランチ削除"
    fi
  fi

  if echo "$seg" | grep -qE '(^|[[:space:]])git[[:space:]]' \
    && echo "$seg" | grep -qE '(^|[[:space:]])--no-verify([[:space:]]|$)'; then
    add_reason "--no-verify による hook スキップ"
  fi

  if echo "$seg" | grep -qE "$GIT_BRANCH_RE" \
    && echo "$seg" | grep -qE '(^|[[:space:]])(-D|-d|--delete)([[:space:]]|$)'; then
    add_reason "ブランチ削除"
  fi

  if echo "$seg" | grep -qE '(^|[[:space:]])gh[[:space:]]+pr[[:space:]]+(close|merge|ready|comment|review)([[:space:]]|$)'; then
    add_reason "PR への外部影響操作 (close/merge/ready/comment/review)"
  fi

  # --draft=false must still ask; only --draft / --draft=true / -d are draft.
  if echo "$seg" | grep -qE '(^|[[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)' \
    && ! echo "$seg" | grep -qE '(^|[[:space:]])(--draft(=true)?|-d)([[:space:]]|$)'; then
    add_reason "非Draft PR の作成"
  fi
}

SEGMENTS=$(printf '%s\n' "$STRIPPED" | tr ';&|' '\n')
while IFS= read -r SEG; do
  [ -n "$SEG" ] && check_segment "$SEG"
done <<< "$SEGMENTS"

[ -z "$REASONS" ] && exit 0

jq -n --arg reason "$REASONS" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: ("ハードゲート対象の操作を検知: " + $reason + "。実行にはユーザー承認が必要です。")
  }
}'
exit 0
