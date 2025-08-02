# 設定管理データフロー（逆生成）

## セットアップフロー

### 初回環境構築フロー
```mermaid
sequenceDiagram
    participant U as ユーザー
    participant R as dotfiles リポジトリ
    participant S as install.sh
    participant H as ホームディレクトリ
    participant B as Homebrew
    participant V as VS Code
    
    U->>R: git clone
    U->>S: ./install.sh 実行
    S->>H: dotfiles のシンボリックリンク作成
    S->>H: ~/.config/starship.toml リンク
    S->>H: ~/.config/sheldon/plugins.toml リンク
    S->>H: ~/.claude/settings.json リンク
    S->>H: ~/.aws/amazonq/mcp.json リンク
    U->>B: brew bundle --file=Brewfile
    B->>B: CLI ツール、アプリケーションインストール
    U->>V: xargs -n 1 code --install-extension < ./vscode/extensions
    V->>V: 拡張機能インストール
    Note over U,V: 開発環境構築完了
```

### 設定同期フロー
```mermaid
flowchart TD
    A[dotfiles更新] --> B[git pull]
    B --> C{変更ファイル種別}
    C -->|Brewfile| D[brew bundle]
    C -->|extensions| E[拡張機能再インストール]
    C -->|設定ファイル| F[自動反映済み]
    D --> G[パッケージ更新]
    E --> H[VS Code拡張更新]
    F --> I[設定即座反映]
    G --> J[環境同期完了]
    H --> J
    I --> J
```

## ツール連携フロー

### シェル環境の初期化フロー
```mermaid
flowchart LR
    A[シェル起動] --> B[Sheldon プラグイン読み込み]
    B --> C[PATH設定]
    C --> D[Homebrew補完設定]
    D --> E[zsh-completions読み込み]
    E --> F[zsh-autosuggestions有効化]
    F --> G[zsh-syntax-highlighting有効化]
    G --> H[Starship プロンプト初期化]
    H --> I[compinit実行]
    I --> J[シェル準備完了]
```

### VS Code 環境構築フロー
```mermaid
flowchart TD
    A[VS Code起動] --> B[settings.json読み込み]
    B --> C[拡張機能チェック]
    C --> D{必要な拡張機能}
    D -->|未インストール| E[自動インストール]
    D -->|インストール済み| F[設定適用]
    E --> F
    F --> G[キーバインド適用]
    G --> H[カラーテーマ適用]
    H --> I[言語固有設定適用]
    I --> J[開発環境準備完了]
```

### Claude Code 連携フロー
```mermaid
flowchart LR
    A[Claude Code起動] --> B[~/.claude/settings.json読み込み]
    B --> C[フック設定確認]
    C --> D[terminal-notifier連携]
    D --> E[MCP設定確認]
    E --> F[GitHub MCP接続]
    F --> G[開発支援準備完了]
```

## 設定ファイル依存関係

### 設定ファイル間の関係
```mermaid
graph TD
    A[install.sh] --> B[~/.config/starship.toml]
    A --> C[~/.config/sheldon/plugins.toml]
    A --> D[~/.claude/settings.json]
    A --> E[~/.aws/amazonq/mcp.json]
    
    F[Brewfile] --> G[CLI ツール]
    F --> H[GUI アプリケーション]
    F --> I[フォント]
    
    J[vscode/settings.json] --> K[エディタ設定]
    L[vscode/extensions] --> M[拡張機能]
    N[vscode/keybindings.json] --> O[キーバインド]
    
    C --> P[Zsh プラグイン]
    P --> Q[補完システム]
    P --> R[シンタックスハイライト]
    P --> S[自動提案]
```

### 外部依存関係
```mermaid
flowchart LR
    A[dotfiles] --> B[Homebrew]
    B --> C[パッケージリポジトリ]
    
    A --> D[VS Code Marketplace]
    D --> E[拡張機能]
    
    A --> F[GitHub]
    F --> G[Zsh プラグイン]
    
    A --> H[Docker Hub]
    H --> I[MCP サーバー]
```

## 設定更新プロセス

### 設定変更の伝播
```mermaid
sequenceDiagram
    participant D as 開発者
    participant L as ローカル dotfiles
    participant R as リモート リポジトリ
    participant E as 他の環境
    
    D->>L: 設定ファイル変更
    D->>L: git add, commit
    D->>R: git push
    Note over E: 他の環境で同期
    E->>R: git pull
    E->>E: 設定自動反映（シンボリックリンク）
    E->>E: 必要に応じて再起動
```

### パッケージ更新フロー
```mermaid
flowchart TD
    A[新しいツールの発見] --> B[Brewfile更新]
    B --> C[git commit & push]
    C --> D[他の環境でgit pull]
    D --> E[brew bundle実行]
    E --> F[新パッケージインストール]
    F --> G[設定反映完了]
```

## エラーハンドリングフロー

### インストールエラーの処理
```mermaid
flowchart TD
    A[install.sh実行] --> B{シンボリックリンク作成}
    B -->|成功| C[次のファイル処理]
    B -->|失敗| D[既存ファイル確認]
    D --> E[強制上書き実行]
    E --> F[リンク作成完了]
    
    G[brew bundle実行] --> H{パッケージインストール}
    H -->|成功| I[次のパッケージ]
    H -->|失敗| J[エラーログ出力]
    J --> K[手動対応必要]
```

### 設定競合の解決
```mermaid
flowchart LR
    A[設定競合検出] --> B{競合種別}
    B -->|シンボリックリンク| C[ln -snfv で強制上書き]
    B -->|パッケージ| D[brew bundle で最新化]
    B -->|拡張機能| E[既存無視して再インストール]
    C --> F[競合解決]
    D --> F
    E --> F
```

## 通知フロー

### Claude Code 通知システム
```mermaid
flowchart LR
    A[Claude Code イベント] --> B{イベント種別}
    B -->|入力待ち| C[Notification フック]
    B -->|作業完了| D[Stop フック]
    C --> E[terminal-notifier実行]
    D --> F[terminal-notifier実行]
    E --> G[macOS通知表示]
    F --> H[完了音再生]
```

この設定管理システムは、開発環境の一貫性と再現性を重視した設計となっており、シンボリックリンクによる自動同期とパッケージ管理の組み合わせで効率的な環境構築を実現しています。