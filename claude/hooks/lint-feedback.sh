#!/bin/bash
# PostToolUse Quality Loop: Run linter after file edits and feed errors back to the model.
# Returns lint errors as additionalContext so the agent can self-correct immediately.
# Supports: TypeScript/JS (oxlint), Python (ruff), Go (golangci-lint), Rust (cargo clippy), Terraform (tflint)

set -uo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
# cwd from the hook input follows EnterWorktree; CLAUDE_PROJECT_DIR stays at the launch root.
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
CWD="${CWD:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"

# Exit early if no file or file doesn't exist
[ -z "$FILE" ] || [ ! -f "$FILE" ] && exit 0

# Find linter: check project-local (node_modules/.bin) before global
find_linter() {
  local name="$1"
  local cwd="$CWD"
  if [ -x "$cwd/node_modules/.bin/$name" ]; then
    echo "$cwd/node_modules/.bin/$name"
  elif command -v "$name" &>/dev/null; then
    echo "$name"
  else
    echo ""
  fi
}

DIAG=""

case "$FILE" in
  *.ts|*.tsx|*.js|*.jsx|*.mts|*.mjs|*.cjs)
    LINTER=$(find_linter "oxlint")
    if [ -n "$LINTER" ]; then
      DIAG=$("$LINTER" "$FILE" 2>&1 | head -30) || true
    fi
    ;;
  *.py)
    if command -v ruff &>/dev/null; then
      DIAG=$(ruff check "$FILE" 2>&1 | head -30) || true
    fi
    ;;
  *.go)
    if command -v golangci-lint &>/dev/null; then
      DIAG=$(golangci-lint run "$FILE" 2>&1 | head -30) || true
    fi
    ;;
  *.rs)
    if command -v cargo &>/dev/null; then
      # cargo clippy runs project-wide; the workspace root is the hook cwd
      CARGO_ROOT="$CWD"
      DIAG=$(cargo clippy --manifest-path "$CARGO_ROOT/Cargo.toml" 2>&1 | grep -E '^error|^warning' | head -30) || true
    fi
    ;;
  *.tf|*.tfvars)
    if command -v tflint &>/dev/null; then
      DIAG=$(tflint --chdir "$(dirname "$FILE")" 2>&1 | head -30) || true
    fi
    ;;
esac

# Only inject context if there are actual errors or warnings
[ -z "$DIAG" ] && exit 0
echo "$DIAG" | grep -qiE '(error|warning|warn:|\berror\b)' || exit 0

jq -Rn --arg msg "$DIAG" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("Lint errors found - fix before continuing:\n" + $msg)
  }
}'

exit 0
