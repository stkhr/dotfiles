---
name: pr-creation
description: コミット・PR作成を伴う作業の終盤に使用。PRテンプレート探索、本文フォーマット、
  Draft PRフロー(レビュー→作成→共有)、CI確認までの手順を規定。「PRを作成して」
  「コミットしてPR化して」などの指示、および委譲タスクの終点処理で起動。
---

# PR 作成フロー

## 1. テンプレート探索(上から順に優先)

1. `.github/PULL_REQUEST_TEMPLATE.md` / `.github/pull_request_template.md` /
   `PULL_REQUEST_TEMPLATE.md` / `docs/PULL_REQUEST_TEMPLATE.md`
2. `.github/PULL_REQUEST_TEMPLATE/` ディレクトリ配下の複数テンプレート(変更種別に合うものを選択)
3. `CONTRIBUTING.md` 内のPR作成ガイドライン

テンプレートが存在する場合は項目を勝手に省略・追加せず、フォーマット構造を保ったまま記入する。

## 2. 本文フォーマット(テンプレートが無い場合の既定)

```
## Summary
- <変更点1>
- <変更点2>
```

- `## Summary` 以外のセクションを作らない。例外はテンプレートがある場合と、ユーザーが明示的に要求した場合のみ
- 箇条書きは3項目以内。1項目は1文で言い切り、括弧補足や「〜のため、〜も」の連結で複文にしない
- 「なぜ」を中心に書き、diffで明確な「何を」は最小限に

### 本文に書かず、置き場所を変えるもの

- CI / bot が自動投稿する内容(plan 結果・カバレッジ等)の再掲 — 自動コメントに委ねる
- レビュープロセスのメタ情報(実施したレビュー・指摘の対応状況) — チャット応答で共有
- 調査の網羅性を示す経過(対象外と判断した候補・確認手段) — チャット応答で共有
- スコープ外の発見・改善提案 — 別チケット

## 3. Draft PR フロー(委譲タスクの既定の終点)

1. ローカルでテスト・ビルド・lint/format を実行し、通ることを確認する
2. `superpowers:requesting-code-review` を実行し、Critical な指摘を修正して再レビュー
3. `gh pr create --draft` で Draft PR を作成(事前のユーザー承認は不要)
4. 作成後に PR URL・本文要旨・残レビュー所見を共有する

レビュー所見は PR 本文に書かず、手順4のチャット応答で全件共有する(Critical=修正済み /
Important・Minor=未対応・要判断)。PR 上に残す必要があるかはユーザーが判断する。

非Draft(Ready)PR を作成する場合は Important な指摘も修正してから作成する。

## 4. CI 確認

- リポジトリに CI/CD(GitHub Actions 等)がある場合、PR 作成後 `gh pr checks` で
  ステータスを確認するまでが作業完了。失敗は即修正(放置・無視は禁止)

## 注意

- Draft → Ready 変換、PR の close / comment / merge / review、非Draft PR の作成は
  hook が確認プロンプトを出す(ハードゲート対象)
