---
name: monthly-dev-report
description: |
  月次の開発活動レポートを生成する際に使用。GitHubコミット履歴から特定期間の
  開発作業をリポジトリ別に集計・分析する。「今月の開発をまとめて」「レポート作成」
  「開発活動を振り返りたい」などの指示で起動。
---

# Monthly Development Report Skill

## Purpose

GitHubコミット履歴から月次の開発活動を自動集計し、構造化されたレポートを生成する。

## When to Use

- 月次の開発振り返り
- 「今月の開発をまとめて」という指示
- 期間を指定した開発活動レポートの作成依頼
- チームや個人の開発貢献の可視化

## Parameters

| パラメータ | デフォルト値 | 説明 |
|-----------|-------------|------|
| 対象期間 | 前月 | YYYY-MM形式で指定可能 |
| リポジトリパス | **必須（毎回確認）** | 対象リポジトリの親ディレクトリ |
| 作者メール | git config user.email | コミット作者のフィルタ |

## Instructions

### 1. パラメータの確認

**リポジトリパスは必ずユーザーに確認する。** AskUserQuestionツールを使用して以下を確認:

- 対象リポジトリの親ディレクトリパス（例: `~/ghq/github.com/stkhr/`）
- 対象期間（指定がなければ前月）

```bash
# 作者メールの取得
git config --global user.email

# ユーザー指定後、対象リポジトリの確認
ls -d <リポジトリパス>/*/
```

### 2. コミット収集

全リポジトリから指定期間のコミットを収集:

```bash
cd <リポジトリパス> && for repo in */; do
  commits=$(git -C "$repo" log --author="<メールアドレス>" \
    --since="<開始日>" --until="<終了日>" \
    --pretty=format:"%h|%ad|%s" --date=short 2>/dev/null)
  if [ -n "$commits" ]; then
    echo "=== ${repo%/} ==="
    echo "$commits"
    echo ""
  fi
done
```

### 3. コミット数集計

```bash
cd <リポジトリパス> && for repo in */; do
  count=$(git -C "$repo" log --author="<メールアドレス>" \
    --since="<開始日>" --until="<終了日>" --oneline 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" -gt 0 ]; then
    echo "${repo%/}: $count"
  fi
done | sort -t: -k2 -nr
```

### 4. レポート構成

以下の形式でレポートを生成:

```markdown
## YYYY年M月 開発活動レポート

**期間**: YYYY年M月D日〜M月D日
**総コミット数**: N件
**対象リポジトリ数**: N件

---

### リポジトリ別コミット数

| リポジトリ | コミット数 | 主な内容 |
|-----------|----------|---------|
| repo-name | N | 概要 |

---

### 主要プロジェクト

#### 1. **プロジェクト名 (チケット番号)**
- 実施内容の箇条書き

---

### 日別活動分布

簡易的なASCIIグラフで活動量を可視化
```

## Output Options

レポート生成後、以下のオプションを提示:

1. **ファイル保存**: Markdown形式で保存
2. **追加分析**: PR数、変更行数などの詳細分析
3. **期間変更**: 別の期間でのレポート再生成

## Notes

- Mergeコミットも含まれる（除外したい場合は `--no-merges` を追加）
- 複数のメールアドレスを使用している場合は、それぞれで実行
- リポジトリが多い場合、実行に時間がかかる可能性がある
