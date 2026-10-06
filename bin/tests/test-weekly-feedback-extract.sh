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

# 実運用の Vault パスは空白を含む(Obsidian Vault)。単語分割の回帰を踏むためここも空白入りにする
VAULT="$WORK/Obsidian Vault"
for d in "$D1" "$D2" "$D3"; do
    mkdir -p "$VAULT/03_Claude/$d"
    printf 'session log for %s\n' "$d" > "$VAULT/03_Claude/$d/proj.md"
done

# メモリ側は対象外にしたいので、存在しないディレクトリを指す
export CLAUDE_PROJECTS_DIR="$WORK/no-projects"
export OBSIDIAN_VAULT="$VAULT"

# stub は受け取った stdin を残す。空入力でも「抽出成功」に見えてしまう事故を検知する
export STUB_STDIN="$WORK/stub-stdin"
STUB="$WORK/stub-claude"
cat > "$STUB" <<'STUBEOF'
#!/bin/bash
cat >> "$STUB_STDIN"
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

# 空白入りパスのセッションログが実際に claude へ渡っているか(単語分割の回帰)
check "空白を含むパスのセッションログが入力に載る" "3" \
    "$(grep -c '^===== SESSION: proj.md =====$' "$STUB_STDIN" 2>/dev/null || echo 0)"
check "セッションログの中身が入力に載る" "3" \
    "$(grep -c '^session log for 20' "$STUB_STDIN" 2>/dev/null || echo 0)"

# --- マーカーがあれば処理済みの日を二重に追記しない ---
BEFORE=$(cat "$OUT2"/*.md | wc -c | tr -d ' ')
WEEKLY_FEEDBACK_DIR="$OUT2" bash "$SCRIPT" >/dev/null 2>&1
AFTER=$(cat "$OUT2"/*.md | wc -c | tr -d ' ')
check "再実行しても追記されない" "$BEFORE" "$AFTER"

# --- --since はマーカーを無視するので、処理済みの日を再度渡しても重複しない ---
WEEKLY_FEEDBACK_DIR="$OUT2" bash "$SCRIPT" --since "$D1" >/dev/null 2>&1
check "--since で再処理しても日の見出しは増えない" "3" \
    "$(grep -c '^## 20' "$OUT2"/*.md 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')"
check "--since で再処理しても内容は1日1回ぶん" "3" \
    "$(grep -c '^- stub$' "$OUT2"/*.md 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')"

# --- 進行中の当日はマーカーを進めない(あとで積まれるログを取りこぼさない) ---
OUT5="$WORK/out5"
mkdir -p "$VAULT/03_Claude/$TODAY"
printf 'session log for %s\n' "$TODAY" > "$VAULT/03_Claude/$TODAY/proj.md"
WEEKLY_FEEDBACK_DIR="$OUT5" bash "$SCRIPT" --since "$TODAY" >/dev/null 2>&1
check "当日を処理してもマーカーは進めない" "<none>" "$(marker_of "$OUT5")"
WEEK_TODAY=$(date -j -f '%Y-%m-%d' "$TODAY" '+%G-W%V')
check "当日の抽出結果は書かれている" "1" \
    "$(grep -c "^## $TODAY\$" "$OUT5/$WEEK_TODAY.md" 2>/dev/null || echo 0)"
WEEKLY_FEEDBACK_DIR="$OUT5" bash "$SCRIPT" --since "$TODAY" >/dev/null 2>&1
check "当日を再処理しても重複しない" "1" \
    "$(grep -c "^## $TODAY\$" "$OUT5/$WEEK_TODAY.md" 2>/dev/null || echo 0)"

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

VAULT6="$WORK/vault6"
DAY6="$VAULT6/03_Claude/$D1"
mkdir -p "$DAY6"
printf '# z\n\n## 15:00:00\n\nlate\n' > "$DAY6/z-proj--33333333.md"
printf '# c\n\nno header\n' > "$DAY6/c-nohdr.md"
printf '# a\n\n## 12:00:00\n\nnoon\n' > "$DAY6/a-proj--11111111.md"
printf '# b\n\n## 13:00:00\n\nfirst\n\n## 08:00:00\n\nsecond\n' > "$DAY6/b-old.md"
printf '# n\n\n## 07:00:00\n\nnul\0byte\n' > "$DAY6/n-bin--44444444.md"
printf '# m\n\n## 09:00:00\n\nmorning\n' > "$DAY6/m-proj--22222222.md"
STUB_STDIN="$WORK/stub-stdin-order" OBSIDIAN_VAULT="$VAULT6" WEEKLY_FEEDBACK_DIR="$WORK/out6" \
    bash "$SCRIPT" --since "$D1" >/dev/null 2>&1
check "セッションは最初の開始時刻の順に入力に載り、時刻の無いものは最後" \
    "n-bin--44444444.md|m-proj--22222222.md|a-proj--11111111.md|b-old.md|z-proj--33333333.md|c-nohdr.md" \
    "$(sed -n 's/^===== SESSION: \(.*\) =====$/\1/p' "$WORK/stub-stdin-order" 2>/dev/null | paste -sd '|' -)"

VAULT7="$WORK/vault7"
mkdir -p "$VAULT7/03_Claude/$D1" "$WORK/projects7/p/memory"
head -c 2000 /dev/zero | tr '\0' 'x' > "$VAULT7/03_Claude/$D1/big--55555555.md"
printf 'memory note survives\n' > "$WORK/projects7/p/memory/note.md"
touch -t "$(date -j -f '%Y-%m-%d' "$D1" '+%Y%m%d')1200" "$WORK/projects7/p/memory/note.md"
STUB_STDIN="$WORK/stub-stdin-cap" OBSIDIAN_VAULT="$VAULT7" CLAUDE_PROJECTS_DIR="$WORK/projects7" \
    WEEKLY_FEEDBACK_MAX_BYTES=500 WEEKLY_FEEDBACK_DIR="$WORK/out7" bash "$SCRIPT" --since "$D1" >/dev/null 2>&1
check "入力上限で切り詰めてもメモリは残る" "1" "$(grep -c '^memory note survives$' "$WORK/stub-stdin-cap" 2>/dev/null || echo 0)"
check "入力上限で切り詰めるのはセッションの側" "1" "$(grep -c '入力上限のため省略' "$WORK/stub-stdin-cap" 2>/dev/null || echo 0)"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
