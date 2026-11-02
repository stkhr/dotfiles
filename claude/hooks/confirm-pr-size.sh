#!/bin/bash
# PreToolUse (Bash): warn when `gh pr create` would open a PR that changes
# more than PR_SIZE_LIMIT_LINES (default 500) lines against its base.
# The command is not blocked: a systemMessage shows the numbers to the
# user and additionalContext tells Claude to offer a split once the PR
# URL exists, so the user decides with the diff in front of them.
# Binaries, lockfiles and snapshots are not counted.
# Non-matching or unparsable input passes through silently so a gate bug
# never stalls normal work.

set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

FLAT="$(printf '%s' "$COMMAND" | tr '\n' ' ') "
# FLAT keeps quotes so a quoted cd path survives; everything else matches on STRIPPED.
STRIPPED=$(echo "$FLAT" | sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g")
CREATE_RE='(^|[[:space:]]|&&|\||;)gh[[:space:]]+pr[[:space:]]+create([[:space:];&|]|$)'
CREATE_SEG=$(printf '%s\n' "$STRIPPED" | tr ';&|' '\n' \
  | grep -E '(^|[[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)' | head -n 1)
[ -n "$CREATE_SEG" ] || exit 0

LIMIT="${PR_SIZE_LIMIT_LINES:-500}"
case "$LIMIT" in
  ''|*[!0-9]*) LIMIT=500 ;;
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

# A --base inside a PR body or an earlier command must not pick the comparison branch.
BASE=$(echo "$CREATE_SEG" | grep -oE '(^|[[:space:]])(--base|-B)([[:space:]]+|=)[^[:space:]]+' | head -n 1 \
  | sed -E 's/^[[:space:]]*(--base|-B)([[:space:]]+|=)//')
case "$BASE" in
  -*) BASE="" ;;
esac
BASE_REF=""
if [ -n "$BASE" ]; then
  BASE_REF=$(resolve_base_ref "$BASE")
fi
if [ -z "$BASE_REF" ]; then
  BASE_REF=$(git -C "$DIR" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
fi
if [ -z "$BASE_REF" ]; then
  for name in main master; do
    BASE_REF=$(resolve_base_ref "$name")
    [ -n "$BASE_REF" ] && break
  done
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

SUMMARY="PR の変更量 ${LINES} 行 / ${FILES} ファイルが閾値 ${LIMIT} 行を超えています(base ${BASE_REF})。"
jq -n \
  --arg msg "${SUMMARY}分割するかは Draft PR の diff を見て決めてください。" \
  --arg ctx "${SUMMARY}作成後、PR URL と合わせて実測と分割案(そのまま 1 本 / gh-stack で分割)を要判断に出してください。headless 自走時は gh pr edit <番号> --body-file で本文末尾に書きます。" '{
  systemMessage: $msg,
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: $ctx
  }
}'
exit 0
