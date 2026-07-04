#!/bin/bash
# PreToolUse (Bash): block `git worktree add` that places the worktree OUTSIDE
# the repository root. Sibling/absolute worktrees cause the Bash tool's cwd to
# silently reset to the launch root, leaking artifacts (.venv, uv.lock, ...) to
# the wrong tree. Steer to an in-repo path such as .claude/worktrees/<branch>.
# Exit code 2 blocks the tool execution and shows stderr to Claude.

set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Only inspect `git worktree add` (any form: `git -C <dir> worktree add`,
# `cd <dir> && git worktree add`, etc. — match the `worktree add` token pair).
echo "$COMMAND" | grep -qE 'worktree[[:space:]]+add' || exit 0

CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
CWD="${CWD:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"

ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)
[ -z "$ROOT" ] && exit 0   # not in a git repo, leave it alone

# Extract the worktree path: drop everything up to "add", then take the first
# positional token (skipping option flags and their values) via shlex.
TARGET=$(echo "$COMMAND" \
  | sed -E 's/.*worktree[[:space:]]+add[[:space:]]*//' \
  | python3 -c '
import sys, shlex
try:
    toks = shlex.split(sys.stdin.read())
except Exception:
    sys.exit(0)
valopts = {"-b", "-B", "--reason", "--orphan"}   # flags that consume the next token
i = 0
while i < len(toks):
    t = toks[i]
    if t in valopts:
        i += 2; continue
    if t.startswith("-"):
        i += 1; continue
    print(t); break
' 2>/dev/null)

[ -z "$TARGET" ] && exit 0

# Resolve TARGET against CWD and test whether it lands inside ROOT.
# normpath works without the path existing yet.
INSIDE=$(python3 -c '
import os, sys
cwd, target, root = sys.argv[1], sys.argv[2], sys.argv[3]
p = target if os.path.isabs(target) else os.path.join(cwd, target)
p = os.path.normpath(p)
root = os.path.normpath(root)
print("yes" if (p == root or p.startswith(root + os.sep)) else "no")
' "$CWD" "$TARGET" "$ROOT" 2>/dev/null)

if [ "$INSIDE" = "no" ]; then
  cat >&2 <<EOF
BLOCKED: worktree をリポジトリ外に作成しようとしています ($TARGET)。
リポジトリ外(兄弟階層/絶対パス)の worktree は Bash の cwd が起動ルートに戻り、
成果物(.venv / uv.lock 等)が誤ったツリーに漏れます。
リポジトリ内に作成してください。例: git worktree add .claude/worktrees/<branch>
EOF
  exit 2
fi

exit 0
