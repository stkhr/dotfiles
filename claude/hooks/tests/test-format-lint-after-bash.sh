#!/bin/bash
# Tests for format-lint-after-bash.sh: only files changed since the previous
# run are handed to format-on-edit.sh / lint-feedback.sh, the first run only
# sets the baseline, lockfiles are skipped, and lint output is returned as
# additionalContext JSON.
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

# Stubs: formatters stamp the file once (real formatters leave an already
# formatted file untouched, so the stub must be idempotent too); the linter
# always reports an error so the JSON contract can be asserted.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gofmt" <<'EOF'
#!/bin/bash
# usage: gofmt -w FILE
grep -q '// formatted' "$2" || echo "// formatted" >> "$2"
EOF
cat > "$WORK/bin/prettier" <<'EOF'
#!/bin/bash
# usage: prettier --write FILE
grep -q '"formatted"' "$2" || echo '"formatted"' >> "$2"
EOF
cat > "$WORK/bin/golangci-lint" <<'EOF'
#!/bin/bash
# usage: golangci-lint run FILE
echo "$2:1:1: error: stub lint finding"
EOF
chmod +x "$WORK/bin/gofmt" "$WORK/bin/prettier" "$WORK/bin/golangci-lint"
export PATH="$WORK/bin:$PATH"

GIT_AUTHOR="-c user.email=t@t -c user.name=t"

REPO="$WORK/repo"
git init -q -b main "$REPO"
mkdir -p "$REPO/sub" "$REPO/dir with space"
printf 'package main\n' > "$REPO/old.go"
printf 'package main\n' > "$REPO/x.go"
printf 'package main\n' > "$REPO/sub/x.go"
# shellcheck disable=SC2086
git -C "$REPO" add old.go x.go sub/x.go && git -C "$REPO" $GIT_AUTHOR commit -q -m init

run_hook() {
  local repo="${1:-$REPO}" session="${2:-sess-1}"
  jq -n --arg d "$repo" --arg s "$session" \
    '{session_id: $s, cwd: $d, tool_name: "Bash", tool_input: {command: "true"}}' \
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

# $OUT holds the hook's stdout from the most recent run_hook call.
check_out_empty() {
  if [ -z "$OUT" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $1"
  fi
}

check_out_context() {
  if printf '%s' "$OUT" | jq -e --arg re "$2" '.hookSpecificOutput.additionalContext | test($re)' >/dev/null 2>&1; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $1"
  fi
}

# --- first run: baseline only, pre-existing dirty file untouched ---
# The dirty file must be older than the baseline stamp; a same-second write
# is treated as "changed since the previous run" by design.
printf 'package main\n' > "$REPO/pre.go"
sleep 1
OUT=$(run_hook)
check "first run does not format pre-existing changes" '! grep -q formatted "$REPO/pre.go"'
check_out_empty "first run prints nothing"

# --- a file changed after the baseline is formatted, lint output is JSON ---
printf 'package main\n' > "$REPO/new.go"
OUT=$(run_hook)
check "new file formatted" 'grep -q formatted "$REPO/new.go"'
check "untouched dirty file still not formatted" '! grep -q formatted "$REPO/pre.go"'
check_out_context "lint finding returned as additionalContext" "stub lint finding"

# --- same-second write after a run is still picked up ---
printf 'package main\n' > "$REPO/quick.go"
run_hook >/dev/null
check "same-second write formatted" 'grep -q formatted "$REPO/quick.go"'

# --- unchanged since the run before last: not formatted again ---
sleep 1
run_hook >/dev/null
run_hook >/dev/null
check "formatted file stays formatted once" '[ "$(grep -c formatted "$REPO/new.go")" -eq 1 ]'

# --- tracked file modified after baseline, path with a space ---
sleep 1
printf 'package main\n// edit\n' > "$REPO/old.go"
printf 'package main\n' > "$REPO/dir with space/b.go"
run_hook >/dev/null
check "modified tracked file formatted" 'grep -q formatted "$REPO/old.go"'
check "path with space formatted" 'grep -q formatted "$REPO/dir with space/b.go"'

# --- lockfiles and tool configs are skipped, ordinary json is formatted ---
sleep 1
printf '{}\n' > "$REPO/package-lock.json"
printf '{}\n' > "$REPO/biome.json"
printf '{}\n' > "$REPO/app.json"
run_hook >/dev/null
check "package-lock.json not formatted" '! grep -q formatted "$REPO/package-lock.json"'
check "biome.json not formatted" '! grep -q formatted "$REPO/biome.json"'
check "ordinary json formatted" 'grep -q formatted "$REPO/app.json"'

# --- rename: the old-name record must not resolve to a root-level file ---
sleep 1
run_hook >/dev/null
git -C "$REPO" mv sub/x.go sub/y.go
run_hook >/dev/null
check "root file untouched by rename record" '! grep -q formatted "$REPO/x.go"'

# --- outside a git repo: silent pass ---
OUT=$(run_hook "$WORK" sess-2)
check_out_empty "non-repo cwd passes silently"

# --- more than MAX_FILES changed: the overflow is reported ---
REPO2="$WORK/repo2"
git init -q -b main "$REPO2"
# shellcheck disable=SC2086
git -C "$REPO2" $GIT_AUTHOR commit -q --allow-empty -m init
run_hook "$REPO2" sess-3 >/dev/null
for i in $(seq 1 23); do printf 'package main\n' > "$REPO2/f$i.go"; done
OUT=$(run_hook "$REPO2" sess-3)
check_out_context "overflow reported" "3 more changed files"
check "only MAX_FILES formatted" '[ "$(grep -l formatted "$REPO2"/f*.go | wc -l | tr -d " ")" -eq 20 ]'

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
