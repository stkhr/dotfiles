#!/bin/bash
# Table-driven tests for guard-worktree-path.sh.
# Usage: bash claude/hooks/tests/test-guard-worktree-path.sh
set -uo pipefail

# Hermetic against the machine's git config (init.defaultBranch etc.)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

HOOK="$(cd "$(dirname "$0")/.." && pwd)/guard-worktree-path.sh"
PASS=0
FAIL=0

# -P: the hook compares against `rev-parse --show-toplevel`, which is physical;
# macOS mktemp hands back a /var -> /private/var symlink.
WORK=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"
git init -q -b main "$REPO"
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

run_case() {
  local expect="$1" cmd="$2"
  jq -n --arg c "$cmd" --arg d "$REPO" '{tool_input: {command: $c}, cwd: $d}' | bash "$HOOK" >/dev/null 2>&1
  local code=$?
  local got="pass"
  [ "$code" -eq 2 ] && got="block"
  if [ "$got" = "$expect" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL [expect=$expect got=$got]: $cmd"
  fi
}

# --- target outside the repository root is blocked ---
run_case block 'git worktree add ../x'
run_case block "git worktree add $WORK/outside"
run_case block 'git worktree add "../x with space"'

# --- in-repo target, and subcommands other than add, pass ---
run_case pass 'git worktree add .claude/worktrees/x'
run_case pass 'git worktree add -b feat/x .claude/worktrees/x'
run_case pass 'git worktree list'
run_case pass 'git worktree remove ../x'

# --- heredoc bodies are document text, not commands ---
run_case pass $'cat > docs/x.md <<EOF\ngit worktree add ../x\nEOF'
run_case pass $'cat > docs/x.md <<\'EOF\'\ngit worktree add ../x\nEOF'
run_case pass $'cat > docs/x.md <<"EOF"\ngit worktree add ../x\nEOF'
run_case pass $'cat > docs/x.md <<\\EOF\ngit worktree add ../x\nEOF'
run_case pass $'cat > docs/x.md <<-EOF\n\tgit worktree add ../x\n\tEOF'
run_case pass $'cat <<A > a.md && cat <<B > b.md\ngit worktree add ../a\nA\ngit worktree add ../b\nB'

# --- an invocation outside a heredoc body still blocks ---
run_case block $'cat > docs/x.md <<EOF\nhello\nEOF\ngit worktree add ../x'
run_case block $'echo hi\ngit worktree add ../x'
# a here-string is not a heredoc: it must not swallow the following lines
run_case block $'cat <<< hello\ngit worktree add ../x'

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
