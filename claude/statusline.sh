#!/bin/bash

# Claude Code Statusline Script
# コンテキストウィンドウの使用状況を表示します

# stdin から JSON データを読み取る
INPUT=$(cat)

# transcript_path から実際のトークン使用量を取得
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # transcript.json からトークン使用量を計算
    USED=$(jq '[.[] | select(.role == "user" or .role == "assistant") | .content // [] | if type == "array" then .[] else . end | select(.type == "text" or type == "tool_use" or type == "tool_result") | .text // .input // .content // "" | length] | add // 0' "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")
    # おおよその換算（4文字 ≒ 1トークン）
    USED=$((USED / 4))
else
    USED=0
fi

# モデルの最大トークン数（一般的な値）
TOTAL=200000

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
