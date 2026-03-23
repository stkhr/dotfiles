---
name: session-start
description: |
  新しい作業セッション開始時に使用。現在の作業状態を把握するための
  標準化されたスタートアップルーティン。クロスセッションの文脈を回復する。
  「作業を始める」「状態を確認して」「前回の続きから」「今どんな状態?」
  などの指示で起動。
---

# Session Start Skill

## Purpose

セッション開始時に現在の作業状態を体系的に把握し、
前セッションからの文脈を正確に回復します。

## 実行手順

以下を**この順番で**実行してください:

### Step 1: 作業ディレクトリの確認

```bash
pwd
git branch --show-current
```

mainまたはmasterにいる場合は、ユーザーに作業ブランチを確認してください。

### Step 2: 最近の変更履歴を確認

```bash
git log --oneline -10
git status --short
```

- 未コミットの変更があれば内容を把握する
- 最後のコミットから作業の文脈を読み取る

### Step 3: 進捗ファイルの確認

以下の順に確認し、存在すれば読む:

```bash
# 進捗・TODO ファイル
ls -la TODO.md PROGRESS.md .claude-progress.json 2>/dev/null
```

### Step 4: テストスイートの状態確認

プロジェクトタイプに応じてテストを実行:

```bash
# Node.js
[ -f package.json ] && npm test --if-present 2>&1 | tail -10

# Go
[ -f go.mod ] && go test ./... -count=1 2>&1 | tail -10

# Python
[ -f pytest.ini ] || [ -f pyproject.toml ] && python3 -m pytest -q 2>&1 | tail -10

# Rust
[ -f Cargo.toml ] && cargo test 2>&1 | tail -10
```

テストが失敗している場合は、作業開始前にユーザーに報告する。

### Step 5: 状態サマリーをユーザーに報告

以下の形式で現状を報告:

```
## セッション状態

**ブランチ**: feature/xxx
**未コミット変更**: N ファイル
**テスト**: ✓ 全通過 / ✗ N件失敗

**直近の作業** (git logより):
- ...

**確認が必要な事項**:
- （あれば）
```

## 注意事項

- テストが最初から失敗している場合は、それを「既存の問題」として記録する
- 未コミット変更がある場合は、その変更の意図をユーザーに確認する
- `CLAUDE.md` に記載のADRディレクトリがあれば、関連するADRを確認する
