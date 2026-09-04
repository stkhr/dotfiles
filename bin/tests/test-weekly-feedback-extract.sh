#!/bin/bash
# Tests for weekly-feedback-extract の日付選択とマーカー(未処理日の追いかけ)。
# claude 本体は WEEKLY_FEEDBACK_CLAUDE_BIN で差し替え、抽出結果の中身は検証しない。
# Usage: bash bin/tests/test-weekly-feedback-extract.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/weekly-feedback-extract"
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

TODAY=$(date +%Y-%m-%d)
D1=$(date -j -v-3d -f '%Y-%m-%d' "$TODAY" '+%Y-%m-%d')
D2=$(date -j -v-2d -f '%Y-%m-%d' "$TODAY" '+%Y-%m-%d')
D3=$(date -j -v-1d -f '%Y-%m-%d' "$TODAY" '+%Y-%m-%d')

VAULT="$WORK/vault"
for d in "$D1" "$D2" "$D3"; do
    mkdir -p "$VAULT/03_Claude/$d"
    printf 'session log for %s\n' "$d" > "$VAULT/03_Claude/$d/proj.md"
done

# メモリ側は対象外にしたいので、存在しないディレクトリを指す
export CLAUDE_PROJECTS_DIR="$WORK/no-projects"
export OBSIDIAN_VAULT="$VAULT"

STUB="$WORK/stub-claude"
cat > "$STUB" <<'STUBEOF'
#!/bin/bash
cat > /dev/null
if [ -n "${STUB_FAIL:-}" ]; then
    echo "stub failure" >&2
    exit 1
fi
echo "### 決定・判断"
echo "- stub"
STUBEOF
chmod +x "$STUB"
export WEEKLY_FEEDBACK_CLAUDE_BIN="$STUB"

check() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        printf 'ok   %s\n' "$label"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$label" "$expected" "$actual"
    fi
}

marker_of() { cat "$1/.last-extracted" 2>/dev/null || echo "<none>"; }

# --- 初回はマーカーが無いので当日だけを見る(履歴を勝手に遡らない) ---
OUT1="$WORK/out1"
WEEKLY_FEEDBACK_DIR="$OUT1" bash "$SCRIPT" >/dev/null 2>&1
check "初回はマーカー無しで過去日を処理しない" "<none>" "$(marker_of "$OUT1")"
check "初回は週ファイルを作らない" "0" "$(find "$OUT1" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"

# --- --since で明示的に遡る ---
OUT2="$WORK/out2"
WEEKLY_FEEDBACK_DIR="$OUT2" bash "$SCRIPT" --since "$D1" >/dev/null 2>&1
check "--since で3日ぶん処理してマーカーが最終日になる" "$D3" "$(marker_of "$OUT2")"
check "処理した日の見出しが3つある" "3" "$(grep -c '^## 20' "$OUT2"/*.md 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')"

WEEK_D1=$(date -j -f '%Y-%m-%d' "$D1" '+%G-W%V')
check "ISO週でファイル名が決まる" "0" "$(test -f "$OUT2/$WEEK_D1.md" && echo 0 || echo 1)"

# --- マーカーがあれば処理済みの日を二重に追記しない ---
BEFORE=$(cat "$OUT2"/*.md | wc -c | tr -d ' ')
WEEKLY_FEEDBACK_DIR="$OUT2" bash "$SCRIPT" >/dev/null 2>&1
AFTER=$(cat "$OUT2"/*.md | wc -c | tr -d ' ')
check "再実行しても追記されない" "$BEFORE" "$AFTER"

# --- 抽出が失敗したらマーカーを進めない(次回その日から再開する) ---
OUT3="$WORK/out3"
STUB_FAIL=1 WEEKLY_FEEDBACK_DIR="$OUT3" bash "$SCRIPT" --since "$D1" >/dev/null 2>&1
check "抽出失敗時はマーカーを進めない" "<none>" "$(marker_of "$OUT3")"

# --- ロックが残っていても、生きたプロセスが無ければ実行する ---
OUT4="$WORK/out4"
mkdir -p "$OUT4"
mkdir "$OUT4/.lock"
echo "99999999" > "$OUT4/.lock/pid"
WEEKLY_FEEDBACK_DIR="$OUT4" bash "$SCRIPT" --since "$D1" >/dev/null 2>&1
check "死んだプロセスのロックは奪って実行する" "$D3" "$(marker_of "$OUT4")"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
