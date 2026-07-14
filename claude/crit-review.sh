#!/bin/bash
# crit のレビュー TUI を tmux / herdr のどちらの環境でも隣ペインに開くラッパー。
# crit 本体の --detach は tmux 専用のため、herdr では socket API でペインを分割して
# TUI を起動し、終了マーカーの出力を待つことで --detach --wait 相当を再現する。
# レビュー完了後のコメント取得は従来どおり呼び出し側で `crit status <file>` を実行する。

set -uo pipefail

FILE="${1:-}"
if [ -z "$FILE" ]; then
  echo "usage: crit-review.sh <file>" >&2
  exit 2
fi

if ! command -v crit >/dev/null 2>&1; then
  echo "crit-review: crit が見つかりません（dotfiles の install.sh で導入されます）" >&2
  exit 127
fi

# レビュー完了待ちの上限(ms)。呼び出し側の Bash timeout(600000ms)より短くして、
# タイムアウト時もこのスクリプト自身がエラーを報告して終われるようにする
WAIT_TIMEOUT_MS="${CRIT_REVIEW_TIMEOUT_MS:-540000}"

# tmux 内(herdr のペインで tmux を起動している場合を含む)は crit 標準の統合に委譲する
if [ -n "${TMUX:-}" ]; then
  exec crit review "$FILE" --detach --wait
fi

if [ -n "${HERDR_PANE_ID:-}" ] && command -v herdr >/dev/null 2>&1; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "crit-review: herdr フローには jq が必要です" >&2
    exit 127
  fi

  PANE=$(herdr pane split --pane "$HERDR_PANE_ID" --direction right --cwd "$PWD" --no-focus 2>/dev/null \
    | jq -r '.result.pane.pane_id // empty')
  if [ -z "$PANE" ]; then
    echo "crit-review: herdr ペインの分割に失敗しました" >&2
    exit 1
  fi

  # TUI 終了後に「MARKER=<exit code>」を出力させて完了を検知する。pane run で送った
  # コマンド行自体もペインにエコーされるため、送信文字列側はクォートでマーカーを
  # 分断し、完成形のマーカーが出力にしか現れないようにする
  MARKER="CRIT_REVIEW_EXIT"
  herdr pane run "$PANE" "crit review $(printf '%q' "$FILE"); printf '%s=%s\n' 'CRIT_''REVIEW_EXIT' \"\$?\""

  if ! herdr wait output "$PANE" --match "${MARKER}=" --timeout "$WAIT_TIMEOUT_MS" >/dev/null 2>&1; then
    echo "crit-review: レビュー完了待ちがタイムアウトしました（ペイン $PANE で TUI が開いたままの可能性があります）" >&2
    exit 124
  fi

  RC=$(herdr pane read "$PANE" --source recent-unwrapped --lines 50 2>/dev/null \
    | grep -oE "${MARKER}=[0-9]+" | tail -1 | cut -d= -f2)
  if [ -z "$RC" ]; then
    # マーカーは検知済みなのでレビュー完了として扱い、内容の確認は crit status に委ねる
    echo "crit-review: 終了コードを取得できませんでした（レビューは完了扱い）" >&2
    exit 0
  fi
  exit "$RC"
fi

echo "crit-review: tmux / herdr のどちらでもない環境です。別ターミナルで手動実行してください: crit review $FILE" >&2
exit 1
