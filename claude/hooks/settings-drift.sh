#!/usr/bin/env bash
# SessionStart hook: report uncommitted drift in the dotfiles-managed
# settings.json (e.g. /model writes, installer reformatting), so the session
# does not rediscover the "unrelated diff" mid-task. stdout becomes session
# context. All failure modes exit 0 to avoid blocking session start.

set -uo pipefail

SETTINGS="$HOME/.claude/settings.json"
[ -L "$SETTINGS" ] || exit 0

REAL=$(readlink "$SETTINGS" 2>/dev/null) || exit 0
case "$REAL" in
  /*) : ;;
  *) REAL="$HOME/.claude/$REAL" ;;
esac
[ -f "$REAL" ] || exit 0

REPO_DIR=$(cd "$(dirname "$REAL")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$REPO_DIR" ] || exit 0
REL="${REAL#"$REPO_DIR"/}"

# diff against HEAD so staged-but-uncommitted drift is also caught.
# Exit 1 means drift; anything else is a git failure and stays silent.
git -C "$REPO_DIR" diff --quiet HEAD -- "$REL" 2>/dev/null
case $? in
  1) ;;
  *) exit 0 ;;
esac

SUMMARY=$(git -C "$REPO_DIR" diff --unified=0 HEAD -- "$REL" 2>/dev/null \
  | grep -E '^[+-][^+-]' | head -n 6 | tr -s '[:space:]' ' ' | cut -c 1-300)
echo "[settings-drift] $REL に未コミット差分があります: ${SUMMARY:-（要約取得失敗、git diff で確認）}"
exit 0
