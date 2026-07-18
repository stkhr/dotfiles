# Claude Code Personal Skills

このディレクトリは、Claude Codeで使用するPersonal Skillsを管理します。

## 📋 利用可能なSkills

| Skill | 用途 |
|---|---|
| `adr` | Architecture Decision Record の作成・更新 |
| `code-review` | 体系的なコードレビュー(品質・セキュリティ・パフォーマンス) |
| `debugging` | 障害調査・バグ調査の進め方(原因特定先行・レイヤ切り替え) |
| `external-api-precheck` | クラウドAPI・外部SaaS実装前の一次情報確認 |
| `legal-review` | プロダクト法務の逆引きレビュー(法務案件アラートの検知) |
| `monthly-dev-report` | GitHubコミット履歴からの月次開発レポート生成 |
| `pdm-assist` | プロダクトマネジメント(何を・誰に・いくらで)の意思決定補佐 |
| `pm-assist` | プロジェクトマネジメント(タスク・リスク洗い出し)の補佐 |
| `pr-and-cleanup` | worktree 環境での PR 作成とクリーンアップの一括実行 |
| `pr-creation` | PRテンプレート探索・Draft PRフロー・CI確認の手順 |
| `security-hardening` | 境界レビュー・脅威モデリング等の能動的セキュリティ強化 |
| `session-start` | セッション開始時の作業状態把握ルーティン |
| `terraform-style` | Terraform のスタイル規範 |

各スキルの詳細・起動条件は各ディレクトリの `SKILL.md` frontmatter(`description`)を参照。

---

## 🚀 Skillsの使い方

### 自動起動
Claude Codeは、ユーザーのリクエストと各Skillの`description`を自動的にマッチングし、関連するSkillを提案します。

### 明示的な起動
特定のSkillを使いたい場合は、直接指示することもできます:
```
code-reviewスキルを使ってこのファイルをレビューして
```

## 📝 新しいSkillの作成

### 1. ディレクトリ構造の作成

```bash
mkdir -p claude/skills/<skill-name>
```

### 2. SKILL.mdの作成

必須のYAML frontmatterと指示を含めます:

```markdown
---
name: skill-name
description: |
  このSkillの目的と使用タイミングを明確に記述。
  Claudeがいつ使うべきか判断できるように具体的に。
allowed-tools: Read, Grep, Glob  # オプション: ツール制限
---

# Skill Name

## 目的
[このSkillが解決する問題]

## 使用タイミング
[いつ使うべきか]

## Instructions
[ステップバイステップの手順]

## Examples
[具体例]
```

### 3. サポートファイルの追加(オプション)

大きなSkillの場合、progressive disclosureを活用:

```
my-skill/
├── SKILL.md           # 概要 (500行以下推奨)
├── reference.md       # 詳細ドキュメント
├── examples.md        # 使用例
└── scripts/          # ユーティリティスクリプト
    └── helper.py
```

### 4. シンボリックリンクの作成

```bash
./install.sh
```

### 5. Claude Codeの再起動

変更を反映するため、Claude Codeを再起動してください。

## 🔧 Skillsの管理

### 更新

1. 対象のSkillのファイルを編集
2. Gitにコミット
3. Claude Codeを再起動

```bash
vim claude/skills/code-review/SKILL.md
git commit -am "feat: improve code-review skill"
# Claude Codeを再起動
```

### 削除

```bash
rm -rf claude/skills/<skill-name>
git commit -am "chore: remove <skill-name> skill"
./install.sh
# Claude Codeを再起動
```

### 複数マシン間の同期

```bash
# マシンA
git push origin main

# マシンB
git pull origin main
./install.sh
# Claude Codeを再起動
```

## 📚 命名規則

### Skill名
- 小文字、数字、ハイフン(-)のみ使用
- 最大64文字
- 例: `code-review`, `git-workflow`, `debug-helper`

### ファイル名
- `SKILL.md` (必須・大文字)
- `reference.md`, `examples.md` (推奨)
- その他のサポートファイルは小文字

## 💡 ベストプラクティス

### 1. descriptionを具体的に

❌ 悪い例:
```yaml
description: Helps with code
```

⭕ 良い例:
```yaml
description: |
  コードレビューを実施する際に使用。プルリクエストのレビュー、
  セキュリティ検査、パフォーマンス分析を行う。「レビューして」
  「コードをチェック」などの指示で起動。
```

### 2. Progressive Disclosureの活用

SKILL.mdは簡潔に保ち、詳細は別ファイルにリンク:

```markdown
詳細は[reference.md](reference.md)を参照
```

### 3. ツール制限の活用

読み取り専用のSkillには`allowed-tools`を設定:

```yaml
allowed-tools: Read, Grep, Glob
```

### 4. 具体例の提供

`examples.md`に実際の使用例を含めることで、Claudeがより適切に動作します。

### 5. バージョン管理

重要な変更はGitコミットメッセージで記録:

```bash
git commit -m "feat: add security checklist to code-review"
git commit -m "fix: improve code-review performance analysis"
```

## 🎯 推奨Skillsのアイデア

- `commit-helper` - コンベンショナルコミット形式の支援
- `refactor-guide` - リファクタリング手順
- `test-strategy` - テスト戦略の立案
- `api-design` - REST/GraphQL APIの設計支援
- `performance-audit` - パフォーマンス監査

※ セキュリティ関連は `security-guidance` plugin（自動検出）と `security-hardening` skill（能動的強化）でカバー済み

## 📖 参考資料

- [Claude Code公式ドキュメント](https://github.com/anthropics/claude-code)
- [Personal Skills Guide](https://docs.anthropic.com/claude/docs/skills)
- [CLAUDE.md](../CLAUDE.md) - 開発ガイドライン

## 🐛 トラブルシューティング

### Skillが認識されない

1. SKILL.mdのYAML frontmatterが正しいか確認
2. `name`フィールドがディレクトリ名と一致しているか確認
3. Claude Codeを再起動
4. シンボリックリンクが正しく作成されているか確認:
   ```bash
   ls -la ~/.claude/skills/
   ```

### Skillが自動起動しない

1. `description`がより具体的で、トリガーワードを含んでいるか確認
2. 明示的にSkill名を指定して起動してみる
3. Claudeに「利用可能なSkillsは?」と尋ねて認識されているか確認

### 変更が反映されない

1. Claude Codeを完全に再起動
2. キャッシュのクリア(環境による)
3. `./install.sh`を再実行

## 📞 フィードバック

Skillsに関する改善提案や問題は、このリポジトリのIssueで報告してください。
