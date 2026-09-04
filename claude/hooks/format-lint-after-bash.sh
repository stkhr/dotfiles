#!/bin/bash
# PostToolUse (Bash): hand files that a Bash command changed to
# format-on-edit.sh and lint-feedback.sh. In auto mode Claude edits with
# sed/heredocs, so the Edit|Write hooks never see those edits.
#
# Changed = listed by `git status` and newer than this session's stamp file.
# The first run only writes the stamp, so changes made before the session
# are left alone. At most MAX_FILES files per run to keep the hook cheap
# when a command rewrites a whole tree.

set -uo pipefail

MAX_FILES=20

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
CWD="${CWD:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
SESSION=$(echo "$INPUT" | jq -r '.session_id // "nosession"' 2>/dev/null)

ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0

STAMP_DIR="${TMPDIR:-/tmp}/claude-hooks"
STAMP="$STAMP_DIR/$SESSION.bash-edit-stamp"
mkdir -p "$STAMP_DIR" || exit 0
if [ ! -f "$STAMP" ]; then
  touch "$STAMP"
  exit 0
fi

HOOK_DIR=$(cd "$(dirname "$0")" && pwd)
CONTEXT=""
COUNT=0

# -z keeps paths with spaces intact; renames come as "new\0old", and the
# loop only ever formats existing files, so the old name is a no-op.
while IFS= read -r -d '' ENTRY; do
  REL="${ENTRY:3}"
  FILE="$ROOT/$REL"
  [ -f "$FILE" ] || continue
  [ "$FILE" -nt "$STAMP" ] || continue
  COUNT=$((COUNT + 1))
  [ "$COUNT" -gt "$MAX_FILES" ] && break

  PAYLOAD=$(jq -n --arg f "$FILE" --arg d "$CWD" '{tool_input: {file_path: $f}, cwd: $d}')
  printf '%s' "$PAYLOAD" | bash "$HOOK_DIR/format-on-edit.sh" >/dev/null 2>&1
  DIAG=$(printf '%s' "$PAYLOAD" | bash "$HOOK_DIR/lint-feedback.sh" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
  [ -n "$DIAG" ] && CONTEXT="${CONTEXT:+$CONTEXT

}$DIAG"
done < <(git -C "$ROOT" status --porcelain=v1 --untracked-files=all -z 2>/dev/null)

touch "$STAMP"

[ -z "$CONTEXT" ] && exit 0
jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'
exit 0
