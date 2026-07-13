---
name: security-hardening
description: |
  信頼境界と認可モデルに基づくセキュリティチェックと、OWASP Top 10:2025 に準拠した
  能動的なセキュリティ強化を支援。設計段階の脅威モデリング・境界レビュー、
  認可(IDOR/BOLA/BFLA)の体系的確認、依存関係の脆弱性スキャン、
  構造化されたセキュリティレポートと不変条件(認可マトリクス・入出力契約)の生成を実施。
  「セキュリティチェックして」「セキュリティ強化して」「境界レビュー」
  「OWASP準拠を確認」「認可をレビュー」「依存関係の脆弱性をチェック」
  「脅威モデリング」などの指示で起動。

  注: コード編集時の自動検出は `security-guidance` plugin が担当する。
  本スキルは「能動的ハードニング」「境界レビュー」「依存スキャン」「総点検レポート」など、
  pluginの自動レビューでは代替できない用途に使用する。
---

# Security Hardening Skill

## Purpose

このスキルは、**信頼境界と認可モデル**の観点からセキュリティチェックを行い、結果を
**検証可能な不変条件**として残すための能動的なセキュリティ強化を提供します。

前提となる考え方:

- チェックは脅威モデリングの基本に沿って行う。**信頼境界**(境界の外から来る値は
  検証まで信頼しない)、**認可モデル**(認証とは別に、主体×リソース×操作の許可を確認する)、
  **運用面**(設定・依存・公開エンドポイントはリリース後も変化し続ける)の3領域を見る
- 個別の脆弱性(XSS、CSRF、SSRF、IDOR、BOLA、BFLA…)は、欠けている検証・制御
  (入力検証、認可、出力エンコード、失敗時処理)の単位でチェックする
- AI支援開発では変更量が増え、レビューを通らない仮定がコードに入り込みやすい。だから
  セキュリティ要件は、**レビューで読めて、CIで検証できて、例外を追跡できる不変条件**
  (認可マトリクス・入出力契約・監査条件)として明文化する

`security-guidance` plugin の自動レビュー(per-edit / end-of-turn / commit)で
カバーされない、以下のような場面で使用してください:

- 新機能着手時の設計レビュー・脅威モデリング・信頼境界の特定
- 認可(所有者・ロール・テナント・状態)の体系的なレビュー
- PR前の総点検と構造化レポート生成
- 依存関係・サプライチェーンの脆弱性スキャン(`npm audit`, `pip-audit` 等の実行)
- OWASP Top 10:2025 コンプライアンス状況の明示的な確認
- セキュリティ要件の不変条件化(認可マトリクス・入出力契約の文書化)

## When to Use

- 「セキュリティチェックして」「セキュリティ強化して」という明示的な指示
- 新機能実装前のセキュリティ設計レビュー・脅威モデリング
- 認可まわりのレビュー(マルチテナント、ロール追加、管理者機能の変更時)
- OWASP Top 10:2025 準拠の確認(コンプライアンス報告含む)
- 依存関係の脆弱性スキャン(`npm audit`, `pip-audit` 等)の実施
- セキュリティインシデント後の再発防止策の検討
- PR前の総点検と構造化されたセキュリティレポートの作成

## When NOT to Use(pluginに任せる場面)

以下は `security-guidance` plugin が自動でカバーするため、明示呼び出し不要:

- Claude がコード編集中の脆弱性検出(per-edit パターンマッチ)
- ターン終了時の差分セキュリティレビュー
- `git commit` / `git push` 時のエージェント型レビュー

plugin の検出結果に対する追加調査や、より深い設計観点の強化が必要な場合に
本スキルを併用してください。

## Core Model: 基本の3観点

信頼境界を越える処理ごとに、次の3点を確認する:

1. **出所(provenance)** — この値は信頼境界の外から来ていないか。ユーザー入力、
   Cookie・ヘッダー、外部APIレスポンス、Webhook、キューのメッセージは検証を通るまで
   信頼しない
2. **実行権限(authority)** — この処理はどの主体の権限で動くか。その主体は対象
   リソースへのこの操作を許可されているか。認証(本人確認)と認可(権限確認)を
   区別して確認する
3. **失敗時の挙動(failure mode)** — 検証・認可・依存先が失敗したとき拒否側に
   倒れるか(fail-close / deny by default)

レビューはリクエストのライフサイクルに沿って行う:
**エンドポイント → 認証 → 認可 → 入力検証 → 処理・出力 → 記録**。

具体的な質問集は [boundary-review.md](boundary-review.md) を参照。

## Instructions

### 1. Understand the Context

セキュリティチェック対象を明確化:

```bash
# 対象ファイルの確認
git status
git diff --name-only

# PRの場合は差分を確認
gh pr diff
```

**確認事項**:
- アプリケーションのタイプ(Web API、フロントエンド、CLIツール等)
- 保護対象の資産(機密データ / 状態を変える操作 / 依存・連携という信頼関係)
- 外部入力の有無(ユーザー入力、API、Webhook、ファイル等)
- 認証・認可の実装状況(テナント・ロール・所有者の構造)
- 現在のセキュリティ対策レベル

### 2. Map the Trust Boundaries(信頼境界の特定)

コードを読む前に、対象が跨ぐ境界を列挙する:

| 領域 | 見るもの |
| --- | --- |
| **信頼境界** | ユーザー入力、HTTPヘッダー・Cookie、外部サービス応答・Webhook、アップロードファイル |
| **認可モデル** | ロール定義、リソースの所有権、テナント分離、特権操作 |
| **運用面** | 環境ごとの設定差、シークレット管理、依存の更新状況、エンドポイントの棚卸し、監視 |

**攻撃者モデル**には「未認証の外部者」だけでなく、**認証済みの正規ユーザー**を必ず含める
(水平方向: 別ユーザー・別テナントのリソースへの権限昇格、垂直方向: 管理者機能への
権限昇格)。クライアント側の表示制御・バリデーションはバイパスされる前提で、
サーバー側の検証だけを防御として数える。

### 3. Conduct OWASP Top 10:2025 Security Scan

以下の観点で体系的にスキャン(詳細チェックリストは[reference.md](reference.md)参照):

| 分類 | 主な領域 | レビューで見るもの |
| --- | --- | --- |
| **A01 Broken Access Control** | 認可 | 所有者、ロール、テナント、管理者機能、SSRFになり得る通信 |
| **A02 Security Misconfiguration** | 設定 | CORS、CSP、Cookie属性、クラウド設定、エラー出力 |
| **A03 Software Supply Chain Failures** | 依存・ビルド | lockfile、署名、CI/CD権限、SBOM、typo-squatting |
| **A04 Cryptographic Failures** | データ保護 | TLS、鍵管理、保存データ、トークン、ハッシュ強度 |
| **A05 Injection** | 入力処理 | SQL、OSコマンド、テンプレート、XSS(出力文脈) |
| **A06 Insecure Design** | 設計 | 脅威モデリング、失敗時の挙動、悪用シナリオ、ビジネスロジック |
| **A07 Authentication Failures** | 認証・セッション | セッション、トークン期限、MFA、失効、レート制限 |
| **A08 Software or Data Integrity Failures** | 整合性 | デシリアライゼーション、署名検証、ビルド成果物 |
| **A09 Logging & Alerting Failures** | 可観測性 | 監査ログ、認可失敗の記録、検知、追跡可能性 |
| **A10 Mishandling of Exceptional Conditions** | 例外処理 | fail-open、情報漏洩、未処理例外、縮退動作 |

優先順位は重大度だけでなく**自動検出のしにくさ**も加味する。認可の欠陥(IDOR/BOLA/BFLA)は
正規の認証済みリクエストで悪用できるためツールでは見つけにくく、最優先でレビューする。

### 4. Deep-dive: 認可レビュー

「認可チェックがある」では粗すぎる。ABACの要素に分解して確認する:

| 要素 | 確認すること |
| --- | --- |
| **サブジェクト** | リクエストの主体が正しく識別・検証されているか |
| **リソース** | 対象リソースの所有者・所属テナントを検証しているか(IDOR/BOLA) |
| **アクション** | 読み取り・作成・更新・削除それぞれに同じ強度の検証があるか(BFLA) |
| **コンテキスト** | テナント・組織・リソースの状態(確定済みデータの変更禁止等)を考慮しているか |

チェック観点:
- IDを知っていること・URLに到達できることを許可の根拠にしない。推測困難なID(UUID)は
  認可チェックの代替にならない
- UIに出していない管理者用・内部用エンドポイントにもサーバー側のロール検証を置く
- 認可ロジックはハンドラごとに書かず一元化する(middleware / policy 層、deny by default)

### 5. Input / Output Contracts(入力契約と出力契約)

入力検証と出力制御は別物として確認する:

- **入力契約**: スキーマ(DTO/OpenAPI)、型、長さ、範囲、**未定義フィールドの拒否**
  (マスアサインメント対策: 権限・価格・所属などの内部フィールドを外部から設定できないか)。
  入力モデル・出力モデル・永続化モデルを分離する
- **出力契約**: 返却してよいフィールド、PIIの扱い、エラー応答の形式。出力先の文脈
  (HTML本文・属性・URL・JavaScript)ごとのエンコード。入力時のサニタイズを出力
  エンコードの代替にしない
- **命令との分離**: Injection対策はパラメータ化で行う(入力検証は補助であって代替ではない)

### 6. Implement Security Controls

検出された問題に対する対策を実装:

- **入力検証**: すべての外部入力を検証。型・範囲・フォーマット、allowlist方式
- **インジェクション対策**: パラメータ化クエリ、ORM/クエリビルダー、最小権限DB接続
- **認証情報の保護**: 環境変数管理、ハードコード禁止、バージョン管理除外
- **セキュアな暗号化**: AES-256/SHA-256以上、暗号学的乱数、bcrypt/argon2
- **失敗時の挙動**: エラー時にfail-openしない。デフォルト拒否、詳細を漏らさないエラー応答

### 7. Add Security Tests

正常系のテストだけでは不十分。許可されるケースと**拒否されるべきケース**を対にして書く:

| 確認事項 | テストの書き方 |
| --- | --- |
| 水平方向の権限昇格が拒否されるか | 別ユーザーの認証情報で他者のリソースIDを指定する |
| 垂直方向の権限昇格が拒否されるか | 一般ロールで管理者用エンドポイントを呼ぶ |
| テナントを跨げないか | 別組織・別ワークスペースのIDを指定する |
| 未定義フィールドが拒否されるか | 権限・価格・所属などの内部フィールドをペイロードに混入させる |
| 異常な順序・回数に耐えるか | 状態遷移の逆順、並行実行、リトライの繰り返し |

認可は複数ユーザー・複数ロール・複数テナントの組み合わせで検証する。

### 8. Security Logging(監査証跡)

セキュリティイベントの適切なログ記録:

- 認証試行(成功・失敗)、認可失敗、入力検証エラー、セキュリティ例外、設定変更、機密データアクセス
- インシデント調査に必要な識別子を含める: リクエストID、ユーザーID、テナントID
- 機密情報(パスワード、トークン等)をログに記録しない。ログインジェクション対策

### 9. Dependency & Supply Chain Audit

依存関係の脆弱性スキャン:

```bash
# 言語/ツール別
npm audit          # Node.js
pip-audit          # Python
bundle audit       # Ruby
go list -m all | nancy  # Go
cargo audit        # Rust
```

スキャンに加えてサプライチェーン全体を確認(詳細は[reference.md](reference.md)のA03):

- **依存の管理**: lockfileによる固定、不要依存の削除、更新PRのレビュー
- **取得元の検証**: typo-squatting、dependency confusion、署名の確認
- **ビルドの保護**: CI/CD権限とsecretの最小化、成果物の改ざん防止
- **配布の追跡**: SBOM、成果物の署名、リリース条件のポリシー化

### 10. Provide Security Report & Invariants

チェック結果はレポートに加え、**再利用できる不変条件**として残す:

```markdown
## セキュリティチェックレポート

### 🔴 Critical Vulnerabilities (即座に修正が必要)
- [OWASP分類] [問題の説明]
- [場所とコード例]
- [修正方法]
- [CVE番号(該当する場合)]

### 🟡 High Risk Issues (修正を強く推奨)
- [問題の説明] / [潜在的な影響] / [推奨される対策]

### 🟠 Medium Risk Issues (修正を推奨)
- [問題の説明] / [改善提案]

### 🟢 Security Best Practices Implemented
- [実装されている良いセキュリティ対策]

### 📐 不変条件(今回のチェックで確認・確立したもの)
- 認可マトリクス: [ロール・所有者・テナント × 操作の許可一覧]
- 入力契約: [スキーマ、型・範囲、未定義フィールドの扱い]
- 出力契約: [返却してよいフィールド、PIIの扱い、エラー応答の形式]
- 監査・リリース条件: [記録するイベント、スキャン通過条件、例外承認]

### 📊 OWASP Top 10:2025 Compliance Status
- A01 Broken Access Control: ✅/⚠️/❌
- A02 Security Misconfiguration: ✅/⚠️/❌
- A03 Software Supply Chain Failures: ✅/⚠️/❌
- A04 Cryptographic Failures: ✅/⚠️/❌
- A05 Injection: ✅/⚠️/❌
- A06 Insecure Design: ✅/⚠️/❌
- A07 Authentication Failures: ✅/⚠️/❌
- A08 Software or Data Integrity Failures: ✅/⚠️/❌
- A09 Logging & Alerting Failures: ✅/⚠️/❌
- A10 Mishandling of Exceptional Conditions: ✅/⚠️/❌

### 🔧 Remediation Priority
1. [最優先で修正すべき項目 — 影響が大きく自動検出しづらい認可・入力契約を優先]
2. [次に修正すべき項目]
3. [時間があれば修正する項目]
```

不変条件は使い捨てにせず、プロジェクトで継続的に更新される場所(設計書、ADR、OpenAPI、
PRテンプレート、CLAUDE.md、CI設定)への反映を提案する。コードと一緒に更新されない
ルールは陳腐化する。

## Key Principles

1. **Verifiable Invariants(検証可能な不変条件)**: セキュリティ要件は機械検証・レビューが可能な条件として文書化する。文書化された条件だけがCI・テスト・エージェント指示に反映できる
2. **Defense in Depth(多層防御)**: エッジ・アプリ・データ層・運用のどこで何を判断するかを設計する。単一の防御策に依存しない
3. **Least Privilege(最小権限の原則)**: 必要最小限の権限のみを付与
4. **Fail Securely / Deny by Default(安全な失敗)**: 判断できないときは拒否側に倒す
5. **Security by Design(設計段階からのセキュリティ)**: 境界と失敗時の挙動は実装後には後付けしにくい。設計段階で決める
6. **Validate at Trust Boundaries(信頼境界で検証)**: ユーザー入力だけでなく、Cookie・ヘッダー・Webhook・外部APIレスポンスも検証対象
7. **Assume Authenticated Attackers(認証済みの攻撃者を想定)**: 正規アカウントからの権限昇格を攻撃者モデルに含める

## Secure Coding Guidelines

### DO (実施すべきこと)
- ✅ すべての外部入力を検証する(スキーマ・型・範囲・未定義フィールド拒否)
- ✅ パラメータ化クエリを使用する
- ✅ 認可を一元化し、サブジェクト・リソース・アクション・コンテキストで確認する
- ✅ 機密データを暗号化する
- ✅ セキュアな乱数生成器を使用する(`crypto.randomBytes()`)
- ✅ HTTPSを強制する
- ✅ セキュリティヘッダーを設定する(CSP、HSTS、SameSite)
- ✅ 最小権限の原則を適用する
- ✅ セキュリティイベントをログに記録する(リクエストID / ユーザーID / テナントID)
- ✅ 依存関係をlockfileで固定し定期的に更新する
- ✅ エラーメッセージで詳細情報を漏らさない
- ✅ 権限昇格のテスト(別ユーザー・別ロール・別テナント)を正常系と対で書く

### DON'T (避けるべきこと)
- ❌ 認証情報をハードコードしない
- ❌ MD5、SHA1などの弱い暗号化を使用しない
- ❌ 平文でパスワードを保存しない
- ❌ クエリに直接ユーザー入力を埋め込まない
- ❌ `eval()`や同等の機能を使用しない
- ❌ リクエストボディをそのまま永続化モデルへ渡さない(マスアサインメント)
- ❌ UI非表示・URLの推測困難さをアクセス制御として扱わない
- ❌ デフォルト認証情報を使用しない
- ❌ エラーでスタックトレースを露出しない
- ❌ セキュリティ対策を「後で」に先延ばししない

## Reference Documents

- [境界レビュー チェックリスト(設計・実装・テスト・運用)](boundary-review.md)
- [OWASP Top 10:2025 詳細チェックリスト](reference.md)

## Dependencies

### Required
- Git (変更差分の確認用)
- プロジェクトのソースコード(読み取り・書き込み)
- 依存関係マニフェスト(言語固有)

### Recommended
- 言語別セキュリティ監査ツール:
  - Node.js: `npm audit`, `snyk`
  - Python: `pip-audit`, `safety`
  - Ruby: `bundle audit`, `brakeman`
  - Go: `nancy`, `gosec`
  - Rust: `cargo audit`
  - Java: `dependency-check`
- SAST(Static Application Security Testing)ツール
  - SonarQube / Snyk / GitHub Advanced Security (CodeQL) / Semgrep
- Linter with security plugins
  - ESLint + eslint-plugin-security / Pylint + bandit / RuboCop / golangci-lint

## Integration with Other Skills

- **code-review**: コードレビュー時にセキュリティ観点を追加(境界レビューの質問を差分に適用)
- **adr**: 認可モデル・不変条件などの設計判断をADRとして記録する
- **tdd-***: テスト駆動開発で権限昇格・境界値のセキュリティテストを含める

## Notes

- セキュリティは継続的なプロセスです。一度の対策で終わりではありません
- 機能追加、認可モデルの変更、依存・連携先の変更、インシデント対応の後に不変条件を見直す
- ツールが得意なのはパターン化できる検出(既知CVE・危険な関数・構文)。ドメイン固有の
  ルール(所有権、業務フロー、状態に応じた許可)に依存する判断は本スキルの境界レビューで補う
- セキュリティとユーザビリティのバランスを考慮してください
- コンプライアンス要件(GDPR、HIPAA等)も確認してください

## References

- [OWASP Top 10:2025](https://owasp.org/Top10/2025/en/)
- [OWASP API Security Top 10](https://owasp.org/API-Security/)
- [NIST Secure Software Development Framework (SSDF)](https://csrc.nist.gov/projects/ssdf)
- [OpenSSF Guide for AI Code Assistant Instructions](https://best.openssf.org/Security-Focused-Guide-for-AI-Code-Assistant-Instructions.html)
