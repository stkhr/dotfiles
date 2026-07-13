# OWASP Top 10:2025 Security Reference Guide

このドキュメントは、OWASP Top 10:2025 に基づいた体系的なセキュリティチェックリストを提供します。
境界レビューの質問集は [boundary-review.md](boundary-review.md) を参照してください。

2021版からの主な変更:

- **A03 Software Supply Chain Failures** が新設(2021 A06 Vulnerable and Outdated Components を拡張し、依存だけでなくビルド・配布まで対象)
- **A10 Mishandling of Exceptional Conditions** が新設(失敗時の挙動)
- **SSRF** は独立カテゴリではなく A01 Broken Access Control 配下に統合
- Security Misconfiguration が A02 に上昇

## A01:2025 – Broken Access Control (アクセス制御の不備)

### 概要
アクセス制御の不備により、ユーザーが権限外のデータやリソースにアクセスできる脆弱性。
正規の認証済みリクエストで悪用できるため自動ツールでは検出しづらく、**最優先でレビューする**。
SSRF(サーバーに意図しない通信をさせる)もこの分類に含まれる。

### チェック項目

#### 認可の構造(サブジェクト・リソース・アクション・コンテキスト)
- [ ] すべての機密リソースに認証が必要か
- [ ] 認可チェックが一元化されているか(middleware / policy / decorator、deny by default)
- [ ] ロールベースアクセス制御(RBAC)が適切に実装されているか
- [ ] 権限チェックがサーバー側で行われているか(クライアント側のみではない)
- [ ] 一覧・詳細・更新・削除で同じ強さの検証があるか

#### オブジェクトレベル認可(IDOR / BOLA)
- [ ] URLやJSON内のリソースIDを差し替えたとき、所有者確認で落ちるか
- [ ] テナント境界(組織ID、プロジェクトID、ワークスペースID)を跨げないか
- [ ] 「IDが推測困難(UUID)」を認可の代わりにしていないか
- [ ] ファイルパスの検証が行われているか(パストラバーサル対策)

#### 機能レベル認可(BFLA)
- [ ] UIに出ていない管理者API・内部APIにサーバー側のロール確認があるか
- [ ] URLの直接入力・推測による不正アクセスが防がれているか(UI非表示はアクセス制御ではない)

#### CORS設定
- [ ] CORS設定が適切か(`*`を使用していないか)
- [ ] 信頼できるオリジンのみ許可しているか
- [ ] Credentials付きリクエストの設定が適切か

#### SSRF対策
- [ ] ユーザー提供のURLを検証しているか(スキームのホワイトリスト)
- [ ] プライベートIP(10.0.0.0/8、172.16.0.0/12、192.168.0.0/16、127.0.0.0/8)へのアクセスをブロックしているか
- [ ] クラウドメタデータAPI(169.254.169.254等)へのアクセスが制限されているか
- [ ] DNSリバインディング対策、リダイレクト先の検証があるか

### 脆弱なコード例

```python
# ❌ 脆弱: IDを直接使用(認可チェックなし)
@app.route('/user/<user_id>/profile')
def get_profile(user_id):
    profile = db.get_user_profile(user_id)
    return jsonify(profile)

# ✅ 安全: 認可チェック(主体・対象の確認)
@app.route('/user/<user_id>/profile')
@login_required
def get_profile(user_id):
    if current_user.id != user_id and not current_user.is_admin:
        abort(403)
    profile = db.get_user_profile(user_id)
    return jsonify(profile)
```

```python
# ❌ 脆弱: URL検証なし(SSRF)
@app.route('/fetch')
def fetch_url():
    url = request.args.get('url')
    response = requests.get(url)
    return response.content

# ✅ 安全: スキーム検証 + プライベートIPブロック
from urllib.parse import urlparse
import ipaddress, socket

ALLOWED_SCHEMES = ['http', 'https']
BLOCKED_NETWORKS = [
    ipaddress.ip_network('10.0.0.0/8'),
    ipaddress.ip_network('172.16.0.0/12'),
    ipaddress.ip_network('192.168.0.0/16'),
    ipaddress.ip_network('127.0.0.0/8'),
]

@app.route('/fetch')
def fetch_url():
    url = request.args.get('url')
    parsed = urlparse(url)
    if parsed.scheme not in ALLOWED_SCHEMES:
        return 'Invalid scheme', 400
    try:
        ip = ipaddress.ip_address(socket.gethostbyname(parsed.hostname))
    except Exception:
        return 'Invalid hostname', 400
    for network in BLOCKED_NETWORKS:
        if ip in network:
            return 'Access to private IP is forbidden', 403
    response = requests.get(url, timeout=5)
    return response.content
```

### 対策

1. **デフォルト拒否**: すべてのリソースはデフォルトでアクセス拒否
2. **認可の一元化**: 各ハンドラに散らさず middleware / policy で判断
3. **ABACの要素で確認**: サブジェクト・リソース・アクション・コンテキスト(テナント・状態)を漏れなく検証
4. **サーバー側検証**: すべての認可チェックはサーバー側で実施
5. **権限昇格テスト**: 別ユーザー・別ロール・別テナントで拒否されることを確認するテストを用意
6. **ログ記録**: アクセス制御失敗をログに記録

---

## A02:2025 – Security Misconfiguration (セキュリティ設定ミス)

### 概要
不適切なセキュリティ設定による脆弱性。実装が安全でも設定の誤りで防御は無効化されるため、
設定変更もコードと同様にレビュー・スキャンの対象に含める。

### チェック項目

#### デフォルト設定
- [ ] デフォルトアカウント・デフォルトパスワードが無効化/変更されているか
- [ ] 不要なサービス・機能が無効化されているか
- [ ] サンプルアプリケーション・検証用エンドポイントが削除されているか

#### エラーハンドリングと情報露出
- [ ] エラーメッセージに詳細情報(スタックトレース、内部URL、SQL、環境変数)が含まれていないか
- [ ] デバッグモードが本番環境で無効か
- [ ] エラーログが適切に保護されているか

#### セキュリティヘッダーとCookie
- [ ] Content-Security-Policy が設定されているか
- [ ] X-Frame-Options / X-Content-Type-Options が設定されているか
- [ ] Strict-Transport-Security (HSTS) が設定されているか
- [ ] Cookieの `Secure` / `HttpOnly` / `SameSite` が環境ごとに崩れていないか

#### クラウド・インフラ
- [ ] ストレージバケットが意図せず公開されていないか
- [ ] IAM権限が広すぎないか
- [ ] デバッグ用ポート・管理ポートが公開されていないか

#### パッチ管理
- [ ] すべてのソフトウェアが最新版か、セキュリティパッチが適用されているか
- [ ] EOLソフトウェアを使用していないか

### 脆弱な設定例

```python
# ❌ 脆弱: 詳細なエラー表示
app.config['DEBUG'] = True  # 本番環境でこれはNG

@app.errorhandler(500)
def internal_error(error):
    return str(error), 500  # スタックトレース露出

# ✅ 安全: 最小限のエラー情報
app.config['DEBUG'] = False

@app.errorhandler(500)
def internal_error(error):
    logger.error(f"Internal error: {error}")
    return "An error occurred", 500
```

### 対策

1. **最小構成**: 必要最小限の機能のみ有効化
2. **セキュリティヘッダー**: 適切なHTTPヘッダーを設定
3. **環境間の一貫性**: 本番・ステージングで防御設定を崩さない(IaCで管理)
4. **定期的なパッチ適用**: 脆弱性修正を迅速に適用
5. **セキュリティスキャン**: 定期的な設定スキャン実施

---

## A03:2025 – Software Supply Chain Failures (ソフトウェアサプライチェーンの失敗)

### 概要
依存ライブラリ・ビルド・配布経路の侵害や脆弱性。サードパーティ依存では、パッケージ本体
だけでなくメンテナのアカウント、レジストリ、ビルド環境、推移的依存まで攻撃対象になり得る。
脆弱性スキャンに加えて、**依存の取り込みからビルド・デプロイまでの来歴(provenance)を
追跡できる状態**にする。

### チェック項目

#### 依存関係の管理
- [ ] lockfileでバージョンが固定されているか
- [ ] すべての依存関係(推移的依存含む)のバージョンを把握しているか
- [ ] 不要な依存関係が削除されているか
- [ ] 依存更新PRがレビューされているか(自動マージしていないか)
- [ ] EOL・放置されたライブラリを使用していないか

#### パッケージの取得元
- [ ] typo-squatting(似た名前の悪意あるパッケージ)を確認したか
- [ ] 社内パッケージ名が公開レジストリで取得されないか(dependency confusion)
- [ ] パッケージの署名・整合性検証があるか
- [ ] 信頼できるレジストリからのみ取得しているか

#### ビルドパイプライン
- [ ] 公式CIでビルドされているか
- [ ] CI/CDのsecretが最小化されているか
- [ ] CIの権限が広すぎないか(書き込み権限、トークンスコープ)
- [ ] 生成物の改ざん防止があるか

#### 成果物の配布
- [ ] SBOM(Software Bill of Materials)を管理しているか
- [ ] 成果物の署名があるか
- [ ] 本番へ出してよい条件(スキャン結果、レビュー)がポリシー化されているか

### 脆弱性スキャン

```bash
# Node.js
npm audit

# Python
pip-audit
safety check

# Ruby
bundle audit

# Go
go list -m all | nancy sleuth

# Rust
cargo audit

# Java
dependency-check --scan .

# GitHub Actions
zizmor .github/workflows/
```

### 対策

1. **継続的な監視**: 依存関係の脆弱性を継続的に監視(Dependabot等)
2. **lockfile固定**: すべての依存のバージョンをlockfileで固定する
3. **最小化**: 不要な依存関係を削除
4. **来歴の追跡**: 依存の採用からビルド成果物のデプロイまでを記録でつなぐ
5. **SBOMの作成**: 依存関係の完全な可視化

---

## A04:2025 – Cryptographic Failures (暗号化の失敗)

### 概要
機密データの不適切な保護による情報漏洩の脆弱性。

### チェック項目

#### データ保護
- [ ] 機密データが平文で保存されていないか
- [ ] データベース・バックアップの暗号化が有効か
- [ ] ログファイルに機密情報が記録されていないか

#### 通信の暗号化
- [ ] すべての通信がHTTPS/TLSで暗号化されているか(TLS 1.2以上)
- [ ] 証明書の検証が適切に行われているか
- [ ] HSTSが有効か

#### 暗号化アルゴリズム
- [ ] 弱いアルゴリズム(MD5、SHA1、DES)を使用していないか
- [ ] 適切な鍵長を使用しているか(AES-256、RSA-2048以上)
- [ ] パスワードハッシュにソルトと適切なコストがあるか(bcrypt rounds 12以上)
- [ ] 乱数生成が暗号学的に安全か

#### 鍵管理
- [ ] 暗号化鍵がハードコードされていないか
- [ ] 鍵の定期的なローテーションが行われているか
- [ ] 鍵へのアクセスが適切に制限されているか

### 脆弱なコード例

```python
# ❌ 脆弱: 弱いハッシュ化
import hashlib
password_hash = hashlib.md5(password.encode()).hexdigest()

# ✅ 安全: bcrypt使用
import bcrypt
password_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt(rounds=12))

# ❌ 脆弱: 平文保存
config = {
    'api_key': 'sk-1234567890abcdef',
    'db_password': 'password123'
}

# ✅ 安全: 環境変数使用
import os
api_key = os.environ.get('API_KEY')
if not api_key:
    raise ValueError('API_KEY environment variable is required')
```

### 対策

1. **強力な暗号化**: AES-256、RSA-2048以上を使用
2. **パスワードハッシュ**: bcrypt、argon2、scrypt等を使用
3. **TLS強制**: すべての通信をHTTPS化
4. **鍵管理**: 環境変数または専用の鍵管理サービス使用
5. **データ分類**: 機密度に応じた適切な保護措置

---

## A05:2025 – Injection (インジェクション)

### 概要
信頼できないデータがコマンドやクエリの一部として実行される脆弱性。XSSも含む。
入力検証は必要だが、**命令との分離はパラメータ化・エンコードで行う**。

### チェック項目

#### SQLインジェクション
- [ ] パラメータ化クエリ/プリペアドステートメントを使用しているか
- [ ] ORM/クエリビルダーを使用しているか
- [ ] ユーザー入力を直接SQL文に埋め込んでいないか

#### NoSQLインジェクション
- [ ] NoSQLクエリに入力検証(型チェック)があるか
- [ ] クエリ演算子(`$where`等)が注入できないか

#### OSコマンドインジェクション
- [ ] システムコマンド実行を避けているか
- [ ] 必要な場合、シェルを経由しない実行方法を使っているか
- [ ] ホワイトリストで許可されたコマンドのみ実行しているか

#### XSS(出力境界)
- [ ] 出力先の文脈(HTML本文/属性/URL/JavaScript)に合わせてエンコードしているか
- [ ] `innerHTML`等の危険なAPIを避けているか(`textContent`を使う)
- [ ] CSPで実行できるスクリプトを制限しているか
- [ ] 「入力サニタイズ済み」を出力エンコードの代わりにしていないか

#### その他
- [ ] LDAPクエリの特殊文字(*, (, ), \, NUL)が処理されているか
- [ ] XML外部エンティティ(XXE)対策(DTD処理の無効化)があるか
- [ ] テンプレートインジェクション対策があるか

### 脆弱なコード例

```python
# ❌ 脆弱: SQLインジェクション
query = f"SELECT * FROM users WHERE username = '{username}'"
cursor.execute(query)

# ✅ 安全: パラメータ化クエリ
query = "SELECT * FROM users WHERE username = ?"
cursor.execute(query, (username,))

# ❌ 脆弱: OSコマンドインジェクション
import os
os.system(f"cat {filename}")

# ✅ 安全: 安全なAPI使用
with open(filename, 'r') as f:
    content = f.read()
```

```javascript
// ❌ 脆弱: NoSQLインジェクション
db.users.find({ username: req.body.username })

// ✅ 安全: 入力検証
if (typeof req.body.username !== 'string') {
    throw new Error('Invalid username');
}
db.users.find({ username: req.body.username })
```

### 対策

1. **パラメータ化**: プリペアドステートメント/パラメータ化クエリ使用
2. **文脈別エンコード**: 出力先(HTML/属性/URL/JS)に合わせたエスケープ
3. **入力検証**: すべての入力をホワイトリストで検証(絞る)、出力で文脈に閉じ込める
4. **最小権限**: データベースユーザーに最小限の権限のみ付与
5. **CSP**: XSSの被害範囲を制限

---

## A06:2025 – Insecure Design (安全でない設計)

### 概要
設計段階でのセキュリティ考慮不足による脆弱性。後から足す防御は、設計時に作らなかった
境界を復元できない。仕様通りに動くビジネスロジックの脆弱性はツールで検出しづらい。

### チェック項目

#### セキュリティ要件
- [ ] セキュリティ要件が検証可能な形(認可マトリクス・入出力契約)で定義されているか
- [ ] 脅威モデリングが実施されているか
- [ ] 障害・例外時のデフォルト動作が拒否側(デフォルト拒否、縮退、隔離)に定義されているか

#### セキュアなデザインパターン
- [ ] 多層防御が実装されているか(どの層で何を判断するかが設計されているか)
- [ ] フェイルセーフな設計か
- [ ] 信頼境界と認可モデルが図または文書として残っているか

#### ビジネスロジック(悪用シナリオ)
- [ ] 個々には正当なリクエストが想定外の順序・回数・組み合わせで送られたときの挙動を検討したか
- [ ] レート制限が適切に実装されているか
- [ ] リソース枯渇攻撃への対策があるか
- [ ] 割引・ポイント・在庫・返金・招待・承認フローの悪用を検討したか

#### 入力モデルの分離(マスアサインメント)
- [ ] 入力モデル・出力モデル・永続化モデルを分離しているか
- [ ] リクエストボディをそのまま永続化モデルへ渡していないか
- [ ] 契約にない追加フィールドを拒否/無視しているか

### 脆弱な設計例

```javascript
// ❌ 脆弱: マスアサインメント({ "is_admin": true } を混ぜられる)
await User.update(req.body);

// ✅ 安全: 許可フィールドだけを使う
await User.update({
  name: req.body.name,
  email: req.body.email,
});
```

```python
# ❌ 脆弱: レート制限なし
@app.route('/api/expensive-operation', methods=['POST'])
def expensive_operation():
    result = perform_expensive_calculation()
    return jsonify(result)

# ✅ 安全: レート制限あり
from flask_limiter import Limiter
limiter = Limiter(app, key_func=lambda: request.remote_addr)

@app.route('/api/expensive-operation', methods=['POST'])
@limiter.limit("5 per minute")
def expensive_operation():
    result = perform_expensive_calculation()
    return jsonify(result)
```

### 対策

1. **Security by Design**: 信頼境界と失敗時の挙動を設計段階で決める
2. **脅威モデリング**: STRIDE等のフレームワーク使用。認証済み攻撃者も想定する
3. **契約の明示**: OpenAPI/schema、認可マトリクスを検証に使う
4. **ピアレビュー**: 設計をチームでレビュー([boundary-review.md](boundary-review.md)の質問を使う)
5. **悪用シナリオ**: 正常系と対で悪用ケースを検討する

---

## A07:2025 – Authentication Failures (認証の失敗)

### 概要
認証メカニズムの不備による不正アクセス。セッション・トークンは発行から失効までの
ライフサイクル全体(期限、スコープ、ログアウト、権限変更・退職時の失効、保存場所)を
通して確認する。

### チェック項目

#### パスワードポリシー
- [ ] 弱いパスワードが拒否されるか(最小12文字以上推奨)
- [ ] よく使われるパスワードのブラックリストがあるか

#### パスワード保存
- [ ] パスワードが平文で保存されていないか
- [ ] 適切なハッシュアルゴリズム(bcrypt、argon2等)+ソルトを使用しているか

#### 認証プロセス
- [ ] クレデンシャルスタッフィング・ブルートフォース対策(レート制限、ロックアウト)があるか
- [ ] 機密性の高い操作にMFA(TOTP、WebAuthn)が要求されるか

#### セッション・トークン管理
- [ ] セッションIDが予測困難か(暗号学的乱数)
- [ ] セッションタイムアウト・トークン有効期限が適切か
- [ ] ログアウト時にセッション/トークンが無効化されるか
- [ ] セッション固定攻撃への対策があるか
- [ ] トークンの保存場所(Cookie属性、ストレージ)が適切か
- [ ] 権限変更時(ロール剥奪、退職)に古いトークンが失効するか

### 脆弱なコード例

```python
# ❌ 脆弱: 弱いセッションID
import random
session_id = str(random.randint(100000, 999999))

# ✅ 安全: 暗号学的に安全な乱数
import secrets
session_id = secrets.token_urlsafe(32)

# ❌ 脆弱: レート制限なしのログイン
@app.route('/login', methods=['POST'])
def login():
    ...

# ✅ 安全: レート制限あり
@app.route('/login', methods=['POST'])
@limiter.limit("5 per minute")
def login():
    ...
```

### 対策

1. **強力なパスワードポリシー**: NIST SP 800-63Bに準拠
2. **MFA実装**: すべての重要なアカウントでMFA必須
3. **セキュアなセッション管理**: 予測困難なID、適切なタイムアウト、確実な失効
4. **レート制限**: ログイン試行回数を制限
5. **監視とアラート**: 異常なログイン試行を検出

---

## A08:2025 – Software or Data Integrity Failures (ソフトウェアとデータの整合性の不備)

### 概要
整合性検証の欠如によるデータ改ざんや不正なコード実行。

### チェック項目

#### デシリアライゼーション
- [ ] 信頼できないデータをデシリアライズしていないか(`pickle`等)
- [ ] デシリアライゼーション前に検証・型チェックしているか

#### ソフトウェア更新
- [ ] ソフトウェア更新に署名検証があるか
- [ ] HTTPS経由で更新を取得し、整合性チェックがあるか

#### CI/CDセキュリティ
- [ ] CI/CDパイプラインが適切に保護されているか
- [ ] ビルド環境が隔離されているか
- [ ] シークレットが安全に管理されているか

### 脆弱なコード例

```python
# ❌ 脆弱: 安全でないデシリアライゼーション
import pickle
data = pickle.loads(untrusted_data)  # RCEの危険

# ✅ 安全: 安全なフォーマット使用
import json
data = json.loads(untrusted_data)

# ❌ 脆弱: 署名検証なし
response = requests.get('http://example.com/update.zip')
with open('update.zip', 'wb') as f:
    f.write(response.content)

# ✅ 安全: ハッシュ検証
import hashlib
response = requests.get('https://example.com/update.zip')
expected_hash = 'abc123...'
actual_hash = hashlib.sha256(response.content).hexdigest()
if actual_hash != expected_hash:
    raise ValueError('Hash mismatch')
```

### 対策

1. **デジタル署名**: すべての更新とアーティファクトに署名
2. **整合性チェック**: ハッシュ値の検証
3. **安全なデシリアライゼーション**: JSON等の安全な形式を使用
4. **CI/CD強化**: パイプラインへのアクセス制限、監査ログ

---

## A09:2025 – Logging & Alerting Failures (ログと検知の失敗)

### 概要
不十分なログ記録や監視による攻撃の見逃し。棚卸しされていない公開エンドポイントには
保護策も監視も適用されない。

### チェック項目

#### ログ記録
- [ ] ログイン試行(成功・失敗)、認可失敗、入力検証エラーを記録しているか
- [ ] 重要な設定変更・状態変更・機密データアクセスを記録しているか
- [ ] インシデント時に追える識別子(request id、user id、tenant id)を含めているか

#### ログ保護
- [ ] ログに機密情報(パスワード、トークン、PII)が含まれていないか
- [ ] ログファイルが改ざんから保護され、アクセス制限されているか
- [ ] ログインジェクション対策があるか

#### 監視・検知・棚卸し
- [ ] 認可失敗、トークン失敗、rate limit到達、異常な4xx/5xxを検知できるか
- [ ] 公開エンドポイントの棚卸しができているか(シャドウAPI、未知のパスの観測)
- [ ] アラート通知とインシデント対応プロセスがあるか

### ログ記録例

```python
import logging
import json
from datetime import datetime

logger = logging.getLogger(__name__)

def log_security_event(event_type, user_id, details):
    logger.warning(json.dumps({
        'timestamp': datetime.utcnow().isoformat(),
        'event_type': event_type,
        'user_id': user_id,
        'request_id': g.request_id,
        'ip_address': request.remote_addr,
        'details': details
    }))

# ❌ 脆弱: ログインジェクション
logger.info(f"User input: {user_input}")  # 改行が含まれる可能性

# ✅ 安全: エスケープ処理
logger.info("User input: %s", user_input.replace('\n', '\\n'))
```

### 対策

1. **包括的なログ記録**: すべてのセキュリティイベントを記録
2. **集中ログ管理**: SIEM等で集中管理
3. **リアルタイム監視**: 異常を即座に検出
4. **エンドポイントの棚卸し**: OpenAPI、ゲートウェイ・アクセスログで公開エンドポイントを把握
5. **インシデント対応**: 明確なプロセスと責任者

---

## A10:2025 – Mishandling of Exceptional Conditions (例外的状況の不適切な処理)

### 概要
エラー・例外・想定外の状態での挙動が決まっていないことによる脆弱性。
失敗時にfail-open(開いたまま失敗)すると、防御そのものが無効化される。

### チェック項目

#### 失敗時のデフォルト動作
- [ ] 認可チェックが例外を投げたとき、拒否側に倒れるか(fail-close)
- [ ] 外部サービス(認証基盤、決済等)の障害時にどう縮退するか決まっているか
- [ ] タイムアウト・リトライの挙動が定義されているか(無限リトライ、二重実行の防止)

#### 例外処理
- [ ] 例外を握りつぶしていないか(catchして無視)
- [ ] 例外時にエラー詳細(スタックトレース、内部情報)を外部へ漏らしていないか
- [ ] 部分的な失敗(バッチの途中失敗、トランザクション境界)で不整合が残らないか

#### 異常入力・異常状態
- [ ] 巨大ペイロード・想定外の型・null/空での挙動が定義されているか
- [ ] 並行実行・レースコンディションで検証を迂回できないか
- [ ] 状態遷移の想定外の順序(完了済み注文の変更等)を拒否するか

### 脆弱なコード例

```python
# ❌ 脆弱: 認可エラー時にfail-open
def check_permission(user, resource):
    try:
        return acl_service.check(user, resource)
    except Exception:
        return True  # サービス障害時に全許可

# ✅ 安全: fail-close + 記録
def check_permission(user, resource):
    try:
        return acl_service.check(user, resource)
    except Exception as e:
        logger.error("ACL check failed: %s", e)
        return False  # 判断できないときは拒否
```

### 対策

1. **Fail Securely**: 判断できないときは拒否側に倒す
2. **失敗時の設計**: エラー、縮退、隔離、復旧を設計段階で決める
3. **情報最小化**: エラー応答から内部情報を漏らさない
4. **冪等性**: リトライ・並行実行で二重処理が起きない設計

---

## 言語別セキュリティチェックリスト

### Python
- [ ] `pickle`の使用を避ける(または信頼できるデータのみ)
- [ ] `eval()`、`exec()`の使用を避ける
- [ ] `os.system()`ではなく`subprocess`を使用
- [ ] `bandit`でセキュリティスキャン実施
- [ ] `pip-audit`で依存関係の脆弱性確認

### JavaScript/Node.js
- [ ] `eval()`の使用を避ける
- [ ] `innerHTML`ではなく`textContent`を使用
- [ ] `npm audit`で依存関係の脆弱性確認
- [ ] ESLintに`eslint-plugin-security`を追加
- [ ] `helmet`でセキュリティヘッダー設定

### Java
- [ ] デシリアライゼーションに注意
- [ ] PreparedStatementを使用(Statement避ける)
- [ ] `dependency-check`で脆弱性スキャン
- [ ] SpotBugsでセキュリティバグ検出

### Go
- [ ] `gosec`でセキュリティスキャン
- [ ] `nancy`で依存関係の脆弱性確認
- [ ] SQLインジェクション対策(パラメータ化クエリ)
- [ ] コマンドインジェクション対策

### Ruby
- [ ] `bundle audit`で依存関係確認
- [ ] `brakeman`で静的解析
- [ ] Strong Parametersの使用(Rails)— マスアサインメント対策
- [ ] 生のSQLを避ける

---

## セキュリティテストチェックリスト

### 認可テスト(最優先)
- [ ] user Aのトークンでuser Bのリソースへアクセス(横方向の越境)
- [ ] 一般ロールで管理者エンドポイントへアクセス(縦方向の越境)
- [ ] 別テナント・別組織のIDを指定したアクセス
- [ ] 一覧・詳細・更新・削除それぞれで権限昇格を確認
- [ ] 許可されるケースと拒否されるケースを対にして確認

### 単体テスト
- [ ] 入力検証のテスト(境界値、不正値、想定外フィールド)
- [ ] 認証・認可のテスト
- [ ] 暗号化処理のテスト
- [ ] エラーハンドリングのテスト(fail-closeの確認)

### 統合テスト
- [ ] セキュリティヘッダーの検証
- [ ] CSRF保護の検証
- [ ] セッション管理の検証(ログアウト後の無効化)
- [ ] APIセキュリティの検証(追加フィールド拒否)

### 脆弱性テスト
- [ ] SQLインジェクション / XSS / CSRF / SSRF テスト
- [ ] 認証バイパス / 権限昇格テスト
- [ ] マスアサインメントテスト(`is_admin`、`price`、`tenant_id` の混入)
- [ ] 異常な順序・回数・並行実行のテスト(ビジネスロジック)

---

## 参考リソース

- [OWASP Top 10:2025](https://owasp.org/Top10/2025/en/)
- [OWASP Top Ten プロジェクト](https://owasp.org/www-project-top-ten/)
- [OWASP API Security Top 10 2023](https://owasp.org/API-Security/editions/2023/en/0x11-t10/)
- [OWASP Cheat Sheet Series](https://cheatsheetseries.owasp.org/)
- [CWE Top 25](https://cwe.mitre.org/top25/)
- [NIST SSDF](https://csrc.nist.gov/projects/ssdf)
- [OWASP SAMM](https://owaspsamm.org/model/)
