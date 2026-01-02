# AI駆動開発 共通ガイドライン

思考は英語で行い、最終的な出力は必ず日本語で提供してください。

## Core Development Principles
- 動くコードを書くだけでなく、品質・保守性・安全性を常に意識する
- プロジェクトの段階（プロトタイプ、MVP、本番環境）に応じて適切なバランスを取る
- 問題を見つけたら放置せず、必ず対処または明示的に記録する
- ボーイスカウトルール：エラーを見つけた時よりも良い状態で残す

## Error Handling Principles
- 関連が薄く見えるエラーでも必ず解決する
- エラーの抑制（@ts-ignore、try-catch で握りつぶす等）ではなく、根本原因を修正
- 早期にエラーを検出し、明確なエラーメッセージを提供
- エラーケースも必ずテストでカバーする
- 外部APIやネットワーク通信は必ず失敗する可能性を考慮

## Code Quality Standards
- DRY原則：重複を避け、単一の信頼できる情報源を維持
- 意味のある変数名・関数名で意図を明確に伝える
- プロジェクト全体で一貫したコーディングスタイルを維持
- 小さな問題も放置せず、発見次第修正（Broken Windows理論）
- コメントは「なぜ」を説明し、「何を」はコードで表現

## Testing Discipline
- テストをスキップせず、問題があれば修正する
- 実装詳細ではなく振る舞いをテスト
- テスト間の依存を避け、任意の順序で実行可能に
- テストは高速で、常に同じ結果を返すように
- カバレッジは指標であり、質の高いテストを重視

## Maintainability and Refactoring
- 機能追加と同時に既存コードの改善を検討
- 大規模な変更は小さなステップに分割
- 使用されていないコードは積極的に削除
- 依存関係は定期的に更新（セキュリティと互換性のため）
- 技術的負債は明示的にコメントやドキュメントに記録

## Security Considerations
- APIキー、パスワード等は環境変数で管理（ハードコード禁止）
- すべての外部入力を検証
- 必要最小限の権限で動作（最小権限の原則）
- 不要な依存関係を避ける
- セキュリティ監査ツールを定期的に実行

## Performance Awareness
- 推測ではなく計測に基づいて最適化
- 初期段階から拡張性を考慮
- 必要になるまでリソースの読み込みを遅延
- キャッシュの有効期限と無効化戦略を明確に
- N+1問題やオーバーフェッチを避ける

## Reliability Assurance
- タイムアウト処理を適切に設定
- リトライ機構の実装（指数バックオフを考慮）
- サーキットブレーカーパターンの活用
- 一時的な障害に対する耐性を持たせる
- 適切なログとメトリクスで可観測性を確保

## Understanding Project Context
- ビジネス要件と技術要件のバランスを取る
- 現在のフェーズで本当に必要な品質レベルを判断
- 時間制約がある場合でも、最低限の品質基準を維持
- チーム全体の技術レベルに合わせた実装選択

## Recognizing Trade-offs
- すべてを完璧にすることは不可能（銀の弾丸は存在しない）
- 制約の中で最適なバランスを見つける
- プロトタイプなら簡潔さを、本番なら堅牢性を優先
- 妥協点とその理由を明確にドキュメント化

## Git Workflow Basics
- コンベンショナルコミット形式を使用（feat:, fix:, docs:, test:, refactor:, chore:）
- コミットは原子的で、単一の変更に焦点を当てる
- 明確で説明的なコミットメッセージを英語で記述
- main/masterブランチへの直接コミットはしない

## Pull Request Creation and CI/CD

### Pre-PR Checks (Required)
**すべてのPRを作成する前に、以下のチェックをローカルで実行し、パスすることを確認する:**

プロジェクトで利用可能なコマンドを実行（例）:

```bash
# 型チェック（言語により異なる）
npm run type-check  # TypeScript/JavaScript
mypy .              # Python
go vet ./...        # Go
cargo check         # Rust

# Linting
npm run lint        # JavaScript/TypeScript
pylint **/*.py      # Python
golangci-lint run   # Go
rubocop             # Ruby
cargo clippy        # Rust

# フォーマットチェック
npm run format:check  # Prettier等
black --check .       # Python
gofmt -l .            # Go
cargo fmt -- --check  # Rust

# テスト
npm test           # JavaScript/TypeScript
pytest             # Python
go test ./...      # Go
bundle exec rspec  # Ruby
cargo test         # Rust

# ビルド
npm run build      # JavaScript/TypeScript
python -m build    # Python
go build ./...     # Go
cargo build        # Rust

# プロジェクト固有の統合コマンド（定義されている場合）
npm run ci
make ci
./scripts/ci-local.sh
```

**重要**:
- CI/CDで失敗することがわかっているコードはプッシュしない
- ローカルでパスしない場合は、修正してから再度チェック
- 時間がない場合でも、最低限**テストとビルド**は必ず実行
- プロジェクトのREADMEやCI設定ファイル(`.github/workflows/`, `.gitlab-ci.yml`等)を確認し、実際に使用されているコマンドを実行する

### CI/CD Monitoring After PR Creation (Required)
**PR作成または更新後は、必ずCI/CDステータスを確認する:**

```bash
# 現在のブランチのPRステータス確認
gh pr status

# 特定のPRのチェック状況
gh pr checks [<PR番号>]

# 詳細な状態（JSON）
gh pr view <PR番号> --json statusCheckRollup
```

### Handling CI Failures (Your Own PR)

**CI/CDチェックが失敗した場合、即座に以下の対応を実施:**

1. **失敗の詳細を確認**
   ```bash
   # 失敗したチェックの詳細
   gh pr checks

   # ログの確認（GitHub Actions）
   gh run view <run-id> --log-failed
   ```

2. **カテゴリ別の対応**
   - **テスト失敗**: ローカルで該当テストを実行し、原因を特定・修正
   - **ビルドエラー**: 型エラーやインポートエラーを修正
   - **Linter/Formatter**: 自動修正コマンドを実行（`lint:fix`, `format`, `black .`, `gofmt -w .`等）
   - **セキュリティスキャン**: 脆弱性の詳細を確認し、依存関係を更新または修正

3. **修正とプッシュ**
   ```bash
   # ローカルで再度CI相当のチェックを実行
   # 型チェック、テスト、ビルドなど該当するコマンドを実行

   # パスしたら修正をコミット
   git add .
   git commit -m "fix: resolve CI failures"
   git push
   ```

4. **優先度の認識**
   - 🔴 **Critical（即座に修正）**: セキュリティスキャン失敗、ビルドエラー
   - 🟡 **High（マージ前に修正）**: テスト失敗、型エラー
   - 🟠 **Medium（修正推奨）**: Linter違反、カバレッジ低下
   - 🟢 **Low（任意）**: Formatterの警告

**絶対に避けるべき行動**:
- ❌ CI失敗を無視してマージ
- ❌ CI失敗を放置したまま次の作業に移る
- ❌ 「あとで直す」と言ってそのまま放置

### CI/CD Check When Reviewing Others' PRs

**レビュー開始前に必ずCI/CDステータスを確認:**

```bash
gh pr checks <PR番号>
```

**CI失敗がある場合、レビューコメントに含める:**

```markdown
## ⚠️ CI/CD Status

現在、以下のCI/CDチェックが失敗しています:

### 失敗しているチェック
- [チェック名]: [失敗理由の要約]

### 修正が必要なアクション
1. [具体的な修正内容]
2. [具体的な修正内容]

---

[以下、通常のコードレビュー]
```

### Recommended pre-commit Hook Setup

**CI失敗を事前に防ぐため、pre-commit hookの設定を推奨:**

言語・フレームワークに応じた設定例:

**JavaScript/TypeScript (Husky)**
```bash
# .husky/pre-commit
#!/bin/sh
. "$(dirname "$0")/_/husky.sh"

npm run lint
npm run type-check
npm test

# セットアップ
npm install -D husky
npx husky init
```

**Python (pre-commit framework)**
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/psf/black
    rev: 23.3.0
    hooks:
      - id: black
  - repo: https://github.com/PyCQA/flake8
    rev: 6.0.0
    hooks:
      - id: flake8
  - repo: local
    hooks:
      - id: pytest
        name: pytest
        entry: pytest
        language: system
        pass_filenames: false

# セットアップ
pip install pre-commit
pre-commit install
```

**Go (.git/hooks/pre-commit)**
```bash
#!/bin/sh
gofmt -l . | grep . && exit 1
go vet ./...
go test ./...
```

**汎用 (Makefileを使用)**
```bash
# .git/hooks/pre-commit
#!/bin/sh
make pre-commit

# Makefile
.PHONY: pre-commit
pre-commit:
	make lint
	make test
	make build
```

## Code Review Attitude
- レビューコメントは建設的な改善提案として受け取る
- 個人ではなくコードに焦点を当てる
- 変更の理由と影響を明確に説明
- フィードバックを学習機会として歓迎

## Debugging Best Practices
- 問題を確実に再現できる手順を確立
- 二分探索で問題の範囲を絞り込む
- 最近の変更から調査を開始
- デバッガー、プロファイラー等の適切なツールを活用
- 調査結果と解決策を記録し、知識を共有

## Dependency Management
- 本当に必要な依存関係のみを追加
- package-lock.json等のロックファイルを必ずコミット
- 新しい依存関係追加前にライセンス、サイズ、メンテナンス状況を確認
- セキュリティパッチとバグ修正のため定期的に更新

## Documentation Standards
- READMEにプロジェクトの概要、セットアップ、使用方法を明確に記載
- ドキュメントをコードと同期して更新
- 実例を示すことを優先
- 重要な設計判断はADR (Architecture Decision Records)で記録

## Continuous Improvement
- 学んだことを次のプロジェクトに活かす
- 定期的に振り返りを行い、プロセスを改善
- 新しいツールや手法を適切に評価して取り入れる
- チームや将来の開発者のために知識を文書化
