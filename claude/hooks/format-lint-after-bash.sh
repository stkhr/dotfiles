#!/bin/bash
# PostToolUse (Bash): hand files that a Bash command changed to
# format-on-edit.sh and lint-feedback.sh. In auto mode Claude edits with
# sed/heredocs, so the Edit|Write hooks never see those edits.
#
# Changed = listed by `git status` and not older than the previous run's
# stamp. The first run only writes the stamp, so changes made before the
# session are left alone. A file formatted in one run is handed back once
# more in the next (its mtime equals the stamp), so its lint result is
# reported twice; formatters skip unchanged files, so this converges.
# At most MAX_FILES files per run. The stamp is advanced before any work,
# so a run killed by the hook timeout drops the rest of that batch instead
# of redoing it on every later Bash call.

set -uo pipefail

MAX_FILES=20

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
CWD="${CWD:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
SESSION=$(echo "$INPUT" | jq -r '.session_id // "nosession"' 2>/dev/null)

ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0

STAMP_DIR="${TMPDIR:-/tmp}/claude-hooks"
STAMP="$STAMP_DIR/$SESSION.bash-edit-stamp"
PREV="$STAMP.prev"
mkdir -p "$STAMP_DIR" || exit 0
if [ ! -f "$STAMP" ]; then
  touch "$STAMP"
  exit 0
fi
if ! mv -f "$STAMP" "$PREV" || ! touch "$STAMP"; then
  exit 0
fi

HOOK_DIR=$(cd "$(dirname "$0")" && pwd)
CONTEXT=""
COUNT=0
SKIPPED=0
SKIPPED_FILES=""
RS_LINTED=""
LINTED_DIRS=""

# Generated or tool-config files that the formatters must not rewrite.
# Mirrors the Edit deny rules in settings.json, which this path bypasses.
skip_file() {
  case "$(basename "$1")" in
    package-lock.json|npm-shrinkwrap.json|pnpm-lock.yaml|yarn.lock|bun.lockb|bun.lock) return 0 ;;
    biome.json|.eslintrc|.eslintrc.*|eslint.config.*|.oxlintrc*) return 0 ;;
    ruff.toml|.ruff.toml|.golangci.yml|.golangci.yaml|clippy.toml|.tflint.hcl) return 0 ;;
  esac
  return 1
}

add_context() {
  CONTEXT="${CONTEXT:+$CONTEXT

}$1"
}

# -z keeps paths with spaces intact. Renames and copies carry a second
# record with the old name, which is consumed and ignored.
while IFS= read -r -d '' ENTRY; do
  XY="${ENTRY:0:2}"
  REL="${ENTRY:3}"
  case "$XY" in
    *R*|*C*) IFS= read -r -d '' _ ;;
  esac
  FILE="$ROOT/$REL"
  [ -f "$FILE" ] || continue
  # "not older than" keeps same-second writes; -nt alone would drop them.
  [ "$FILE" -ot "$PREV" ] && continue
  skip_file "$FILE" && continue
  COUNT=$((COUNT + 1))
  if [ "$COUNT" -gt "$MAX_FILES" ]; then
    SKIPPED=$((SKIPPED + 1))
    [ "$SKIPPED" -le 10 ] && SKIPPED_FILES="${SKIPPED_FILES:+$SKIPPED_FILES
}$REL"
    continue
  fi

  PAYLOAD=$(jq -n --arg f "$FILE" --arg d "$CWD" '{tool_input: {file_path: $f}, cwd: $d}')
  printf '%s' "$PAYLOAD" | bash "$HOOK_DIR/format-on-edit.sh" >/dev/null 2>&1

  # Linters that cover more than one file run once per hook invocation:
  # cargo clippy is workspace-wide, tflint is directory-wide.
  case "$FILE" in
    *.rs)
      [ -n "$RS_LINTED" ] && continue
      RS_LINTED=1
      ;;
    *.tf|*.tfvars)
      DIR=$(dirname "$FILE")
      case "$LINTED_DIRS" in
        *"|$DIR|"*) continue ;;
      esac
      LINTED_DIRS="$LINTED_DIRS|$DIR|"
      ;;
  esac
  DIAG=$(printf '%s' "$PAYLOAD" | bash "$HOOK_DIR/lint-feedback.sh" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
  [ -n "$DIAG" ] && add_context "$DIAG"
done < <(git -C "$ROOT" status --porcelain=v1 --untracked-files=all -z 2>/dev/null)

if [ "$SKIPPED" -gt 0 ]; then
  NOTE="$SKIPPED more changed files were not formatted or linted (limit $MAX_FILES per command); run the formatter and linter on them yourself:
$SKIPPED_FILES"
  [ "$SKIPPED" -gt 10 ] && NOTE="$NOTE
..."
  add_context "$NOTE"
fi

[ -z "$CONTEXT" ] && exit 0
jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'
exit 0
