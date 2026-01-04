# Claude グローバル設定管理

## 管理

### 1. バージョン管理とバックアップ

dotfilesリポジトリで管理:

```
~/dotfiles/
├── claude/
│   ├── config.json      # Claude Codeグローバル設定
│   ├── mcp.json         # MCPサーバー設定
│   ├── CLAUDE.md        # グローバルプロンプト
│   └── README.md        # この説明ファイル
└── install.sh           # シンボリックリンク作成スクリプト
```

セットアップスクリプト:

```bash
# install.shで以下が実行される
ln -sf ~/dotfiles/claude/config.json ~/.claude/config.json
ln -sf ~/dotfiles/claude/mcp.json ~/.claude/mcp.json
ln -sf ~/dotfiles/claude/CLAUDE.md ~/.claude/CLAUDE.md
```

### 2. 環境変数の活用

機密情報は環境変数で参照:

```json
"env": {
  "API_KEY": "${MY_API_KEY}"
}
```

### 3. コメントの代わりにドキュメント化

JSONはコメント不可のため、別ファイルで管理:

```
~/.claude/
├── config.json
└── README.md  # 設定の説明
```

### 4. 段階的な設定

- 最小限の設定から始める
- 必要に応じて追加

### 5. 定期的な見直し

- 使っていないMCPサーバーの削除
- 新機能の設定追加
- 不要な設定の削除

## 機能設定

### Statusline（コンテキストウィンドウ使用率表示）

トークン使用量をリアルタイムで可視化するステータスライン機能を提供します。

#### 設定ファイル

`~/.claude/statusline.sh` にスクリプトが配置されています。

#### 機能

- トークン使用量をプログレスバーで表示
- 使用率に応じた色分け:
  - 緑: 0-49%
  - 黄色: 50-74%
  - 赤: 75-89%
  - マゼンタ: 90%以上（警告）
- 90%を超えると警告アイコン（⚠️）を表示

#### セットアップ

`~/.claude/config.json` に以下を追加:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 0
  }
}
```

**重要**: プロパティ名は `statusLine` (大文字のL) です。

dotfilesの `claude/config.json` には既に設定済みです。install.sh実行でシンボリックリンクが作成されます。

#### 動作原理

- Claude Code から **stdin 経由で JSON データ**が渡されます
- スクリプトは `transcript_path` からトークン使用量を計算します
- 計算結果を **stdout の最初の行**として出力します
- ANSI カラーコードによる色付けがサポートされています

### 自動承認設定

開発体験を向上させるため、安全な読み取り専用操作を自動承認しています。

#### WebFetch / WebSearch

Web検索とWebページの取得を自動承認:

```json
{
  "permissions": {
    "allow": [
      "WebFetch(**)",
      "WebSearch(**)"
    ]
  }
}
```

これにより、以下の操作が自動的に実行されます:
- 技術ドキュメントの検索
- ライブラリの公式ドキュメント参照
- Stack Overflowなどの技術情報取得

#### MCPサーバーの自動承認

各MCPサーバーのツールを自動承認:

```json
{
  "permissions": {
    "allow": [
      "mcp__github__*",
      "mcp__chrome-devtools__*",
      "mcp__serena__*",
      "mcp__context7__*",
      "mcp__playwright__*"
    ]
  }
}
```

### 音声通知

作業完了時やプロンプト表示時に音声通知を送信します。

#### Stop通知

Claude Codeの応答が完了した時に通知:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "terminal-notifier -title \"Claude Code\" -message \"作業が完了しました\" -sound Glass"
          }
        ]
      }
    ]
  }
}
```

#### Notification通知

入力待ちプロンプトが表示された時に通知:

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "terminal-notifier -title \"Claude Code\" -message \"入力待ちプロンプトが表示されました\" -sound default"
          }
        ]
      }
    ]
  }
}
```

**要件**: macOS の `terminal-notifier` が必要です。

インストール:
```bash
brew install terminal-notifier
```

## MCPサーバー設定

### 設定ファイルの配置

**重要**: Claude CodeはMCP設定を`~/.claude.json`の`mcpServers`セクションから読み込みます。
dotfilesで管理している`claude/mcp.json`はリファレンス用です。

- **Claude Code実際の設定場所**: `~/.claude.json` の `mcpServers` セクション
- **dotfiles管理用**: `~/dotfiles/claude/mcp.json`（リファレンス）
- **VSCode Extension**: `~/Library/Application Support/Code/User/mcp.json`
- **Amazon Q**: `~/.aws/amazonq/mcp.json`

### 有効化されているMCPサーバー

1. **serena**: コード解析・シンボル検索・リファクタリング支援
2. **github**: GitHub統合（Issues、PR、Repository操作）
3. **chrome-devtools**: Chrome DevToolsとの連携・ブラウザ操作
4. **context7**: 技術ドキュメント検索（React、Next.js、TypeScriptなど）
5. **playwright**: E2Eテスト自動化・ブラウザ操作

### 初回セットアップ手順

#### 1. 環境変数の設定

GitHub MCPサーバーを使用するには、Personal Access Tokenが必要です:

```bash
# ~/.zshrc または ~/.bashrc に追加
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_xxxxxxxxxxxxx"
```

**GitHub Personal Access Tokenの作成**:
1. https://github.com/settings/tokens にアクセス
2. "Generate new token (classic)" をクリック
3. 必要なスコープを選択:
   - `repo` (フルアクセス)
   - `read:org` (Organization情報の読み取り)
   - `workflow` (GitHub Actions)
4. トークンをコピーして環境変数に設定

#### 2. MCPサーバーの登録

**重要**: `claude mcp add`コマンドはプロジェクト固有の設定になるため、グローバル設定には**手動で`~/.claude.json`を編集**する必要があります。

`~/.claude.json`のトップレベル（プロジェクト外）にある`mcpServers`セクションに以下を追加:

```json
"mcpServers": {
  "serena": {
    "type": "stdio",
    "command": "docker",
    "args": [
      "run", "--rm", "-i", "--network", "host",
      "-v", "/Users/stkhr:/workspaces/projects",
      "ghcr.io/oraios/serena:latest",
      "serena", "start-mcp-server",
      "--transport", "stdio",
      "--context", "ide-assistant",
      "--project", "/workspaces/projects"
    ],
    "env": {}
  },
  "github": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-github"],
    "env": {
      "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_PERSONAL_ACCESS_TOKEN}"
    }
  },
  "chrome-devtools": {
    "command": "npx",
    "args": ["-y", "chrome-devtools-mcp@0.12.1"]
  },
  "context7": {
    "command": "npx",
    "args": ["-y", "@context-labs/mcp-server-context7"]
  },
  "playwright": {
    "command": "npx",
    "args": ["-y", "@executeautomation/playwright-mcp-server"]
  }
}
```

**注意点**:
- `~/.claude.json`のトップレベルの`mcpServers`に追加（`projects`の外）
- Serenaの`/Users/stkhr`パスは環境に応じて変更してください
- JSONの構文エラーに注意（カンマの位置など）

#### 3. 設定の確認

```bash
# MCPサーバー一覧を確認
claude mcp list

# 環境変数の再読み込み
source ~/.zshrc

# Claude Codeを起動して /mcp コマンドで確認
claude
> /mcp
```

### 設定の同期とバックアップ

グローバルMCP設定は`~/.claude.json`に保存されますが、このファイル全体をdotfilesで管理するのは推奨されません（セッション履歴など、マシン固有の情報が含まれるため）。

代わりに、以下の方法で設定を管理します：

1. **リファレンス設定**: `~/dotfiles/claude/mcp.json`に理想的な設定を保持
2. **セットアップスクリプト**: 新環境で手動または半自動でセットアップ
3. **ドキュメント**: このREADMEで手順を文書化

**オプション: 設定の抽出スクリプト**

現在の設定をバックアップするには：

```bash
# ~/.claude.jsonのmcpServersセクションだけを抽出
jq '.mcpServers' ~/.claude.json > ~/dotfiles/claude/mcp-backup.json
```

### MCPサーバーの有効化・無効化

グローバル設定されたMCPサーバーは、`~/.claude/config.json`の`enabledMcpjsonServers`で制御します：

```json
{
  "enabledMcpjsonServers": [
    "serena",
    "github",
    "chrome-devtools",
    "context7",
    "playwright"
  ]
}
```

または、Claude Code内から：

```
> /mcp enable github
> /mcp disable chrome-devtools
```

### トラブルシューティング

**MCPサーバーが表示されない場合**:
1. `~/.claude.json`の`mcpServers`セクションを確認
2. 環境変数が正しく設定されているか確認: `echo $GITHUB_PERSONAL_ACCESS_TOKEN`
3. Claude Codeを再起動

**Serenaが起動しない場合**:
1. Dockerが起動しているか確認: `docker ps`
2. イメージをプル: `docker pull ghcr.io/oraios/serena:latest`
3. ボリュームマウントのパスが正しいか確認

## Sub-agents（専門エージェント）

特定のタスクに特化した専用エージェントを設定できます。

### 有効化されている Sub-agents

#### 1. tech-researcher（技術調査専門家）

**用途**: 新しい技術スタック、ライブラリ、ベストプラクティスの調査

**特徴**:
- Web検索を活用した最新情報の収集
- 公式ドキュメント優先の調査
- ライブラリ・技術の比較分析
- 実装例の提供

**使用例**:
```
> tech-researcher を使って Next.js 15 の新機能を調査して
> 状態管理ライブラリ（Redux vs Zustand vs Jotai）を比較して
```

#### 2. test-debugger（テスト・デバッグ専門家）

**用途**: テスト実行、エラー解析、デバッグ

**特徴**:
- コード変更後、積極的にテストを実行
- エラーの根本原因を特定
- 最小限の変更で問題を解決
- テストの種類に応じた適切なアプローチ

**使用例**:
```
> test-debugger を使ってテストが失敗している原因を調べて
> このエラーをデバッグして修正して
```

### Sub-agents の配置

```
~/dotfiles/
└── claude/
    └── agents/
        ├── tech-researcher.md
        └── test-debugger.md
```

`install.sh` 実行で `~/.claude/agents/` にシンボリックリンクが作成されます。

### Sub-agents の使い方

#### 自動的な起動

Claude Code が以下の条件で自動的に適切な Sub-agent を起動します:
- タスクの内容
- Sub-agent の `description` フィールド
- 現在のコンテキスト

#### 明示的な起動

```
> [sub-agent名] を使って [タスク内容]
```

例:
```
> tech-researcher を使って React 19 の新機能を調査
> test-debugger を使ってテストを実行
```

### Sub-agents の管理

#### Claude Code 内から管理

```bash
claude
> /agents
```

対話的なメニューから:
- 利用可能な Sub-agents の表示
- 新規 Sub-agents の作成
- 既存 Sub-agents の編集
- Sub-agents の削除

#### ファイルで直接管理

```bash
# 新しい Sub-agent を作成
vi ~/dotfiles/claude/agents/new-agent.md

# install.sh でシンボリックリンクを作成
./install.sh
```

### Sub-agent ファイルの形式

```markdown
---
name: agent-name
description: エージェントの説明。いつ使うべきかを明記。
tools: WebSearch, WebFetch, Read, Write, Grep, Glob, Bash
model: sonnet
---

エージェントのシステムプロンプトをここに記述。

役割、アプローチ、ベストプラクティスなどを詳細に記載。
```

### ベストプラクティス

1. **明確な責任範囲**: 各エージェントは単一の明確な責任を持つ
2. **詳細なプロンプト**: 具体的な指示、例、制約を含める
3. **必要最小限のツール**: セキュリティと集中力のため、必要なツールのみ付与
4. **バージョン管理**: プロジェクト固有の Sub-agents は git でチーム共有

### 組み込み Sub-agents

Claude Code には以下の組み込み Sub-agents が含まれています:

- **general-purpose**: 複雑な複数ステップのタスク
- **plan**: プランモード時のリサーチと情報収集
- **explore**: コードベースの高速検索・分析（読み取り専用）

## 設定完了確認

### すべての設定が正しく適用されているか確認

```bash
# 1. シンボリックリンクの確認
ls -la ~/.claude/config.json
ls -la ~/.claude/CLAUDE.md
ls -la ~/.claude/statusline.sh

# 2. MCPサーバーの確認
jq '.mcpServers | keys' ~/.claude.json

# 期待される出力:
# [
#   "chrome-devtools",
#   "context7",
#   "github",
#   "playwright",
#   "serena"
# ]

# 3. 有効化されているMCPサーバーの確認
jq '.enabledMcpjsonServers' ~/.claude/config.json

# 4. terminal-notifierの確認
which terminal-notifier

# 5. Claude Codeを起動して確認
claude
> /mcp
```

### statusline の動作確認

Claude Code起動時に画面下部にトークン使用率のプログレスバーが表示されていれば成功です。

### 音声通知の動作確認

Claude Codeの応答完了時に「作業が完了しました」という通知が表示されれば成功です。

### MCP サーバーの動作確認

```bash
claude
> /mcp
```

以下のサーバーが表示されることを確認:
- ✅ serena
- ✅ github
- ✅ chrome-devtools
- ✅ context7
- ✅ playwright
