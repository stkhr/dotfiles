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

# Extract the FINAL assistant message only, not a rolling window: a claim
# from an older turn ("pushしました", true at the time) must not be re-checked
# against the current repo state, or an honest follow-up ("pushはまだ") gets
# blocked. Parse line-by-line with fromjson? so a truncated/partial line can
# never break the whole parse; -c keeps each message on one line (newlines
# escaped) so `tail -n 1` selects whole messages, then jq -r unescapes.
LAST_MSG=$(tail -n 400 "$TRANSCRIPT" 2>/dev/null \
  | jq -Rc 'fromjson? | select(.type == "assistant") | [(.message.content // [])[]? | select(.type == "text") | .text] | join("\n") | select(length > 0)' 2>/dev/null \
  | tail -n 1 \
  | jq -r '.' 2>/dev/null)

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

# --- Verify PR claim: the claimed PR exists ---
# Prefer a PR number from a URL in the message: it stays correct even when the
# claim is about another branch (e.g. worktree cleanup switched back to main).
# Fall back to the current branch's PR only when no number is present.
if echo "$CLAIM" | grep -q 'PR作成'; then
  if command -v gh >/dev/null 2>&1 && (cd "$CWD" && ${TO:+$TO 10} gh auth status >/dev/null 2>&1); then
    PR_NUM=$(echo "$LAST_MSG" | grep -oE '/pull/[0-9]+' | tail -n 1 | grep -oE '[0-9]+')
    if [ -n "$PR_NUM" ]; then
      if ! (cd "$CWD" && ${TO:+$TO 15} gh pr view "$PR_NUM" --json url >/dev/null 2>&1); then
        PROBLEMS="${PROBLEMS}- PR #${PR_NUM} を作成したと報告したが、gh で見つからない\n"
      fi
    elif ! (cd "$CWD" && ${TO:+$TO 15} gh pr view --json url >/dev/null 2>&1); then
      PROBLEMS="${PROBLEMS}- PRを作成したと報告したが、現ブランチ($BRANCH)に対応するPRが gh で見つからない\n"
    fi
  fi
  # gh unavailable/unauthenticated -> cannot verify, skip.
fi

[ -z "$PROBLEMS" ] && exit 0

REASON=$(printf '完了報告の事実性チェックに失敗しました。直近の報告(%s)と実態が矛盾しています:\n%b実際に実行するか、報告を「未完了/未確認」に訂正してください。検証: git status -sb / gh pr view' "$CLAIM" "$PROBLEMS")

# Exit 2 blocks the stop and feeds stderr back to Claude as the correction
# instruction. Do NOT emit JSON here: stdout is only parsed on exit 0, and
# "continue: false" would halt the session instead of forcing a correction.
echo "$REASON" >&2
exit 2
