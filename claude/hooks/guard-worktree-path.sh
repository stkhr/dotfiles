#!/bin/bash
# PreToolUse (Bash): block `git worktree add` that places the worktree OUTSIDE
# the repository root. Sibling/absolute worktrees cause the Bash tool's cwd to
# silently reset to the launch root, leaking artifacts (.venv, uv.lock, ...) to
# the wrong tree. Steer to an in-repo path such as .claude/worktrees/<branch>.
# Exit code 2 blocks the tool execution and shows stderr to Claude.
#
# Accident guard, not an adversarial boundary: parsing is heuristic, and a
# heredoc body fed to an interpreter (bash <<EOF) is never inspected.

set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Only inspect `git worktree add` (any form: `git -C <dir> worktree add`,
# `cd <dir> && git worktree add`, etc. — match the `worktree add` token pair).
# Heredoc stripping below only ever removes lines, so gating on the raw command
# first is safe and keeps python off the path of every other Bash call.
echo "$COMMAND" | grep -qE 'worktree[[:space:]]+add' || exit 0

# Heredoc bodies are document text, not commands: writing an example path into
# a file must not trip the guard. A python failure leaves SCAN empty and falls
# back to the raw command, so the scan errs toward inspecting too much rather
# than too little.
SCAN=$(printf '%s' "$COMMAND" | python3 -c '
import re, sys
lines = sys.stdin.read().split("\n")
# (?<!<) and (?!<) keep here-strings (<<< word) from being read as a tag.
tag_re = re.compile(r"(?<!<)<<(-?)[ \t]*(?!<)[\x27\"\\]?([A-Za-z0-9_][A-Za-z0-9_.-]*)[\x27\"]?")
out = []
i = 0
while i < len(lines):
    line = lines[i]
    i += 1
    out.append(line)
    for dash, tag in tag_re.findall(line):
        start = i
        closed = False
        while i < len(lines):
            body = lines[i]
            i += 1
            # <<- strips leading tabs from the terminator, plain << does not.
            if (body.lstrip("\t") if dash else body) == tag:
                closed = True
                break
        if not closed:
            # Nothing terminated it, so the "<<" was probably a shift operator
            # or lived inside a quoted string. Put the swallowed lines back.
            out.extend(lines[start:])
sys.stdout.write("\n".join(out))
' 2>/dev/null)
[ -z "$SCAN" ] && SCAN="$COMMAND"

CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
CWD="${CWD:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"

# A preceding `cd <dir>` or `git -C <dir>` moves git away from the session cwd, so judge against that repo.
INVOCATIONS=$(printf '%s' "$SCAN" | python3 -c '
import os, shlex, sys
base = sys.argv[1]
valopts = {"-b", "-B", "--reason"}   # flags that consume the next token
seps = {";", "&&", "||", "|", "&", "(", ")"}
def resolve(d, frm):
    d = os.path.expanduser(d)
    return os.path.normpath(d if os.path.isabs(d) else os.path.join(frm, d))
for line in sys.stdin.read().split("\n"):
    lex = shlex.shlex(line, posix=True, punctuation_chars=";&|()")
    lex.whitespace_split = True
    try:
        toks = list(lex)
    except ValueError:
        continue
    segs, seg = [], []
    for t in toks:
        if t in seps:
            segs.append(seg); seg = []
        else:
            seg.append(t)
    segs.append(seg)
    for seg in segs:
        if len(seg) >= 2 and seg[0] == "cd":
            base = resolve(seg[1], base)
            continue
        k = next((j for j in range(len(seg) - 1) if seg[j:j + 2] == ["worktree", "add"]), None)
        if k is None:
            continue
        gitdir = base
        j = 0
        while j < k:
            if seg[j] == "-C" and j + 1 < k:
                gitdir = resolve(seg[j + 1], gitdir); j += 2; continue
            j += 1
        rest = seg[k + 2:]
        i = 0
        while i < len(rest):
            t = rest[i]
            if t in valopts:
                i += 2; continue
            if t.startswith("-"):
                i += 1; continue
            print(gitdir + "\t" + resolve(t, gitdir)); break
' "$CWD" 2>/dev/null)

while IFS=$'\t' read -r GITDIR TARGET; do
  [ -z "$TARGET" ] && continue
  ROOT=$(git -C "$GITDIR" rev-parse --show-toplevel 2>/dev/null || true)
  [ -z "$ROOT" ] && continue   # not in a git repo, leave it alone

  # normpath works without the path existing yet.
  INSIDE=$(python3 -c '
import os, sys
p, root = os.path.normpath(sys.argv[1]), os.path.normpath(sys.argv[2])
print("yes" if (p == root or p.startswith(root + os.sep)) else "no")
' "$TARGET" "$ROOT" 2>/dev/null)

  [ "$INSIDE" = "no" ] || continue

  cat >&2 <<EOF
BLOCKED: worktree をリポジトリ外に作成しようとしています ($TARGET)。
リポジトリ外(兄弟階層/絶対パス)の worktree は Bash の cwd が起動ルートに戻り、
成果物(.venv / uv.lock 等)が誤ったツリーに漏れます。
リポジトリ内に作成してください。例: git worktree add .claude/worktrees/<branch>
EOF
  exit 2
done <<< "$INVOCATIONS"

exit 0
