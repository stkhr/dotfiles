#!/bin/bash
# Prevent git commit on main/master branch.
# Used as a Claude Code PreToolUse hook for the Bash tool.
# Exit code 2 blocks the tool execution and shows stderr to Claude.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only check git commit commands
if ! echo "$COMMAND" | grep -qE '(^|\s|&&|\||\;)git\s+commit(\s|$)'; then
  exit 0
fi

# Determine the working directory from hook input, fallback to CLAUDE_PROJECT_DIR
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
CWD="${CWD:-$CLAUDE_PROJECT_DIR}"

if [ -z "$CWD" ]; then
  exit 0
fi

BRANCH=$(git -C "$CWD" symbolic-ref --short HEAD 2>/dev/null || true)

if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  echo "BLOCKED: Direct commit to '$BRANCH' branch is not allowed. Create a feature branch first." >&2
  exit 2
fi

exit 0
