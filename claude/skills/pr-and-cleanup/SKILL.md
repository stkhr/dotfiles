---
name: pr-and-cleanup
description: |
  Worktree環境でのPR作成とクリーンアップを一括実行。未コミット変更の確認、
  GitHub PR作成、worktree削除、メインブランチへの切り替えを自動化。
  「PRを作成してクリーンアップ」「worktreeを片付ける」などの指示で起動。
---

# PR and Cleanup Skill

## Purpose

このスキルは、worktree環境での作業完了後のPR作成とクリーンアップを自動化します:

- 未コミット変更の検出と警告
- GitHub Pull Requestの作成
- worktreeディレクトリの削除
- メインブランチへの自動切り替え
- 安全な状態への復帰

## When to Use

以下の場合にこのスキルを使用:

- worktree環境で機能開発が完了した時
- PRを作成してworktreeを片付けたい時
- 作業が中断され、worktreeをクリーンアップしたい時
- 複数のworktreeを管理していて整理したい時

## Instructions

### 1. Verify Environment

**現在の状態を確認:**

```bash
# worktree内で実行されているか確認
git worktree list | grep "$(pwd)"

# 現在のブランチを確認
git branch --show-current

# 未コミット変更の確認
git status --short
```

### 2. Check for Uncommitted Changes

**変更があるか確認:**

```bash
if [ -n "$(git status --porcelain)" ]; then
  echo "⚠️ Uncommitted changes detected"
  git status
  # ユーザーに確認を求める
fi
```

**対応オプション:**
- コミットしてから続行
- 変更を破棄して続行（`--force` オプション）
- 操作をキャンセル

### 3. Ensure Changes are Pushed

**リモートとの同期を確認:**

```bash
# プッシュされていないコミットがあるか確認
if [ -n "$(git log @{u}.. 2>/dev/null)" ]; then
  echo "⚠️ Unpushed commits detected"
  # 自動的にプッシュするか確認
fi
```

### 4. Independent Code Review

**PR作成前に独立したコードレビューエージェントを起動する（自己評価での代替不可）:**

```bash
# SHAを取得
BASE_SHA=$(git merge-base HEAD origin/main 2>/dev/null || git rev-parse HEAD~1)
HEAD_SHA=$(git rev-parse HEAD)
```

`superpowers:requesting-code-review` スキルを実行し、`superpowers:code-reviewer` サブエージェントを起動すること。

**結果に応じた対応（Draft PR フロー）:**
- Critical issues → 修正してからこのステップを再実行
- Important / Minor issues → 修正は必須とせず、Draft PR 本文の「レビュー所見」セクションに記載し、人間レビューでの判断に委ねる
- 問題なし → PR作成に進む

非Draft（Ready）PR を作成する場合は、Important issues も修正してから進む。

### 5. Create Draft Pull Request

委譲タスクの既定の終点は **Draft PR**。事前のユーザー承認は挟まず作成する（Draft PR の作成はハードゲート対象外）。

**本文の構成**: `## Summary`（なぜ中心の変更要旨 2〜4 点）に加えて `## レビュー所見` セクションを設け、Step 4 の独立レビュー結果を Critical（修正済み）/ Important・Minor（未対応・要判断）に分けて列挙する。これにより PR description とコードの指摘が PR 上で1か所にまとまる。

```bash
# Draft PR を作成（既定）。本文は Summary + レビュー所見
gh pr create --draft \
  --title "feat: ..." \
  --body "$(cat <<'EOF'
## Summary
- <変更点1>
- <変更点2>

## レビュー所見
- ✅ Critical（修正済み）: <内容>
- ⚠️ Important（未対応・要判断）: <内容>
- 💡 Minor: <内容>
EOF
)"

# ベースブランチを指定する場合
gh pr create --draft --base develop
```

**作成前のローカル確認:**
- ローカルで lint/format/テストを実行済みか
- リポジトリの PR テンプレート有無を確認（あれば従う）

**Ready PR 化（Draft → Ready）・マージは別途ユーザー承認が必要**（ハードゲート対象）。

### 6. Clean Up Worktree

> **Draft PR レビューフローの注意**: Draft PR を作成してユーザーのレビューを待つ場合は、worktree を残す（`--pr-only` 相当）。レビュー反映（コード修正・PR更新）が済んでからクリーンアップする。

**PR作成成功後、worktreeを削除:**

```bash
# 現在のworktreeパスを取得
WORKTREE_PATH=$(git worktree list | grep "$(git branch --show-current)" | awk '{print $1}')

# メインブランチに戻る前に、ベースディレクトリ（リポジトリルート）を確認
REPO_ROOT=$(git rev-parse --show-toplevel)

# メインブランチ（または指定されたブランチ）にチェックアウト
cd "$REPO_ROOT"
git checkout main  # または develop など

# worktreeを削除
git worktree remove "$WORKTREE_PATH"
```

### 7. Report Status

完了後、以下の情報をユーザーに提供:

```markdown
✅ PR作成とクリーンアップが完了しました

**PR URL:** <pr-url>
**削除したworktree:** <worktree-path>
**現在のブランチ:** main

**次のステップ:**
1. PRのレビューを依頼
2. CI/CDの結果を確認
3. レビューコメントに対応
4. マージ準備が整ったらマージ

**便利なコマンド:**
- `gh pr view` - 現在のブランチのPRを表示
- `gh pr checks` - CI/CDステータスを確認
- `gh pr merge` - PRをマージ（承認後）
```

### 8. Handle Edge Cases

#### Case 1: PR作成のみ（worktreeは残す）

```bash
# --pr-only オプションを使用
./pr_and_cleanup.sh --pr-only
```

#### Case 2: クリーンアップのみ（PRは作成済み）

```bash
# --cleanup-only オプションを使用
./pr_and_cleanup.sh --cleanup-only
```

#### Case 3: 強制実行（未コミット変更を無視）

```bash
# --force オプション（非推奨）
./pr_and_cleanup.sh --force
```

## Key Principles

1. **安全性優先**: 未コミット変更がある場合は警告
2. **柔軟性**: PR作成とクリーンアップを個別に実行可能
3. **透明性**: すべての操作を明示的にユーザーに報告
4. **可逆性**: ブランチは削除せず、必要に応じて復元可能

## Customization Options

ユーザーが以下をカスタマイズしたい場合は質問して確認:

- **ベースブランチ**: PRのマージ先（`main`, `develop`, `staging` など）
- **戻り先ブランチ**: クリーンアップ後にチェックアウトするブランチ
- **PRテンプレート**: カスタムテンプレートの使用
- **ブランチ削除**: リモートブランチも削除するかどうか

## Dependencies

- Git 2.5+ (worktree機能のサポート)
- GitHub CLI (`gh`) - PR作成に必須
  ```bash
  # インストール
  brew install gh

  # 認証
  gh auth login
  ```

## Integration with Other Skills

- **create-worktree**: このスキルで作成したworktreeのクリーンアップ
- **code-review**: PR作成後のコードレビュー実施

## Best Practices

1. **作業の完了確認**: PR作成前にすべての変更がコミット済みか確認
2. **CI/CDの確認**: PR作成後、すぐにCI/CDステータスを確認
3. **ブランチの整理**: マージ済みのブランチは定期的に削除
4. **ドラフトPRの活用**: 作業中はドラフトPRで進捗を共有

## Common Issues and Solutions

### Issue 1: GitHub CLIが未認証

```
error: authentication required
```

**Solution**: GitHub CLIで認証を実行

```bash
gh auth login
# ブラウザまたはトークンで認証
```

### Issue 2: worktreeディレクトリ内からの実行に失敗

```
fatal: cannot remove path when it is in the current directory
```

**Solution**: スクリプトが自動的にリポジトリルートに移動してから削除

```bash
# スクリプト内で処理済み
cd "$REPO_ROOT"
git worktree remove "$WORKTREE_PATH"
```

### Issue 3: リモートブランチが存在しない

```
error: branch 'feature/xxx' has no upstream branch
```

**Solution**: 最初にリモートにプッシュ

```bash
git push -u origin $(git branch --show-current)
```

### Issue 4: PR作成時にベースブランチが見つからない

**Solution**: ベースブランチを明示的に指定

```bash
gh pr create --base develop
```

## Advanced Options

### ブランチも削除する場合

PR作成とクリーンアップ後、ローカル・リモートブランチも削除:

```bash
# PRマージ後に実行
gh pr merge --auto --squash
git worktree remove <worktree-path>
git branch -D <branch-name>
git push origin --delete <branch-name>
```

### 複数worktreeの一括クリーンアップ

```bash
# すべてのworktreeを一覧表示
git worktree list

# 不要なworktreeを削除
git worktree remove <path1>
git worktree remove <path2>

# staleなworktreeをクリーンアップ
git worktree prune
```

## Notes

- worktreeを削除してもブランチは残るため、必要に応じて再度worktreeを作成可能
- PRをマージした後、ブランチを削除するのはGitHub側の設定で自動化可能
- `gh pr create` はリポジトリのPRテンプレートを自動的に使用
- ドラフトPRは通常のPRに後から変換可能
