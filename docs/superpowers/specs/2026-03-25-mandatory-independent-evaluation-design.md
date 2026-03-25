# 設計ドキュメント: PR作成前の独立評価フェーズ強制

**日付**: 2026-03-25
**ステータス**: 承認済み

---

## 背景・動機

Anthropic の記事 "Harness Design for Long-Running Application Development" における最大の知見:

> 「モデルは自分の成果を自己評価させると、明らかに品質が低くても自信を持って称賛する」

現在の設定では `requesting-code-review` スキルは「使える状態」にあるが、強制されていない。
`verification-before-completion` スキルは完了前検証を要求するが、検証者は生成エージェント自身であり、独立評価ではない。

**既存スキルの役割分担（本設計導入後）:**
- `verification-before-completion`: テスト・ビルド・lint などの技術的検証（自己検証）として引き続き機能
- `requesting-code-review`: 独立エージェントによるコード品質評価（本設計で必須化）
- 両スキルは相互補完的であり、置き換え関係ではない

**`superpowers:requesting-code-review` スキルについて:**
このスキルは `superpowers` プラグイン（`claude-plugins-official` マーケットプレイス）として提供され、`settings.json` の `enabledPlugins` で有効化済み。スキルの実体は `/Users/stkhr/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.5/skills/requesting-code-review/SKILL.md` に存在する。

**`claude/CLAUDE.md` について:**
`install.sh` により `~/.claude/CLAUDE.md` へシンボリックリンクされており、両者は同一ファイル。このリポジトリの `claude/CLAUDE.md` を変更することで、グローバル設定が更新される。

---

## 目標 (What)

PR作成前に、**生成エージェントとは独立したエージェントによるコードレビューを必須化**する。

---

## 対象外

- コミット単位での強制（PR作成前のみに限定）
- 評価基準の採点軸追加（今回はスコープ外）

---

## 設計 (How)

### 変更 1: `claude/CLAUDE.md` への追記

`## CI/CD` セクションに独立レビュー必須ルールを追加する。

**追加内容:**
```
- PR作成前に必ず `superpowers:requesting-code-review` スキルを実行し、
  独立したコードレビューエージェントの承認を得ること（自己評価での代替不可）
- Critical または Important な指摘がある場合は修正してからPRを作成する
```

**配置**: 既存の「ローカルでテスト・ビルド・lint/format を実行」の直後。

### 変更 2: `claude/skills/pr-and-cleanup/SKILL.md` へのステップ追加

PR作成フロー（Step 4: Create Pull Request）の前に独立レビューステップを挿入する。

**追加ステップ (Step 3.5: Independent Code Review):**

```
PR作成前に superpowers:requesting-code-review スキルを実行すること:

1. BASE_SHA と HEAD_SHA を取得
2. superpowers:code-reviewer サブエージェントを起動
3. 結果を確認:
   - Critical issues → 修正してからステップを再実行
   - Important issues → 修正してからPR作成に進む
   - 問題なし → PR作成に進む

自己評価（自分でコードを読んで「良さそう」と判断する）は不可。
```

**注意: ステップ番号について:**
挿入後、既存の Step 4 以降はステップ番号が繰り上がる（Step 4 → Step 5, Step 5 → Step 6...）。
SKILL.md 内の内部参照（"Then: Cleanup worktree (Step 5)" 等）もあわせて更新すること。

**注意: Edge Cases（`--pr-only` オプション等）について:**
`SKILL.md` の Step 7 に記載された `--pr-only`、`--cleanup-only` などのオプション経路は、今回のスコープ外とする。これらのオプションは PR 作成前の独立レビューを省略できる抜け道になりえるが、CLAUDE.md ルールによる抑止に委ねる。

---

## 強制力の重なり

| レイヤー | 効果 | 迂回リスク |
|---------|------|-----------|
| CLAUDE.md ルール | 全セッションで読まれる | Claudeが省略する可能性 |
| pr-and-cleanup スキル | スキル呼び出し時に強制 | スキルを使わない場合は無効 |
| **両方** | 二重の強制力 | 低 |

---

## 成功基準

- `pr-and-cleanup` スキルを実行すると、PR作成前に必ずコードレビューサブエージェントが起動される
- CLAUDE.md を読んだ Claude が、手動で PR 作成する場合も独立レビューを実行する
- Critical/Important な指摘がある場合、Claude は修正を行ってから PR を作成する（技術的ブロックではなく、LLM への指示による制約）
