#!/bin/bash
# Tests for claude-outputs の --emit(fzf の reload が呼ぶ行出力)と --open-session(ctrl-o)。
# gh は PATH のスタブに差し替え、crit は無い環境として走らせる。herdr は --emit では
# 無い環境、--open-session では呼び出しを記録するスタブにする。
# Usage: bash bin/tests/test-claude-outputs.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/claude-outputs"
SEP=$(printf '\037')
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# 頼み忘れた --json の列は実物の gh と同じく欠ける。既定の空配列は artifact の行だけを見るため
STUB_BIN="$WORK/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/gh" <<'STUBEOF'
#!/bin/bash
[ -n "${GH_STUB_JSON:-}" ] || { echo '[]'; exit 0; }
fields=""
while [ $# -gt 0 ]; do [ "$1" = --json ] && fields="$2"; shift; done
jq --arg f "$fields" '($f | split(",")) as $keep | map(with_entries(select(.key | IN($keep[]))))' "$GH_STUB_JSON"
STUBEOF
chmod +x "$STUB_BIN/gh"
PATH="$STUB_BIN:$PATH"
export PATH

# herdr のメタ情報は引かせない(状態の印が付くと表示列が変わる)
unset HERDR_ENV
export CRIT_SESSIONS_DIR="$WORK/no-crit"

SID=11111111-2222-3333-4444-555555555555
URL=https://claude.ai/code/artifact/abcdef01-0000-0000-0000-000000000000

make_projects() {
    local dir="$1"
    mkdir -p "$dir/-Users-someone-proj"
    cat > "$dir/-Users-someone-proj/$SID.jsonl" <<TRANSCRIPT
{"type":"assistant","cwd":"/Users/someone/proj","message":{"content":[{"type":"tool_use","id":"toolu_1","name":"Artifact","input":{"action":"publish","description":"テスト用の成果物"}}]}}
{"type":"user","cwd":"/Users/someone/proj","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_1","content":"Published at $URL"}]}}
TRANSCRIPT
}

check() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        printf 'ok   %s\n' "$name"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$name" "$expected" "$actual"
    fi
}

# ---- --emit は fzf に渡す4列(表示 / URL / session_id / cwd)を出す ----------
PROJECTS="$WORK/projects"
make_projects "$PROJECTS"
export CLAUDE_PROJECTS_DIR="$PROJECTS"

out=$("$SCRIPT" --emit 2>"$WORK/emit.err")
check "--emit は1行だけ出す" 1 "$(printf '%s\n' "$out" | grep -c .)"
check "--emit の列数は4" 4 "$(printf '%s' "$out" | awk -F"$SEP" '{ print NF }')"
check "--emit の2列目は URL" "$URL" "$(printf '%s' "$out" | awk -F"$SEP" '{ print $2 }')"
check "--emit の3列目は session_id" "$SID" "$(printf '%s' "$out" | awk -F"$SEP" '{ print $3 }')"
check "--emit の表示列に説明文が入る" 1 \
    "$(printf '%s' "$out" | awk -F"$SEP" '{ print $1 }' | grep -c 'テスト用の成果物')"

# ---- 端末が無い時の既定出力は従来どおり2列 --------------------------------
plain=$("$SCRIPT" 2>/dev/null)
check "既定出力は表示と URL を並べる" 1 "$(printf '%s' "$plain" | grep -c "  $URL\$")"

PR_URL=https://github.com/someone/proj/pull/42
PR_PROJECTS="$WORK/pr-projects"
mkdir -p "$PR_PROJECTS/-Users-someone-proj"
cat > "$PR_PROJECTS/-Users-someone-proj/$SID.jsonl" <<TRANSCRIPT
{"type":"pr-link","sessionId":"$SID","prUrl":"$PR_URL","timestamp":"2026-09-01T00:00:00Z"}
TRANSCRIPT
cat > "$WORK/gh-prs.json" <<JSON
[{"url":"$PR_URL","number":42,"isDraft":true,"title":"テスト用の PR","repository":{"nameWithOwner":"someone/proj"}}]
JSON
pr=$(CLAUDE_PROJECTS_DIR="$PR_PROJECTS" GH_STUB_JSON="$WORK/gh-prs.json" "$SCRIPT" --emit 2>/dev/null)
check "PR の表示列はタイトルの前に番号を付ける" \
    "$(printf 'PR   Draft %-28s #42 テスト用の PR' someone/proj)" \
    "$(printf '%s' "$pr" | awk -F"$SEP" '{ print $1 }')"

# ---- 10 日前に触ったセッションの成果物も既定で出る ------------------------
AGED="$WORK/aged-projects"
make_projects "$AGED"
touch -t "$(date -v-10d +%Y%m%d%H%M)" "$AGED/-Users-someone-proj/$SID.jsonl"
export CLAUDE_PROJECTS_DIR="$AGED"
aged=$("$SCRIPT" --emit 2>/dev/null)
check "10 日前に触ったセッションの成果物は既定で出る" 1 \
    "$(printf '%s\n' "$aged" | grep -c "$URL")"

# ---- 成果物が無い時、--emit は何も出さずに 0 で返る ------------------------
# fzf の reload が空のリストを受け取れないと、一覧を開いたまま待てない。
export CLAUDE_PROJECTS_DIR="$WORK/no-projects"
empty=$("$SCRIPT" --emit 2>/dev/null)
rc=$?
check "成果物が無い --emit は空" "" "$empty"
check "成果物が無い --emit は 0 で返る" 0 "$rc"

# 端末が無い時は一覧を開けないので、従来どおり理由を書いて終わる
none=$("$SCRIPT" 2>/dev/null)
check "成果物が無い既定出力は理由を書く" 1 "$(printf '%s' "$none" | grep -c '開くべき成果物はありません')"

# ---- 間隔の指定は数値だけ受ける --------------------------------------------
# every(0) は 0.01 秒に丸められるので、間隔の取り違えは走査の暴走になる。
CLAUDE_OUTPUTS_INTERVAL=abc "$SCRIPT" --emit >/dev/null 2>&1
check "間隔が数値でなければ 1 で返る" 1 "$?"
CLAUDE_OUTPUTS_INTERVAL=0 "$SCRIPT" --emit >/dev/null 2>&1
check "間隔 0(自動更新なし)は受ける" 0 "$?"

# ---- 不明な引数は使い方を出して 2 で返る ----------------------------------
"$SCRIPT" --nope >/dev/null 2>&1
check "不明な引数は 2 で返る" 2 "$?"

# ---- 生きているセッションへの ctrl-o は workspace ごと画面を移す ------------
HERDR_LOG="$WORK/herdr.log"
cat > "$STUB_BIN/herdr" <<STUBEOF
#!/bin/bash
case "\$1 \$2" in
    "agent list")
        echo '{"result":{"agents":[{"agent_session":{"value":"$SID"},"pane_id":"w3A:p1","workspace_id":"w3A"}]}}' ;;
    "workspace focus"|"agent focus")
        echo "\$*" >> "$HERDR_LOG" ;;
esac
STUBEOF
chmod +x "$STUB_BIN/herdr"
: > "$HERDR_LOG"
HERDR_ENV=1 "$SCRIPT" --open-session "$SID" /Users/someone/proj >/dev/null 2>&1 </dev/null
check "生きているセッションを開くと 0 で返る" 0 "$?"
check "生きているセッションは pane を focus してから workspace へ画面を移す" \
    "$(printf 'agent focus w3A:p1\nworkspace focus w3A')" "$(cat "$HERDR_LOG")"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
