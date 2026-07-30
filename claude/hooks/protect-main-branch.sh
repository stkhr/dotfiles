#!/bin/bash
# Prevent git commit on main/master branch.
# Used as a Claude Code PreToolUse hook for the Bash tool.
# Exit code 2 blocks the tool execution and shows stderr to Claude.
#
# Accident guard, not an adversarial boundary: parsing is heuristic and
# unresolvable targets fall back to the session cwd judgment.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Flatten to one line (+ trailing space) so ordering scans and end-of-command
# matches work without $ anchors inside embedded regexes.
FLAT="$(printf '%s' "$COMMAND" | tr '\n' ' ') "

Q_PATH="(\"[^\"]*\"|'[^']*'|[^[:space:]]+)"
SEP="([[:space:]]|;|&|\|)"
COMMIT_RE="(^|[[:space:]]|&&|\||;)git[[:space:]]+(-C[[:space:]]+${Q_PATH}[[:space:]]+)?commit${SEP}"

if ! echo "$FLAT" | grep -qE "$COMMIT_RE"; then
  exit 0
fi

# Text before the first commit invocation: a branch created after the commit
# does not protect it, and a `cd` after the commit does not decide its repo.
PRE=$(echo "$FLAT" | sed -E "s/${COMMIT_RE}.*//")

if echo "$PRE" | grep -qE "git[[:space:]]+(-C[[:space:]]+${Q_PATH}[[:space:]]+)?(checkout[[:space:]]+-b|switch[[:space:]]+(-c|--create))${SEP}"; then
  exit 0
fi

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
CWD="${CWD:-${CLAUDE_PROJECT_DIR:-}}"

strip_quotes() {
  echo "$1" | sed -E "s/^\"(.*)\"$/\1/; s/^'(.*)'$/\1/"
}

resolve_dir() {
  local target
  target=$(strip_quotes "$1")
  case "$target" in
    "") echo "$CWD" ;;
    /*) echo "$target" ;;
    "~"*) echo "${target/#\~/$HOME}" ;;
    *) echo "${CWD:+$CWD/}$target" ;;
  esac
}

branch_of() {
  git -C "$1" symbolic-ref --short HEAD 2>/dev/null || true
}

check_dir() {
  local dir="$1" branch
  branch=$(branch_of "$dir")
  # Unresolvable target (bad path parse, deleted dir): fall back to the
  # session cwd rather than silently passing a possible main commit through.
  if [ -z "$branch" ] && [ "$dir" != "$CWD" ] && [ -n "$CWD" ]; then
    branch=$(branch_of "$CWD")
  fi
  if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
    echo "BLOCKED: Direct commit to '$branch' branch is not allowed. Create a feature branch first." >&2
    exit 2
  fi
}

# Judge every `git -C <path> commit`: each names its own target repo.
GIT_C_TARGETS=$(echo "$FLAT" \
  | grep -oE "git[[:space:]]+-C[[:space:]]+${Q_PATH}[[:space:]]+commit${SEP}" \
  | sed -E "s/^git[[:space:]]+-C[[:space:]]+//; s/[[:space:]]+commit.?$//" || true)
if [ -n "$GIT_C_TARGETS" ]; then
  while IFS= read -r t; do
    check_dir "$(resolve_dir "$t")"
  done <<< "$GIT_C_TARGETS"
fi

# A bare `git commit` is judged against the last `cd <path>` before the first
# commit, then the session cwd.
if echo "$FLAT" | grep -qE "(^|[[:space:]]|&&|\||;)git[[:space:]]+commit${SEP}"; then
  TARGET=""
  CD_SEG=$(echo "$PRE" | grep -oE "(^|[;&|][[:space:]]*)cd[[:space:]]+${Q_PATH}" | tail -n 1 || true)
  if [ -n "$CD_SEG" ]; then
    TARGET=$(echo "$CD_SEG" | sed -E "s/^([;&|]*[[:space:]]*)?cd[[:space:]]+//")
  fi
  DIR=$(resolve_dir "$TARGET")
  if [ -n "$DIR" ]; then
    check_dir "$DIR"
  fi
fi

exit 0
