#!/usr/bin/env bash
# Claude Code Stop hook: sync session conversation to Obsidian vault.
# On each invocation, overwrites this session's file with the latest jsonl
# snapshot. All failure modes exit 0 to avoid blocking other hooks.

set -uo pipefail

VAULT="${OBSIDIAN_VAULT:-$HOME/Documents/Obsidian Vault}"
LOG_DIR_NAME="03_Claude"

warn() { echo "[obsidian-sync] $*" >&2; }

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

if ! command -v jq >/dev/null 2>&1; then
  warn "jq not found, skipping"
  exit 0
fi

[ ! -d "$VAULT" ] && exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
LAST_MESSAGE=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty')

if [ -z "$SESSION_ID" ] || [ -z "$TRANSCRIPT_PATH" ]; then
  warn "missing session_id or transcript_path, skipping"
  exit 0
fi

if [ ! -f "$TRANSCRIPT_PATH" ]; then
  warn "transcript not found: $TRANSCRIPT_PATH"
  exit 0
fi

# Name from the session's starting cwd: the hook cwd follows cd and worktree moves.
START_CWD=$(jq -nr 'first(inputs | select(.type == "user" or .type == "assistant") | .cwd // empty)' "$TRANSCRIPT_PATH" 2>/dev/null)
PROJECT_RAW=$(basename "${START_CWD:-${CWD:-unknown}}")
PROJECT_NAME=$(printf '%s' "$PROJECT_RAW" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')
PROJECT_NAME="${PROJECT_NAME:-unknown}"
SESSION_SHORT=$(printf '%s' "${SESSION_ID:0:8}" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')

MESSAGES=$(jq -c '
  select(.type == "user" or .type == "assistant")
  | select(.isSidechain != true)
  | select(.isMeta != true)
  | {
      type: .type,
      timestamp: .timestamp,
      text: ([ .message.content[]? | select(.type == "text") | .text ] | join("\n\n"))
    }
  | select(.text != null and (.text | length) > 0)
' "$TRANSCRIPT_PATH" 2>/dev/null)

# The transcript is written asynchronously and can lack the turn's final message at Stop.
if [ -n "$LAST_MESSAGE" ]; then
  LAST_IN_TRANSCRIPT=$(printf '%s\n' "$MESSAGES" | jq -rs 'map(select(.type == "assistant")) | last | .text // empty')
  if [ "$LAST_MESSAGE" != "$LAST_IN_TRANSCRIPT" ]; then
    MESSAGES=$(printf '%s\n' "$MESSAGES"
      jq -nc --arg t "$LAST_MESSAGE" --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        '{type: "assistant", timestamp: $ts, text: $t}')
  fi
fi

[ -z "$MESSAGES" ] && exit 0

# Secret masking is limited to unambiguous known prefixes and assignment
# contexts (env/ini snake_case and STS-JSON CamelCase): a bare 40-char secret
# key with no surrounding context cannot be told apart from ordinary base64
# and is intentionally left alone, as are space-separated assignments
# (`aws configure set aws_secret_access_key <value>`).
# \x27 is the apostrophe (avoids quoting it inside this single-quoted program).
CLEANED=$(printf '%s\n' "$MESSAGES" | jq -c '
  .text |= (
      gsub("(?s)<system-reminder>.*?</system-reminder>"; "")
    | gsub("(?s)<ide_opened_file>.*?</ide_opened_file>"; "")
    | gsub("(?s)<ide_selection>.*?</ide_selection>"; "")
    | gsub("(?s)<command-message>.*?</command-message>"; "")
    | gsub("(?s)<command-name>.*?</command-name>"; "")
    | gsub("(?s)<command-args>.*?</command-args>"; "")
    | gsub("(?s)<local-command-stdout>.*?</local-command-stdout>"; "")
    | gsub("(?s)<local-command-stderr>.*?</local-command-stderr>"; "")
    | gsub("(?s)<user-prompt-submit-hook>.*?</user-prompt-submit-hook>"; "")
    | gsub("(AKIA|ASIA)[0-9A-Z]{16}"; "[MASKED_AWS_KEY_ID]")
    | gsub("(?<k>(aws_)?secret_?access_?key[\"\\x27]?\\s*[=:]\\s*[\"\\x27]?)[A-Za-z0-9/+=]{16,}"; "\(.k)[MASKED]"; "i")
    | gsub("(?<k>(aws_)?session_?token[\"\\x27]?\\s*[=:]\\s*[\"\\x27]?)[A-Za-z0-9/+=]{16,}"; "\(.k)[MASKED]"; "i")
    | gsub("gh[pousr]_[A-Za-z0-9]{20,}"; "[MASKED_GITHUB_TOKEN]")
    | gsub("github_pat_[A-Za-z0-9_]{20,}"; "[MASKED_GITHUB_TOKEN]")
    | gsub("xox[baprs]-[A-Za-z0-9-]{10,}"; "[MASKED_SLACK_TOKEN]")
    | sub("^\\s+"; "")
    | sub("\\s+$"; "")
  )
  | select((.text | length) > 0)
')

[ -z "$CLEANED" ] && exit 0

FIRST_TS=$(printf '%s\n' "$CLEANED" | jq -rs 'map(.timestamp) | min // empty')
FIRST_TS_CLEAN=$(printf '%s' "$FIRST_TS" | sed -E 's/\.[0-9]+Z$/Z/' | sed 's/Z$//')

if [ -n "$FIRST_TS_CLEAN" ]; then
  EPOCH=$(date -u -j -f "%Y-%m-%dT%H:%M:%S" "$FIRST_TS_CLEAN" "+%s" 2>/dev/null || true)
fi

if [ -n "${EPOCH:-}" ]; then
  SESSION_DATE=$(TZ=Asia/Tokyo date -r "$EPOCH" "+%Y-%m-%d")
  SESSION_TIME=$(TZ=Asia/Tokyo date -r "$EPOCH" "+%H:%M:%S")
else
  SESSION_DATE=$(date "+%Y-%m-%d")
  SESSION_TIME=$(date "+%H:%M:%S")
fi

OUT_DIR="$VAULT/$LOG_DIR_NAME/$SESSION_DATE"
OUT_FILE="$OUT_DIR/${PROJECT_NAME}--${SESSION_SHORT}.md"

mkdir -p "$OUT_DIR" || { warn "mkdir failed: $OUT_DIR"; exit 0; }

TMP=$(mktemp "${OUT_FILE}.XXXXXX") || { warn "mktemp failed"; exit 0; }

{
  printf '# %s (%s)\n\n' "$PROJECT_NAME" "$SESSION_DATE"
  printf '<!-- session: %s -->\n\n' "$SESSION_ID"
  printf '## %s\n\n' "$SESSION_TIME"

  printf '%s\n' "$CLEANED" | jq -r '
    if .type == "user" then "### User\n\n" + .text + "\n"
    else "### Assistant\n\n" + .text + "\n"
    end
  '

  printf '\n---\n'
} > "$TMP" 2>/dev/null && /bin/mv -f "$TMP" "$OUT_FILE" || {
  warn "write failed: $OUT_FILE"
  rm -f "$TMP"
}

exit 0
