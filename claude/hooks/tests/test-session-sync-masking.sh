#!/bin/bash
# Tests for session-sync.sh secret masking (known-prefix tokens and
# assignment-context AWS credentials must not reach the vault in plain text).
# Usage: bash claude/hooks/tests/test-session-sync-masking.sh
set -uo pipefail

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

HOOK="$(cd "$(dirname "$0")/.." && pwd)/session-sync.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export OBSIDIAN_VAULT="$WORK/vault"
mkdir -p "$OBSIDIAN_VAULT"

TEXT='export AWS_ACCESS_KEY_ID=ASIAQAWOTESTKEY12345 AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMIK7MDENGbPxRfiCYEXAMPLEKEY99" AWS_SESSION_TOKEN=IQoJb3JpZ2luX2VjEBcaCXVzLWVhc3QtMSJHtest {"SecretAccessKey": "stsJsonSecretValue0123456789abcdef", "SessionToken": "IQoJstsJsonTokenValue0123456789"} ghp_AbCdEfGhIjKlMnOpQrStUvWxYz0123456789 xoxb-1234567890-abcdefghij github_pat_11ABCDEFG0123456789_abcdef keep-this-plain-sentence'

jq -nc --arg t "$TEXT" '{type:"assistant", isSidechain:false,
  timestamp:"2026-07-30T04:00:00.000Z",
  message:{content:[{type:"text", text:$t}]}}' > "$WORK/transcript.jsonl"

jq -n --arg tp "$WORK/transcript.jsonl" --arg d "$WORK/proj" \
  '{session_id:"test-session-1", transcript_path:$tp, cwd:$d}' | bash "$HOOK"

OUT=$(find "$OBSIDIAN_VAULT" -name 'proj.md' -exec cat {} +)

check_absent() {
  local label="$1" needle="$2"
  if printf '%s' "$OUT" | grep -qF "$needle"; then
    FAIL=$((FAIL + 1))
    echo "FAIL [leaked]: $label"
  else
    PASS=$((PASS + 1))
  fi
}

check_present() {
  local label="$1" needle="$2"
  if printf '%s' "$OUT" | grep -qF "$needle"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL [missing]: $label"
  fi
}

check_absent "AWS access key id"    'ASIAQAWOTESTKEY12345'
check_absent "AWS secret key"       'wJalrXUtnFEMIK7MDENG'
check_absent "AWS session token"    'IQoJb3JpZ2luX2Vj'
check_absent "STS JSON secret key"  'stsJsonSecretValue'
check_absent "STS JSON token"       'IQoJstsJsonTokenValue'
check_absent "GitHub token"         'ghp_AbCdEfGhIjKlMnOp'
check_absent "GitHub fine-grained"  'github_pat_11ABCDEFG'
check_absent "Slack token"          'xoxb-1234567890'
check_present "masked key id"       '[MASKED_AWS_KEY_ID]'
check_present "masked assignment"   'AWS_SECRET_ACCESS_KEY="[MASKED]"'
check_present "plain text survives" 'keep-this-plain-sentence'

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
