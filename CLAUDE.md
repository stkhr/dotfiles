# dotfiles Repository Guidelines

## Post-Change Checklist

After making changes to this repository, always check:

1. **install.sh の更新が必要か確認**
   - 新しい設定ファイルを追加した場合 → シンボリックリンク作成処理を追加
   - 新しいディレクトリ構造を追加した場合 → mkdir と ln コマンドを追加
   - 新しいプラグイン/スキルを追加した場合 → インストールコマンドを追加

2. **変更対象ごとのチェックポイント**
   - `claude/` 配下: claude セクションの更新
   - `claude/skills/` 配下: skills ループで自動処理されるか確認。Codex にも共有するなら install.sh の `codex_skills` 配列に追加
   - `claude/agents/` 配下: agents ループで自動処理されるか確認
   - `codex/` 配下: codex セクションの更新
   - `config/` 配下: 個別の ln コマンド追加が必要
   - `bin/` 配下: bin ループで自動処理されるか確認(`~/.local/bin` へリンク)

3. **共通ガイドラインの同期**
   - `claude/CLAUDE.md` を変更したら `codex/AGENTS.md` にも反映する(方針が食い違うと Codex が予備として機能しない)

## Directory Structure

```
dotfiles/
├── .??*              # ホームディレクトリ直下にシンボリックリンク
├── bin/              # ~/.local/bin 配下に配置(自作コマンド)
├── config/           # ~/.config/ 配下に配置
├── claude/           # ~/.claude/ 配下に配置
│   ├── skills/       # カスタムスキル
│   └── agents/       # カスタムエージェント
└── codex/            # ~/.codex/ 配下に配置(Claude Code の予備)
    ├── AGENTS.md     # claude/CLAUDE.md の Codex 移植版
    └── rules/        # コマンド承認ルール
```
