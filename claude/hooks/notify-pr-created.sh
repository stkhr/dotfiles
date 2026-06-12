#!/bin/bash
# PostToolUse (Bash): gh pr create の出力から PR URL を拾い、systemMessage で通知する。

set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

echo "$COMMAND" | grep -q 'gh pr create' || exit 0

URL=$(echo "$INPUT" | jq -r '.tool_response.stdout // ""' 2>/dev/null \
  | grep -oE 'https://github\.com/\S+' | head -1)

if [ -n "$URL" ]; then
  jq -n --arg msg "PR が作成されました: $URL" '{systemMessage: $msg}'
fi

exit 0
