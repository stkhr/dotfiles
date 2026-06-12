#!/bin/bash
# Stop hook: Verify completion claims against reality.
# If the agent's recent message claims a PR/push was completed but git/gh show
# it does not actually exist, block the stop (exit 2) and force correction.
#
# Scope: PR-creation and git-push claims only (cleanly verifiable, high-value).
# Passes through (exit 0) when: no claim detected, not a git repo, gh
# unavailable/unauthenticated, verification is inconclusive (e.g. ls-remote
# fails), or already inside a stop-hook continuation (loop guard).

set -uo pipefail

# Portable timeout wrapper: coreutils `timeout`, macOS/brew `gtimeout`, or none.
# Used as ${TO:+$TO <secs>} so it expands to nothing when neither is present
# (the command then runs without a timeout rather than failing with not-found).
if command -v timeout >/dev/null 2>&1; then TO=timeout
elif command -v gtimeout >/dev/null 2>&1; then TO=gtimeout
else TO=""; fi

INPUT=$(cat)

# Loop guard: never re-block within a stop-hook-triggered continuation.
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$STOP_ACTIVE" = "true" ] && exit 0

TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
CWD="${CWD:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"

if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then exit 0; fi

# Must be inside a git repo to verify anything.
git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Extract recent assistant text from the transcript JSONL. Parse line-by-line
# with fromjson? so a truncated/partial line can never break the whole parse.
LAST_MSG=$(tail -n 400 "$TRANSCRIPT" 2>/dev/null \
  | jq -Rr 'fromjson? | select(.type == "assistant") | (.message.content // [])[]? | select(.type == "text") | .text' 2>/dev/null \
  | tail -n 60)

[ -z "$LAST_MSG" ] && exit 0

# Detect completion/past-tense claims only (ignore "作成します" intentions).
CLAIM=""
if echo "$LAST_MSG" | grep -qE 'PR.{0,15}作成しました|プルリクエスト.{0,15}作成しました|PR.{0,15}作成済'; then
  CLAIM="PR作成"
fi
if echo "$LAST_MSG" | grep -qE 'pushしました|プッシュしました|push.{0,4}(完了|成功)'; then
  CLAIM="${CLAIM:+$CLAIM / }push"
fi

[ -z "$CLAIM" ] && exit 0

BRANCH=$(git -C "$CWD" symbolic-ref --short HEAD 2>/dev/null || true)
# Detached HEAD: no branch name to verify against -> cannot verify, skip.
[ -z "$BRANCH" ] && exit 0
PROBLEMS=""

# --- Verify push claim: remote has this branch at the local HEAD ---
# (Assumes the claim is about the currently checked-out branch.)
if echo "$CLAIM" | grep -q 'push'; then
  if LSREMOTE=$(cd "$CWD" && ${TO:+$TO 15} git ls-remote --heads origin "$BRANCH" 2>/dev/null); then
    REMOTE_HASH=$(echo "$LSREMOTE" | awk 'NR==1{print $1}')
    LOCAL_HASH=$(git -C "$CWD" rev-parse HEAD 2>/dev/null)
    if [ -z "$REMOTE_HASH" ]; then
      PROBLEMS="${PROBLEMS}- pushしたと報告したが、リモートに $BRANCH が存在しない\n"
    elif [ "$REMOTE_HASH" != "$LOCAL_HASH" ]; then
      PROBLEMS="${PROBLEMS}- pushしたと報告したが、リモートの $BRANCH がローカルHEADと一致しない（未pushのコミットがある）\n"
    fi
  fi
  # ls-remote failed (network/no remote) -> inconclusive, skip.
fi

# --- Verify PR claim: an open PR exists for the current branch ---
if echo "$CLAIM" | grep -q 'PR作成'; then
  if command -v gh >/dev/null 2>&1 && (cd "$CWD" && ${TO:+$TO 10} gh auth status >/dev/null 2>&1); then
    if ! (cd "$CWD" && ${TO:+$TO 15} gh pr view --json url >/dev/null 2>&1); then
      PROBLEMS="${PROBLEMS}- PRを作成したと報告したが、現ブランチ($BRANCH)に対応するPRが gh で見つからない\n"
    fi
  fi
  # gh unavailable/unauthenticated -> cannot verify, skip.
fi

[ -z "$PROBLEMS" ] && exit 0

REASON=$(printf '完了報告の事実性チェックに失敗しました。直近の報告(%s)と実態が矛盾しています:\n%b実際に実行するか、報告を「未完了/未確認」に訂正してください。検証: git status -sb / gh pr view' "$CLAIM" "$PROBLEMS")

echo "$REASON" >&2

jq -Rn --arg msg "$REASON" '{
  continue: false,
  stopReason: "完了報告と実態が矛盾しています。実行するか訂正してください。",
  hookSpecificOutput: {
    hookEventName: "Stop",
    additionalContext: $msg
  }
}'

exit 2
