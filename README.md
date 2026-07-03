# dotfiles

macOS 向けの各種ツール設定を管理するリポジトリ。`install.sh` がホームディレクトリへ
シンボリックリンクを配置する。

## セットアップ

```bash
# Homebrew パッケージのインストール
brew bundle

# シンボリックリンクの配置 + Claude Code セットアップ
zsh install.sh
```

install.sh は再実行可能（リンクは `ln -snf` で張り直されるため、リポジトリを
移動した場合も再実行すれば追従する）。

## 構成

| パス | 配置先 | 内容 |
|---|---|---|
| `.zshrc` / `.tmux.conf` / `.tmux.session.conf` / `.vimrc` | `~/` | シェル・tmux・vim |
| `config/starship.toml` | `~/.config/` | プロンプト（starship） |
| `config/sheldon/plugins.toml` | `~/.config/sheldon/` | zsh プラグイン管理（sheldon） |
| `config/herdr/config.toml` | `~/.config/herdr/` | エージェントマルチプレクサ（herdr） |
| `claude/` | `~/.claude/` | Claude Code 設定一式（詳細は [claude/README.md](claude/README.md)） |
| `vscode/` | （手動） | VSCode 設定・拡張リスト |
| `Brewfile` | - | Homebrew パッケージ定義 |

リポジトリ自体は ghq 管理（`~/ghq/github.com/stkhr/dotfiles`）。

## VSCode

```bash
# 拡張リストの書き出し
code --list-extensions > ./vscode/extensions

# 拡張のインストール
xargs -n 1 code --install-extension < ./vscode/extensions
```
