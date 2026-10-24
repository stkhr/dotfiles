#!/bin/bash
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/report-pane"
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

STUB_BIN="$WORK/bin"
NOGLOW_BIN="$WORK/noglow"
mkdir -p "$STUB_BIN" "$NOGLOW_BIN"

cat > "$STUB_BIN/herdr" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >> "$STUB_HERDR_LOG"
case "$1 $2" in
    "pane current")
        echo '{"result":{"pane":{"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1"}}}'
        ;;
    "pane list")
        echo "{\"result\":{\"panes\":[${STUB_HERDR_PANES:-}]}}"
        ;;
    "pane close")
        [ -z "${STUB_HERDR_CLOSE_FAIL:-}" ] || exit 1
        echo '{"result":{"type":"ok"}}'
        ;;
    "pane split")
        [ -z "${STUB_HERDR_SPLIT_FAIL:-}" ] || exit 1
        echo "${STUB_HERDR_SPLIT_JSON:-{\"result\":{\"pane\":{\"pane_id\":\"w1:p9\"}}}}"
        ;;
    "pane rename")
        [ -z "${STUB_HERDR_RENAME_FAIL:-}" ] || exit 1
        echo '{"result":{}}'
        ;;
    *)
        echo '{"result":{}}'
        ;;
esac
STUBEOF
printf '#!/bin/bash\n' > "$STUB_BIN/glow"
chmod +x "$STUB_BIN"/*
cp "$STUB_BIN/herdr" "$NOGLOW_BIN/herdr"
PATH="$STUB_BIN:$PATH"
export PATH

export HERDR_ENV=1
export HERDR_PANE_ID=w1:p1
export STUB_HERDR_LOG="$WORK/herdr.log"
export STUB_HERDR_PANES=""
export HOME="$WORK/home"
STYLE="$HOME/.config/glow/report-style.json"

REPORT_DIR="$WORK/scratchpad"
mkdir -p "$REPORT_DIR"
REPORT="$REPORT_DIR/inventory.md"
echo "# inventory" > "$REPORT"

reset() {
    : > "$STUB_HERDR_LOG"
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

logged() {
    grep -cxF -- "$1" "$STUB_HERDR_LOG"
}

reset
out=$("$SCRIPT" "$REPORT" 2>"$WORK/err")
check "開けたら 0 で返る" 0 "$?"
check "開いたペインとレポートを報告する" "w1:p9: $REPORT" "$out"
check "呼び出し元の右にフォーカスを移さず開く" 1 \
    "$(logged 'pane split --current --direction right --no-focus')"
check "開いたペインに report と名前を付ける" 1 "$(logged 'pane rename w1:p9 report')"
check "スタイルが無ければ glow の既定で開き、抜けたらペインごと閉じる" 1 \
    "$(logged "pane run w1:p9 glow -s 'auto' -p '$REPORT'; exit")"
check "report ペインが無ければ何も閉じない" 0 "$(grep -c '^pane close' "$STUB_HERDR_LOG")"

reset
(cd "$REPORT_DIR" && "$SCRIPT" inventory.md >/dev/null 2>&1)
check "相対パスは絶対パスにして glow に渡す" 1 \
    "$(logged "pane run w1:p9 glow -s 'auto' -p '$REPORT'; exit")"

reset
odd="$REPORT_DIR/it's レポート.md"
echo "# odd" > "$odd"
"$SCRIPT" "$odd" >/dev/null 2>&1
check "空白・引用符・日本語を含むパスをそのまま引用して渡す" 1 \
    "$(logged "pane run w1:p9 glow -s 'auto' -p '$REPORT_DIR/it'\\''s レポート.md'; exit")"

reset
mkdir -p "$(dirname "$STYLE")"
echo '{}' > "$STYLE"
"$SCRIPT" "$REPORT" >/dev/null 2>&1
check "report 用スタイルがあればそれで開く" 1 \
    "$(logged "pane run w1:p9 glow -s '$STYLE' -p '$REPORT'; exit")"
rm -f "$STYLE"

reset
STUB_HERDR_PANES='{"pane_id":"w1:p5","tab_id":"w1:t1","label":"report"},{"pane_id":"w1:p6","tab_id":"w1:t2","label":"report"},{"pane_id":"w1:p7","tab_id":"w1:t1"}' \
    "$SCRIPT" "$REPORT" >/dev/null 2>&1
check "同じタブの report ペインは閉じてから開く" 1 "$(logged 'pane close w1:p5')"
check "別タブの report ペインは閉じない" 0 "$(logged 'pane close w1:p6')"
check "名前の無いペインは閉じない" 0 "$(logged 'pane close w1:p7')"
check "閉じるのは split より前" "pane close w1:p5" \
    "$(grep -E '^pane (close|split)' "$STUB_HERDR_LOG" | head -1)"

reset
STUB_HERDR_CLOSE_FAIL=1 STUB_HERDR_PANES='{"pane_id":"w1:p5","tab_id":"w1:t1","label":"report"}' \
    "$SCRIPT" "$REPORT" >/dev/null 2>&1
check "古いペインを閉じられなければ 1 で返る" 1 "$?"
check "古いペインを閉じられなければ新しく開かない" 0 "$(grep -c '^pane split' "$STUB_HERDR_LOG")"

reset
out=$(STUB_HERDR_SPLIT_FAIL=1 "$SCRIPT" "$REPORT" 2>/dev/null)
check "split が失敗したら 1 で返る" 1 "$?"
check "split が失敗したら開いたと報告しない" "" "$out"
check "split が失敗したら名前付けも glow もしない" 0 "$(grep -cE '^pane (rename|run)' "$STUB_HERDR_LOG")"

reset
out=$(STUB_HERDR_SPLIT_JSON='{"result":{}}' "$SCRIPT" "$REPORT" 2>/dev/null)
check "pane_id が無ければ 1 で返る" 1 "$?"
check "pane_id が無ければ開いたと報告しない" "" "$out"
check "pane_id が無ければ glow を走らせない" 0 "$(grep -c '^pane run' "$STUB_HERDR_LOG")"

reset
out=$(STUB_HERDR_RENAME_FAIL=1 "$SCRIPT" "$REPORT" 2>/dev/null)
check "名前を付けられなければ 1 で返る" 1 "$?"
check "名前を付けられなければ開いたペインを閉じる" 1 "$(logged 'pane close w1:p9')"
check "名前を付けられなければ glow を走らせない" 0 "$(grep -c '^pane run' "$STUB_HERDR_LOG")"

reset
PATH="$NOGLOW_BIN:/usr/bin:/bin" "$SCRIPT" "$REPORT" >/dev/null 2>&1
check "glow が無ければ 1 で返る" 1 "$?"
check "glow が無ければ herdr を呼ばない" 0 "$(grep -c . "$STUB_HERDR_LOG")"

reset
"$SCRIPT" "$WORK/missing.md" >/dev/null 2>&1
check "レポートが無ければ 1 で返る" 1 "$?"
check "レポートが無ければ herdr を呼ばない" 0 "$(grep -c . "$STUB_HERDR_LOG")"

reset
"$SCRIPT" >/dev/null 2>&1
check "引数が無ければ 1 で返る" 1 "$?"
check "引数が無ければ herdr を呼ばない" 0 "$(grep -c . "$STUB_HERDR_LOG")"

reset
"$SCRIPT" "$REPORT" "$REPORT" >/dev/null 2>&1
check "引数が2つ以上なら 1 で返る" 1 "$?"
check "引数が2つ以上なら herdr を呼ばない" 0 "$(grep -c . "$STUB_HERDR_LOG")"

reset
"$SCRIPT" --nope >/dev/null 2>&1
check "不明なオプションは 1 で返る" 1 "$?"
check "不明なオプションは herdr を呼ばない" 0 "$(grep -c . "$STUB_HERDR_LOG")"

reset
HERDR_ENV='' "$SCRIPT" "$REPORT" >/dev/null 2>&1
check "herdr の外では 1 で返る" 1 "$?"
check "herdr の外では herdr を呼ばない" 0 "$(grep -c . "$STUB_HERDR_LOG")"

reset
HERDR_PANE_ID='' "$SCRIPT" "$REPORT" >/dev/null 2>&1
check "呼び出し元のペイン ID が無ければ 1 で返る" 1 "$?"
check "呼び出し元のペイン ID が無ければ herdr を呼ばない" 0 "$(grep -c . "$STUB_HERDR_LOG")"

margins=$(jq -c '[.document.margin, .code_block.margin]' "$(dirname "$SCRIPT")/../config/glow/report-style.json")
check "同梱のスタイルは文書とコードブロックの余白が 0" "[0,0]" "$margins"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
