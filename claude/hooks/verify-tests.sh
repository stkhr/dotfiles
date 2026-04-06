#!/bin/bash
# Stop Completion Gate: Verify tests pass before the agent declares completion.
# Only runs if there are uncommitted file changes (agent wrote code this session).
# Blocks completion (exit 2) if tests fail.
# Supports: Node.js (npm test), Go (go test), Python (pytest), Rust (cargo test), Terraform (terraform validate/test)

set -uo pipefail

CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Only run if there are file changes (staged or modified)
if ! git -C "$CWD" rev-parse HEAD &>/dev/null 2>&1; then
  exit 0  # No git repo or no commits yet
fi
CHANGES=$(git -C "$CWD" status --porcelain 2>/dev/null | grep -E '^( M|M |MM|A |AM| A|\?\?)' | wc -l | tr -d ' ')
[ "$CHANGES" -eq 0 ] && exit 0

# Detect test runner
TEST_CMD=""
TEST_TYPE=""

if [ -f "$CWD/package.json" ]; then
  TEST_SCRIPT=$(jq -r '.scripts.test // empty' "$CWD/package.json" 2>/dev/null)
  PLACEHOLDER='echo "Error: no test specified" && exit 1'
  if [ -n "$TEST_SCRIPT" ] && [ "$TEST_SCRIPT" != "$PLACEHOLDER" ]; then
    PKG_MGR="npm"
    [ -f "$CWD/pnpm-lock.yaml" ] && PKG_MGR="pnpm"
    [ -f "$CWD/yarn.lock" ] && PKG_MGR="yarn"
    [ -f "$CWD/bun.lockb" ] && PKG_MGR="bun"
    TEST_CMD="cd '$CWD' && $PKG_MGR test"
    TEST_TYPE="$PKG_MGR"
  fi
elif [ -f "$CWD/go.mod" ] && command -v go &>/dev/null; then
  TEST_CMD="cd '$CWD' && go test ./... -count=1 -timeout 60s"
  TEST_TYPE="go"
elif command -v python3 &>/dev/null; then
  if [ -f "$CWD/pytest.ini" ] || [ -f "$CWD/setup.cfg" ] || \
     ([ -f "$CWD/pyproject.toml" ] && grep -q '\[tool\.pytest' "$CWD/pyproject.toml" 2>/dev/null); then
    TEST_CMD="cd '$CWD' && python3 -m pytest --tb=short -q 2>&1"
    TEST_TYPE="pytest"
  fi
elif [ -f "$CWD/Cargo.toml" ] && command -v cargo &>/dev/null; then
  TEST_CMD="cd '$CWD' && cargo test 2>&1"
  TEST_TYPE="cargo"
elif ls "$CWD"/*.tf &>/dev/null 2>&1 && command -v terraform &>/dev/null; then
  # Use 'terraform test' if .tftest.hcl files exist (Terraform 1.6+), otherwise validate
  if ls "$CWD"/*.tftest.hcl &>/dev/null 2>&1 || ls "$CWD"/tests/*.tftest.hcl &>/dev/null 2>&1; then
    TEST_CMD="cd '$CWD' && terraform test 2>&1"
    TEST_TYPE="terraform test"
  else
    TEST_CMD="cd '$CWD' && terraform validate 2>&1"
    TEST_TYPE="terraform validate"
  fi
fi

# No recognized test runner - pass through
[ -z "$TEST_CMD" ] && exit 0

# Run tests with 90s timeout (use gtimeout on macOS if available, else run without timeout)
if command -v timeout &>/dev/null; then
  TIMEOUT_CMD="timeout 90"
elif command -v gtimeout &>/dev/null; then
  TIMEOUT_CMD="gtimeout 90"
else
  TIMEOUT_CMD=""
fi
OUTPUT=$($TIMEOUT_CMD bash -c "$TEST_CMD" 2>&1 | tail -30)
EXIT_CODE=$?

[ "$EXIT_CODE" -eq 0 ] && exit 0

# Tests failed - block completion and inject context
echo "Tests failing ($TEST_TYPE) - fix before completing:" >&2
echo "$OUTPUT" >&2

jq -Rn --arg msg "$OUTPUT" --arg type "$TEST_TYPE" '{
  continue: false,
  stopReason: ("Tests failing (" + $type + ") - please fix before completing"),
  hookSpecificOutput: {
    hookEventName: "Stop",
    additionalContext: ("Tests are failing. Fix these before declaring completion:\n" + $msg)
  }
}'

exit 2
