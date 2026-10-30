#!/bin/bash
# Tests for verify-reply-format.sh. Usage: bash claude/hooks/tests/test-verify-reply-format.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/verify-reply-format.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# One assistant message per argument; the last one is the final message.
make_transcript() {
  local out="$WORK/transcript.jsonl"
  : > "$out"
  local text
  for text in "$@"; do
    jq -nc --arg t "$text" \
      '{type: "assistant", message: {content: [{type: "text", text: $t}]}}' >> "$out"
  done
  echo "$out"
}

run_hook() {
  local transcript="$1" active="${2:-false}"
  # shellcheck disable=SC2069
  jq -n --arg tp "$transcript" --argjson a "$active" \
    '{stop_hook_active: $a, transcript_path: $tp}' | bash "$HOOK" 2>&1 >/dev/null
}

check() {
  local ok="$1" label="$2" detail="${3:-}"
  if [ "$ok" = "yes" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label"
    [ -n "$detail" ] && echo "  $detail"
  fi
}

run_case() {
  local expect="$1" label="$2" text="$3" active="${4:-false}"
  local transcript err code got="pass"
  transcript=$(make_transcript "$text")
  err=$(run_hook "$transcript" "$active")
  code=$?
  [ "$code" -eq 2 ] && got="block"
  local ok=no
  [ "$got" = "$expect" ] && ok=yes
  check "$ok" "[expect=$expect got=$got] $label" "stderr: $err"
}

# --- URL adjacency ---
run_case pass "URL at end of line" '- Draft・CI pass: https://github.com/o/r/pull/1
次に進みます'
run_case pass "URL followed by space" 'PR は https://github.com/o/r/pull/1 にあります'
run_case block "URL followed by ASCII paren" 'PR https://github.com/o/r/pull/1(マージ済み)を確認しました'
run_case block "URL inside parentheses" '計画を直しました(crit は http://localhost:5000)。確認してください'
run_case block "URL followed by full-width paren" 'PR https://github.com/o/r/pull/1（Draft）です'
run_case block "URL inside corner brackets" 'PR は「https://github.com/o/r/pull/1」 です'
run_case block "URL followed by Japanese comma" '対応表 http://localhost:6001、計画 http://localhost:6002 を開いています'
run_case block "URL followed by Japanese text" 'https://github.com/o/r/pull/1を確認しました'
run_case block "URL followed by trailing period" '詳細は https://example.com/docs. を見てください'
run_case pass "markdown link" '詳細は [PR #1](https://github.com/o/r/pull/1) を見てください'
run_case pass "markdown link whose text is the URL" '詳細は [https://github.com/o/r/pull/1](https://github.com/o/r/pull/1) を見てください'
run_case pass "autolink" '詳細は <https://github.com/o/r/pull/1> を見てください'
run_case pass "URL in fenced code block" '次を実行してください
```
curl "https://example.com/api)"
```
結果を貼ってください'
# shellcheck disable=SC2016
run_case pass "URL in inline code" 'URL は `https://example.com/x)` の形式で指定します'

# --- Japanese ---
run_case block "English-only report" 'Investigating. The access logs already reach the archive bucket through the event bus, and the gateway service is registered in the config. Next I am checking where those logs end up and what the agent can read.'
run_case block "English with a few Japanese words" 'The CI passed all jobs: lint, test, build, shellcheck, tflint, validate, fmt and docs, so the branch is ready. 成功しました。'
run_case pass "Japanese with many identifiers" 'PR #1239 の CI は 81 件が pass、1 件が skipping でした。plan のコメントを全件取得し、web ACL の in-place 更新以外の変更がある env を洗い出します。'
run_case pass "identifier-heavy Japanese near the threshold" 'ローカルでは lint, test, build, shellcheck, tflint, validate, fmt, docs, audit, bench の 10 ジョブがすべて成功しました。次は Draft PR を作ります。'
run_case pass "short English" 'OK'
run_case pass "English only inside code block" '次のコマンドを実行してください
```
aws lambda invoke --function-name my-function --payload file://event.json out.json && cat out.json
```'
run_case block "plain-text English commit message draft" 'コミットメッセージ案です。
feat(hooks): block non-Japanese replies and URL-adjacent punctuation in the final assistant message so that the rules in the guideline are enforced mechanically'
run_case pass "English commit message draft in code block" 'コミットメッセージ案です。
```
feat(hooks): block non-Japanese replies and URL-adjacent punctuation in the final assistant message so that the rules in the guideline are enforced mechanically
```'
run_case pass "Japanese with file paths" '変更したファイル
- claude/hooks/verify-reply-format.sh
- claude/hooks/tests/test-verify-reply-format.sh
- claude/settings.json
テストは全件通りました。'

# --- loop guard ---
run_case pass "stop_hook_active skips English" 'Investigating. The access logs already reach the archive bucket through the event bus, and the gateway service is registered in the config. Next I am checking where those logs end up and what the agent can read.' true

# --- only the final assistant message is checked ---
transcript=$(make_transcript 'Investigating. The access logs already reach the archive bucket through the event bus, and the gateway service is registered in the config. Next I am checking where those logs end up and what the agent can read.' '調査が終わりました。結果はレポートにまとめています。')
err=$(run_hook "$transcript"); code=$?
ok=no; [ "$code" -eq 0 ] && ok=yes
check "$ok" "earlier English turn is ignored when the final message is Japanese" "stderr: $err"

# --- reason text ---
transcript=$(make_transcript 'PR https://github.com/o/r/pull/1(マージ済み)を確認しました')
err=$(run_hook "$transcript")
ok=no; echo "$err" | grep -q 'https://github.com/o/r/pull/1' && ok=yes
check "$ok" "reason names the offending URL" "stderr: $err"

transcript=$(make_transcript 'https://github.com/o/r/pull/1を確認しました')
err=$(run_hook "$transcript")
ok=no; echo "$err" | grep -qE 'pull/1( |$)' && ! echo "$err" | grep -q 'pull/1を' && ok=yes
check "$ok" "reported URL excludes the Japanese tail" "stderr: $err"

transcript=$(make_transcript 'Investigating. The access logs already reach the archive bucket through the event bus, and the gateway service is registered in the config. See https://example.com/x(details) for the rest of the findings.')
err=$(run_hook "$transcript")
ok=no; echo "$err" | grep -q 'URL の直後' && echo "$err" | grep -q '日本語ではありません' && echo "$err" | grep -qE '割合 [0-9]+%' && ok=yes
check "$ok" "both findings reported together with the Japanese share" "stderr: $err"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
