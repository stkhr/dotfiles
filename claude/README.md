# Claude Code グローバル設定管理

Claude Code のグローバル設定一式を dotfiles で管理し、`install.sh` で実際の読み込み場所
（`~/.claude/` 配下）へシンボリックリンクを配置する。

## ディレクトリ構成

```
claude/
├── settings.json    # グローバル設定（permissions / hooks / statusline / plugins）
├── CLAUDE.md        # グローバルプロンプト（全プロジェクト共通ガイドライン）
├── statusline.sh    # ステータスライン表示スクリプト
├── crit-review.sh   # crit レビュー TUI 起動ラッパー（tmux / herdr 対応）
├── mcp-setup.sh     # MCPサーバー登録スクリプト
├── hooks/           # フックスクリプト
├── skills/          # カスタムスキル
├── agents/          # カスタムサブエージェント
└── README.md        # この説明ファイル
```

## セットアップ

リポジトリルートで `./install.sh` を実行すると以下が行われる:

| 対象 | リンク先 / 処理 |
|---|---|
| `claude/settings.json` | `~/.claude/settings.json` |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `claude/statusline.sh` | `~/.claude/statusline.sh` |
| `claude/crit-review.sh` | `~/.claude/crit-review.sh` |
| `claude/hooks/*.sh` | `~/.claude/hooks/`（個別リンク + `chmod +x`） |
| `claude/skills/*/` | `~/.claude/skills/`（ディレクトリ単位でリンク） |
| `claude/agents/*.md` | `~/.claude/agents/`（個別リンク） |
| `claude/mcp-setup.sh` | 実行（MCPサーバーを user スコープで登録） |
| plugins | marketplace 登録 + `claude plugin install`（後述） |
| supabase skills | `npx skills add supabase/agent-skills`（`~/.agents/skills/` 配下） |

**注意**: `~/.claude` 自体はシンボリックリンクにしない（実体ディレクトリの中に
ファイル単位でリンクを置く）。Claude Code はこのディレクトリに履歴・キャッシュ等の
ランタイムファイルを書き込むため、ディレクトリ丸ごとのリンクにするとそれらが
リポジトリに混入する。install.sh の除外リストはこの前提を守っている。

## MCPサーバー

`mcp-setup.sh` が `claude mcp add --scope user` で登録する（設定の実体は
`~/.claude.json` のトップレベル `mcpServers` に保存される）。

| サーバー | 用途 | 実行方式 |
|---|---|---|
| serena | コード解析・シンボル検索 | docker（`~/ghq` をマウント） |
| chrome-devtools | ブラウザ操作・DevTools連携 | npx（バージョンピン留め） |
| context7 | ライブラリドキュメント検索 | npx（バージョンピン留め） |
| playwright | E2E・ブラウザ自動化 | npx（バージョンピン留め） |
| drawio | 図の生成・編集 | npx（バージョンピン留め） |
| notion | Notion連携 | HTTP（`https://mcp.notion.com/mcp`） |
| aws | AWS API操作（SigV4認証） | uvx `mcp-proxy-for-aws`（要 `brew install uv`） |

- user スコープで登録したサーバーは登録した時点で有効になる
- バージョンを上げる場合は `mcp-setup.sh` のピン留めを更新し、
  `claude mcp remove <name>` してから再実行する（`claude mcp add` は同名サーバーが
  あるとエラーになる）
- 確認: `claude mcp list` または Claude Code 内で `/mcp`

GitHub 操作は MCP ではなく `gh` CLI を使う方針のため、GitHub MCP サーバーは登録しない
（CLAUDE.md 参照）。

## Hooks

`settings.json` の `hooks` セクションから `~/.claude/hooks/` のスクリプトを呼び出す。

| スクリプト | イベント | 役割 |
|---|---|---|
| `protect-main-branch.sh` | PreToolUse (Bash) | main/master への `git commit` をブロック |
| `guard-worktree-path.sh` | PreToolUse (Bash) | worktree をリポジトリ外に作らせない |
| `confirm-hard-gate.sh` | PreToolUse (Bash) | git/gh の破壊的操作に確認プロンプトを強制 |
| `lint-feedback.sh` | PostToolUse (Edit\|Write) | 編集ファイルを lint し、エラーをモデルにフィードバック |
| `format-on-edit.sh` | PostToolUse (Edit\|Write) | prettier / black / gofmt / terraform fmt による自動整形 |
| `notify-pr-created.sh` | PostToolUse (Bash) | `gh pr create` 実行時に PR URL を通知 |
| `precompact-context.sh` | PreCompact | git の作業状態を compaction サマリに注入 |
| `verify-completion-claims.sh` | Stop | 完了報告と実際の作業状態の突き合わせ |
| `verify-tests.sh` | Stop | 応答完了時のテスト検証 |
| `session-sync.sh` | Stop | セッション状態の同期 |

hook のテストは `hooks/tests/` 配下に置く。

このほか settings.json 内のインラインフックとして、macOS通知（`osascript` による
Notification / Stop 通知）を設定している。

## Skills / Agents

- カスタムスキルは `claude/skills/<name>/SKILL.md` 形式。install.sh がディレクトリ単位で
  `~/.claude/skills/` にリンクする
- カスタムエージェントは `claude/agents/<name>.md` 形式（frontmatter に name /
  description / tools / model を記述）
- 追加・削除したら install.sh を再実行する。リポジトリ側でファイルを削除した場合、
  `~/.claude/` 側に壊れたリンクが残るので手動で削除する

確認: Claude Code 内で `/agents`、スキルは会話中の available-skills 一覧に表示される。

## Plugins

install.sh が marketplace を登録し、以下をインストールする
（`settings.json` の `enabledPlugins` / `extraKnownMarketplaces` と対応）:

- `superpowers` / `frontend-design` / `context7` / `security-guidance`（anthropics/claude-plugins-official）
- `terraform-code-generation` / `terraform-module-generation` / `terraform-provider-development`（hashicorp/agent-skills）
- `crit`（kevindutra/crit）

## crit レビューラッパー

CLAUDE.md のレビューゲートは `crit review` を直接ではなく `crit-review.sh <file>` 経由で
起動する。crit 本体の `--detach`（TUI を隣ペインに開く機能）が tmux 専用のため、
ラッパーが実行環境を判別して同じ体験を提供する:

- tmux 内（`$TMUX`）: `crit review <file> --detach --wait` にそのまま委譲
- herdr 内（`$HERDR_PANE_ID`）: `herdr pane split` で隣ペインを作り TUI を起動、
  終了マーカーの出力を `herdr wait output` で待つ（`--detach --wait` 相当）
- どちらでもない: エラー終了し、手動実行を促す

待ち時間の上限は 540000ms（env `CRIT_REVIEW_TIMEOUT_MS` で変更可）。
herdr フローは `jq` に依存する。

## Statusline

`statusline.sh` がコンテキストウィンドウ使用率をプログレスバー表示する。

- stdin で渡される JSON の `context_window` からトークン使用量を計算
- 使用率で色分け: 緑 (<50%) / 黄 (<75%) / 赤 (<90%) / マゼンタ + ⚠️ (90%以上)
- `settings.json` の `statusLine`（L は大文字）で有効化済み

## 動作確認

```bash
# シンボリックリンクの確認
ls -la ~/.claude/settings.json ~/.claude/CLAUDE.md ~/.claude/statusline.sh
ls -la ~/.claude/hooks ~/.claude/skills ~/.claude/agents

# MCPサーバーの確認
claude mcp list

# 通知経路の確認（osascript は macOS 標準）
osascript -e 'display notification "test" with title "Claude Code" sound name "Glass"'
```
