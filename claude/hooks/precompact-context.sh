#!/bin/bash
# PreCompact hook: Inject current work state as additionalContext before compaction.
# Ensures git status, recent changes, and branch info survive the compaction summary.

set -uo pipefail

CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Gather state
BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "unknown")
GIT_STATUS=$(git -C "$CWD" status --short 2>/dev/null | head -20)
GIT_LOG=$(git -C "$CWD" log --oneline -5 2>/dev/null)

CONTEXT="Current work state (preserve in compaction summary):
Branch: $BRANCH"

if [ -n "$GIT_STATUS" ]; then
  CONTEXT="$CONTEXT
Uncommitted changes:
$GIT_STATUS"
fi

if [ -n "$GIT_LOG" ]; then
  CONTEXT="$CONTEXT
Recent commits:
$GIT_LOG"
fi

jq -Rn --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "PreCompact",
    additionalContext: $ctx
  }
}'

exit 0
