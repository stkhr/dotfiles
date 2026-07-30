#!/bin/bash
# Prevent git commit on main/master branch.
# Used as a Claude Code PreToolUse hook for the Bash tool.
# Exit code 2 blocks the tool execution and shows stderr to Claude.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only check git commit commands (with or without an interleaved -C <path>)
if ! echo "$COMMAND" | grep -qE '(^|\s|&&|\||\;)git\s+(-C\s+("[^"]*"|'\''[^'\'']*'\''|\S+)\s+)?commit(\s|$)'; then
  exit 0
fi

# A branch created earlier in the same command means the commit lands on it,
# not on the branch checked out at judgment time (compound-command false positive).
if echo "$COMMAND" | grep -qE 'git\s+(-C\s+\S+\s+)?(checkout\s+-b|switch\s+(-c|--create))(\s|$)'; then
  exit 0
fi

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
CWD="${CWD:-${CLAUDE_PROJECT_DIR:-}}"

# The repo being committed to is not always the session cwd (cross-repo
# worktrees): prefer the commit's own `git -C <path>`, then a `cd <path>`
# prefix, and only then the session cwd.
TARGET=""
GIT_C=$(echo "$COMMAND" | grep -oE 'git\s+-C\s+("[^"]*"|'\''[^'\'']*'\''|\S+)\s+commit' | head -n 1 || true)
if [ -n "$GIT_C" ]; then
  TARGET=$(echo "$GIT_C" | sed -E 's/^git[[:space:]]+-C[[:space:]]+//; s/[[:space:]]+commit$//')
else
  CD_SEG=$(echo "$COMMAND" | grep -oE '(^|[;&|]\s*)cd\s+("[^"]*"|'\''[^'\'']*'\''|[^[:space:];&|]+)' | tail -n 1 || true)
  if [ -n "$CD_SEG" ]; then
    TARGET=$(echo "$CD_SEG" | sed -E 's/^([;&|]*[[:space:]]*)?cd[[:space:]]+//')
  fi
fi
TARGET=$(echo "$TARGET" | sed -E 's/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/')

case "$TARGET" in
  "") DIR="$CWD" ;;
  /*) DIR="$TARGET" ;;
  "~"*) DIR="${TARGET/#\~/$HOME}" ;;
  *) DIR="${CWD:+$CWD/}$TARGET" ;;
esac

[ -z "$DIR" ] && exit 0

BRANCH=$(git -C "$DIR" symbolic-ref --short HEAD 2>/dev/null || true)

# Unresolvable target (bad path parse, deleted dir): fall back to the session
# cwd judgment rather than silently passing a possible main commit through.
if [ -z "$BRANCH" ] && [ "$DIR" != "$CWD" ] && [ -n "$CWD" ]; then
  BRANCH=$(git -C "$CWD" symbolic-ref --short HEAD 2>/dev/null || true)
fi

if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  echo "BLOCKED: Direct commit to '$BRANCH' branch is not allowed. Create a feature branch first." >&2
  exit 2
fi

exit 0
