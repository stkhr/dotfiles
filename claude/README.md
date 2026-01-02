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
    "chrome-devtools"
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
