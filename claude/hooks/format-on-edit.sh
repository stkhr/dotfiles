#!/bin/bash
# PostToolUse (Edit|Write): 編集されたファイルを言語別フォーマッタで整形する。
# フォーマッタ未導入・整形失敗は無視する（lint-feedback.sh が品質面を担当）。

set -uo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[ -z "$FILE" ] || [ ! -f "$FILE" ] && exit 0

case "$FILE" in
  *.ts|*.tsx|*.js|*.jsx|*.json|*.md)
    command -v prettier &>/dev/null && prettier --write "$FILE" 2>/dev/null
    ;;
  *.py)
    command -v black &>/dev/null && black -q "$FILE" 2>/dev/null
    ;;
  *.go)
    command -v gofmt &>/dev/null && gofmt -w "$FILE" 2>/dev/null
    ;;
esac

exit 0
