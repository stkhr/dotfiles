#!/bin/bash
# Tests for herdr-space。gh / herdr / ghq / fzf を PATH のスタブに差し替え、
# herdr に渡した引数はログに落として検証する。
# Usage: bash bin/tests/test-herdr-space.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/herdr-space"
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

STUB_BIN="$WORK/bin"
mkdir -p "$STUB_BIN"

cat > "$STUB_BIN/gh" <<'STUBEOF'
#!/bin/bash
[ -z "${STUB_GH_FAIL:-}" ] || exit 1
printf 'acme\nglobex\n'
STUBEOF

cat > "$STUB_BIN/ghq" <<'STUBEOF'
#!/bin/bash
echo "$STUB_GHQ_ROOT"
STUBEOF

cat > "$STUB_BIN/fzf" <<'STUBEOF'
#!/bin/bash
cat >/dev/null
[ -z "${STUB_FZF_CANCEL:-}" ] || exit 130
echo "$STUB_FZF_PICK"
STUBEOF

cat > "$STUB_BIN/herdr" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >> "$STUB_HERDR_LOG"
case "$1 $2" in
    "workspace list")
        printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"%s"}]}}\n' "$STUB_HERDR_EXISTING"
        ;;
    "workspace create")
        echo "${STUB_HERDR_CREATE_JSON:-{\"result\":{\"workspace\":{\"workspace_id\":\"w9\"}}}}"
        ;;
    "workspace focus")
        echo '{"result":{}}'
        ;;
esac
STUBEOF
chmod +x "$STUB_BIN"/*
PATH="$STUB_BIN:$PATH"
export PATH

export HERDR_ENV=1
export STUB_GHQ_ROOT="$WORK/ghq"
export STUB_HERDR_LOG="$WORK/herdr.log"
export STUB_HERDR_EXISTING=""
export STUB_FZF_PICK=""

reset() {
    : > "$STUB_HERDR_LOG"
    rm -rf "$STUB_GHQ_ROOT"
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

# ---- 引数の org で space を作る ---------------------------------------------
reset
out=$("$SCRIPT" acme 2>"$WORK/err")
check "作成時は 0 で返る" 0 "$?"
check "作成した workspace_id を報告する" "acme: w9 を作成" "$out"
check "cwd と label を org で渡す" 1 \
    "$(grep -c "^workspace create --cwd $STUB_GHQ_ROOT/github.com/acme --label acme --focus\$" "$STUB_HERDR_LOG")"
check "cwd を作っておく" 1 "$([ -d "$STUB_GHQ_ROOT/github.com/acme" ] && echo 1 || echo 0)"

# ---- 同じ label の space があれば作らず移動する -----------------------------
reset
out=$(STUB_HERDR_EXISTING=acme "$SCRIPT" acme 2>/dev/null)
check "既存なら 0 で返る" 0 "$?"
check "既存の workspace_id を報告する" "acme: w1 へ移動" "$out"
check "既存なら focus だけ呼ぶ" 1 "$(grep -c '^workspace focus w1$' "$STUB_HERDR_LOG")"
check "既存なら create を呼ばない" 0 "$(grep -c '^workspace create' "$STUB_HERDR_LOG")"
check "既存なら cwd を作らない" 0 "$([ -d "$STUB_GHQ_ROOT" ] && echo 1 || echo 0)"

# ---- 引数を省くと fzf の選択で作る ------------------------------------------
reset
out=$(STUB_FZF_PICK=globex "$SCRIPT" 2>/dev/null)
check "fzf で選んだ org を使う" "globex: w9 を作成" "$out"

reset
STUB_FZF_CANCEL=1 "$SCRIPT" >/dev/null 2>&1
check "fzf を抜けると 1 で返る" 1 "$?"
check "fzf を抜けると herdr を呼ばない" 0 "$(grep -c . "$STUB_HERDR_LOG")"

# ---- 所属していない org や誤った引数は herdr に渡さない ---------------------
reset
"$SCRIPT" typo >/dev/null 2>&1
check "所属していない org は 1 で返る" 1 "$?"
check "所属していない org は herdr を呼ばない" 0 "$(grep -c . "$STUB_HERDR_LOG")"
check "所属していない org は cwd を作らない" 0 "$([ -d "$STUB_GHQ_ROOT" ] && echo 1 || echo 0)"

reset
"$SCRIPT" --nope >/dev/null 2>&1
check "不明なオプションは 1 で返る" 1 "$?"
check "不明なオプションは herdr を呼ばない" 0 "$(grep -c . "$STUB_HERDR_LOG")"

# ---- gh が失敗したら fzf を開かずに終わる -----------------------------------
reset
STUB_GH_FAIL=1 "$SCRIPT" >/dev/null 2>&1
check "gh の失敗は 1 で返る" 1 "$?"
check "gh の失敗は herdr を呼ばない" 0 "$(grep -c . "$STUB_HERDR_LOG")"

# ---- herdr の応答に workspace_id が無ければ成功と言わない -------------------
reset
out=$(STUB_HERDR_CREATE_JSON='{"result":{}}' "$SCRIPT" acme 2>/dev/null)
rc=$?
check "workspace_id が無ければ 1 で返る" 1 "$rc"
check "workspace_id が無ければ作成を報告しない" "" "$out"

# ---- herdr のペイン外では動かない -------------------------------------------
reset
HERDR_ENV='' "$SCRIPT" acme >/dev/null 2>&1
check "HERDR_ENV が無ければ 1 で返る" 1 "$?"
check "HERDR_ENV が無ければ herdr を呼ばない" 0 "$(grep -c . "$STUB_HERDR_LOG")"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
