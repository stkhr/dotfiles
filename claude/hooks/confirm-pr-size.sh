#!/bin/bash
# PreToolUse (Bash): force a permission prompt ("ask") on `gh pr create`
# when the branch changes more than PR_SIZE_LIMIT_LINES (default 400)
# lines against its base, so an oversized PR is split or knowingly
# accepted instead of slipping past review. Binaries, lockfiles and
# snapshots are not counted. Unattended permission modes
# (bypassPermissions / dontAsk) pass through: nobody can answer the
# prompt, and a `-p` run would see the ask as a denial.
# Non-matching or unparsable input passes through silently so a gate bug
# never stalls normal work.

set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

FLAT="$(printf '%s' "$COMMAND" | tr '\n' ' ') "
STRIPPED=$(echo "$FLAT" | sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g")
CREATE_RE='(^|[[:space:]]|&&|\||;)gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'
echo "$STRIPPED" | grep -qE "$CREATE_RE" || exit 0

MODE=$(echo "$INPUT" | jq -r '.permission_mode // empty' 2>/dev/null)
case "$MODE" in
  bypassPermissions|dontAsk) exit 0 ;;
esac

LIMIT="${PR_SIZE_LIMIT_LINES:-400}"
case "$LIMIT" in
  ''|*[!0-9]*) LIMIT=400 ;;
esac

CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
CWD="${CWD:-${CLAUDE_PROJECT_DIR:-}}"

strip_quotes() {
  echo "$1" | sed -E "s/^\"(.*)\"$/\1/; s/^'(.*)'$/\1/"
}

# The last `cd <path>` before `gh pr create` decides which repo is measured.
Q_PATH="(\"[^\"]*\"|'[^']*'|[^[:space:]]+)"
PRE=$(echo "$FLAT" | sed -E "s/${CREATE_RE}.*//")
CD_SEG=$(echo "$PRE" | grep -oE "(^|[;&|][[:space:]]*)cd[[:space:]]+${Q_PATH}" | tail -n 1 || true)
DIR="$CWD"
if [ -n "$CD_SEG" ]; then
  TARGET=$(strip_quotes "$(echo "$CD_SEG" | sed -E "s/^([;&|]*[[:space:]]*)?cd[[:space:]]+//")")
  case "$TARGET" in
    /*) DIR="$TARGET" ;;
    "~"*) DIR="${TARGET/#\~/$HOME}" ;;
    *) DIR="${CWD:+$CWD/}$TARGET" ;;
  esac
fi
[ -n "$DIR" ] || exit 0
git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

resolve_base_ref() {
  local name="$1"
  if git -C "$DIR" rev-parse --verify -q "refs/remotes/origin/$name" >/dev/null 2>&1; then
    echo "origin/$name"
  elif git -C "$DIR" rev-parse --verify -q "refs/heads/$name" >/dev/null 2>&1; then
    echo "$name"
  fi
}

BASE=$(echo "$FLAT" | grep -oE '(^|[[:space:]])(--base|-B)([[:space:]]+|=)[^[:space:]]+' | head -n 1 \
  | sed -E 's/^[[:space:]]*(--base|-B)([[:space:]]+|=)//')
BASE_REF=""
if [ -n "$BASE" ]; then
  BASE_REF=$(resolve_base_ref "$(strip_quotes "$BASE")")
else
  BASE_REF=$(git -C "$DIR" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
  if [ -z "$BASE_REF" ]; then
    for name in main master; do
      BASE_REF=$(resolve_base_ref "$name")
      [ -n "$BASE_REF" ] && break
    done
  fi
fi
[ -n "$BASE_REF" ] || exit 0

NUMSTAT=$(git -C "$DIR" diff --numstat "$BASE_REF...HEAD" 2>/dev/null) || exit 0
[ -n "$NUMSTAT" ] || exit 0

COUNTS=$(printf '%s\n' "$NUMSTAT" | awk -F'\t' '
  $1 == "-" || $2 == "-" { next }
  $3 ~ /(^|\/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|go\.sum|Cargo\.lock|poetry\.lock|Gemfile\.lock|composer\.lock)$/ { next }
  $3 ~ /\.lock$/ { next }
  $3 ~ /(^|\/)__snapshots__\// { next }
  $3 ~ /\.snap$/ { next }
  { lines += $1 + $2; files++ }
  END { printf "%d %d\n", lines, files }')
LINES=${COUNTS% *}
FILES=${COUNTS#* }

[ "$LINES" -gt "$LIMIT" ] 2>/dev/null || exit 0

jq -n --arg reason "PR の変更量が閾値を超えています: ${LINES} 行 / ${FILES} ファイル(閾値 ${LIMIT} 行、base ${BASE_REF})。分割案(そのまま 1 本 / 分割)を要判断に出し、ユーザーが選んでから作成してください。無人実行は bypassPermissions / dontAsk で起動します。" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: $reason
  }
}'
exit 0
