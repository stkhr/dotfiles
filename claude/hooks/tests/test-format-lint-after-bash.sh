#!/bin/bash
# Tests for format-lint-after-bash.sh: only files changed after the previous
# run are handed to format-on-edit.sh; the first run only sets the baseline.
# Usage: bash claude/hooks/tests/test-format-lint-after-bash.sh
set -uo pipefail

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

HOOK="$(cd "$(dirname "$0")/.." && pwd)/format-lint-after-bash.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export TMPDIR="$WORK/tmp"
mkdir -p "$TMPDIR"

# Stub gofmt that stamps the file so formatting is observable.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gofmt" <<'EOF'
#!/bin/bash
# usage: gofmt -w FILE
echo "// formatted" >> "$2"
EOF
chmod +x "$WORK/bin/gofmt"
export PATH="$WORK/bin:$PATH"

REPO="$WORK/repo"
git init -q -b main "$REPO"
printf 'package main\n' > "$REPO/old.go"
git -C "$REPO" add old.go
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m init

run_hook() {
  jq -n --arg d "$REPO" '{session_id: "sess-1", cwd: $d, tool_name: "Bash", tool_input: {command: "true"}}' \
    | bash "$HOOK"
}

check() {
  local label="$1" cond="$2"
  if eval "$cond"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label"
  fi
}

# --- first run: baseline only, pre-existing dirty file untouched ---
printf 'package main\n' > "$REPO/pre.go"
run_hook >/dev/null
check "first run does not format pre-existing changes" '! grep -q formatted "$REPO/pre.go"'

# --- a file changed after the baseline is formatted ---
sleep 1
printf 'package main\n' > "$REPO/new.go"
run_hook >/dev/null
check "new file formatted" 'grep -q formatted "$REPO/new.go"'
check "untouched dirty file still not formatted" '! grep -q formatted "$REPO/pre.go"'

# --- unchanged since last run: not formatted again ---
run_hook >/dev/null
check "not formatted twice" '[ "$(grep -c formatted "$REPO/new.go")" -eq 1 ]'

# --- tracked file modified after baseline ---
sleep 1
printf 'package main\n// edit\n' > "$REPO/old.go"
run_hook >/dev/null
check "modified tracked file formatted" 'grep -q formatted "$REPO/old.go"'

# --- outside a git repo: silent pass ---
OUT=$(jq -n --arg d "$WORK" '{session_id: "sess-2", cwd: $d, tool_name: "Bash", tool_input: {command: "true"}}' | bash "$HOOK")
if [ -z "$OUT" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: non-repo cwd passes silently"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
