#!/bin/bash

# Claude Code Statusline Script
# コンテキストウィンドウの使用状況を表示します

# stdin から JSON データを読み取る
INPUT=$(cat)

# context_window からトークン情報を取得
CONTEXT_SIZE=$(echo "$INPUT" | jq -r '.context_window.context_window_size // 200000')
USAGE=$(echo "$INPUT" | jq '.context_window.current_usage')

if [ "$USAGE" != "null" ] && [ -n "$USAGE" ]; then
    # 現在のコンテキスト使用量を計算
    USED=$(echo "$USAGE" | jq '.input_tokens + .output_tokens + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)')
else
    USED=0
fi

# 数値が取得できなかった場合のフォールバック
if [ -z "$USED" ] || [ "$USED" = "null" ]; then
    USED=0
fi

TOTAL=$CONTEXT_SIZE

# 使用率を計算
if [ "$TOTAL" -gt 0 ]; then
    PERCENTAGE=$((USED * 100 / TOTAL))
else
    PERCENTAGE=0
fi

# 色付けのための関数
get_color() {
    local percent=$1
    if [ "$percent" -lt 50 ]; then
        echo "32" # 緑
    elif [ "$percent" -lt 75 ]; then
        echo "33" # 黄色
    elif [ "$percent" -lt 90 ]; then
        echo "31" # 赤
    else
        echo "35" # マゼンタ (警告)
    fi
}

# バーの表示
get_bar() {
    local percent=$1
    local width=20
    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    printf "["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "]"
}

COLOR=$(get_color "$PERCENTAGE")
BAR=$(get_bar "$PERCENTAGE")

# ステータスラインを出力
printf "\033[%sm%s %d%% (%s / %s tokens)\033[0m" \
    "$COLOR" \
    "$BAR" \
    "$PERCENTAGE" \
    "$(printf "%'d" "$USED")" \
    "$(printf "%'d" "$TOTAL")"

# 90%を超えたら警告アイコンを追加
if [ "$PERCENTAGE" -ge 90 ]; then
    printf " ⚠️  "
fi
