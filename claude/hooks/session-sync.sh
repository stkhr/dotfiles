#!/usr/bin/env bash
# Claude Code Stop hook: sync session conversation to Obsidian vault.
# On each invocation, replaces the block for the current session_id with the
# latest jsonl snapshot. All failure modes exit 0 to avoid blocking other hooks.

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

if [ -z "$SESSION_ID" ] || [ -z "$TRANSCRIPT_PATH" ]; then
  warn "missing session_id or transcript_path, skipping"
  exit 0
fi

if [ ! -f "$TRANSCRIPT_PATH" ]; then
  warn "transcript not found: $TRANSCRIPT_PATH"
  exit 0
fi

PROJECT_RAW=$(basename "${CWD:-unknown}")
PROJECT_NAME=$(printf '%s' "$PROJECT_RAW" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')
PROJECT_NAME="${PROJECT_NAME:-unknown}"

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

[ -z "$MESSAGES" ] && exit 0

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
OUT_FILE="$OUT_DIR/${PROJECT_NAME}.md"

mkdir -p "$OUT_DIR" || { warn "mkdir failed: $OUT_DIR"; exit 0; }

# If this session is already in the file, strip its block. Removal range:
#   from any blank lines immediately preceding the session marker,
#   through the marker itself,
#   up to (but not including) the next session marker or EOF.
# Trailing blanks at EOF are also dropped so the file stays compact across reruns.
if [ -f "$OUT_FILE" ] && grep -qFx "<!-- session: ${SESSION_ID} -->" "$OUT_FILE"; then
  TMP=$(mktemp "${OUT_FILE}.XXXXXX") || { warn "mktemp failed"; exit 0; }
  awk -v sid="$SESSION_ID" '
    BEGIN { pending = ""; skip = 0 }
    /^<!-- session: / {
      if ($0 == "<!-- session: " sid " -->") {
        pending = ""
        skip = 1
        next
      } else {
        if (pending != "") { printf "%s", pending; pending = "" }
        skip = 0
      }
    }
    !skip {
      if ($0 == "") {
        pending = pending "\n"
      } else {
        if (pending != "") { printf "%s", pending; pending = "" }
        print
      }
    }
  ' "$OUT_FILE" > "$TMP" && /bin/mv -f "$TMP" "$OUT_FILE" || {
    warn "block-strip failed for $OUT_FILE"
    rm -f "$TMP"
    exit 0
  }
fi

{
  if [ ! -f "$OUT_FILE" ]; then
    printf '# %s (%s)\n\n' "$PROJECT_NAME" "$SESSION_DATE"
  fi
  printf '\n<!-- session: %s -->\n\n' "$SESSION_ID"
  printf '## %s\n\n' "$SESSION_TIME"

  printf '%s\n' "$CLEANED" | jq -r '
    if .type == "user" then "### User\n\n" + .text + "\n"
    else "### Assistant\n\n" + .text + "\n"
    end
  '

  printf '\n---\n'
} >> "$OUT_FILE" 2>/dev/null || warn "write failed: $OUT_FILE"

exit 0
