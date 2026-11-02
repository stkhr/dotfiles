---
name: pr-creation
description: コミット・PR作成を伴う作業の終盤に使用。PRテンプレート探索、本文フォーマット、
  Draft PRフロー(変更量チェック→レビュー→作成→共有)、gh-stack による PR 分割、
  CI確認までの手順を規定。「PRを作成して」「コミットしてPR化して」「PRを分割して」
  などの指示、および委譲タスクの終点処理で起動。
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

- `## Summary` 以外のセクションを作らない。例外はテンプレートがある場合と、ユーザーがそのセクションを名指しで要求した場合のみ
- 箇条書きは3項目以内。1項目は1文で言い切り、括弧補足や「〜のため、〜も」の連結で複文にしない
- 4点以上になる変更は PR 分割を検討する。分割しない場合は なぜ > 影響範囲 > 何を の順で残す
- 「なぜ」を中心に書き、diffで明確な「何を」は最小限に

### 本文に書かず、置き場所を変えるもの

- CI / bot が自動投稿する内容(plan 結果・カバレッジ等)の再掲 — 自動コメントに委ねる
- レビュープロセスのメタ情報(実施したレビュー・指摘の対応状況) — チャット応答で共有
- 調査の網羅性を示す経過(対象外と判断した候補・確認手段) — チャット応答で共有
- スコープ外の発見・改善提案 — 別チケット

## 3. Draft PR フロー(委譲タスクの既定の終点)

1. ローカルでテスト・ビルド・lint/format を実行し、通ることを確認する
2. 変更量を測る(「4. 変更量チェック」)。閾値超えは分割の要判断を出し、ユーザーが選ぶまで進まない
3. 差分のコードレビューを通し、Critical な指摘を修正して再レビュー
   (Claude Code では `superpowers:requesting-code-review`、それ以外では `code-review` スキル)
4. `gh pr create --draft` で Draft PR を作成(事前のユーザー承認は不要)。分割した時は `gh stack submit --auto`
5. 作成後に PR URL・本文要旨・残レビュー所見を共有する

レビュー所見は PR 本文に書かず、手順5のチャット応答で全件共有する(Critical=修正済み /
Important・Minor=未対応・要判断)。PR 上に残す必要があるかはユーザーが判断する。
例外は headless 自走時。チャットの読み手がいないため、所見を Draft PR 本文の末尾に残す。

非Draft(Ready)PR を作成する場合は Important な指摘も修正してから作成する。

## 4. 変更量チェック

コードレビューより先に base との実変更量を測る。分割すると層ごとにレビューするので、
全体を先にレビューすると 1 回分が無駄になる。閾値は 400 行(追加 + 削除)。

- 計測は `git diff --numstat <base>...HEAD`。バイナリ、lockfile(package-lock.json / yarn.lock /
  pnpm-lock.yaml / go.sum / Cargo.lock / poetry.lock / Gemfile.lock / composer.lock / *.lock)、
  スナップショット(`__snapshots__/` / *.snap)は数えない
- 閾値超えは要判断を出す。A: そのまま 1 本 / B: 分割。B には各 PR の名前・範囲・見込み行数・順序を添える
- ユーザーが選ぶまで Draft PR を作らない
- headless 自走時は要判断を出さず、プランの PR 構成に従う。閾値を超えていても Draft PR を作り、
  実測行数と分割案を本文末尾に書く
- Claude Code では hook(`confirm-pr-size.sh`)が閾値超えの `gh pr create` に確認プロンプトを出す。
  hook が見るのは `gh pr create` だけで、`gh stack submit` は見ない

## 5. PR 分割(gh-stack)

分割は stacked PR で行う。CLI の詳細と非対話フラグは `gh-stack` スキルに従う。

- 切り方: 各 PR が単独で CI を通り単独で読める / 準備のリファクタと振る舞いの変更を分ける /
  テストは対象コードと同じ PR に入れる
- プランで複数 PR と決めた時は最初から層で作る。`gh stack init <現在のブランチ>` で作業ブランチを
  最下層に採用し、実装・commit → `gh stack add <次の層>` → 実装・commit を繰り返す
- 実装後に分割する時は base から層ブランチを切り、`git checkout <元ブランチ> -- <paths>` か
  cherry-pick で層ごとに commit し、`gh stack init <層1> <層2> ...` で採用する
- PR 作成は `gh stack submit --auto`(Draft が既定)。`--open` はハードゲート対象
- 層ごとの変更量は 1 つ下の層との diff で測る
- 下の層を直したら `gh stack rebase --upstack` → `gh stack push`

## 6. CI 確認

- リポジトリに CI/CD(GitHub Actions 等)がある場合、PR 作成後 `gh pr checks` で
  ステータスを確認するまでが作業完了。失敗は即修正(放置・無視は禁止)

## 注意

- Draft → Ready 変換、PR の close / comment / merge / review、非Draft PR の作成、
  `gh stack merge`、`gh stack submit --open`、`gh stack link --open` はハードゲート対象。Claude Code では hook が、
  Codex では `~/.codex/rules/` が確認プロンプトを出す。ゲートが無い操作は自分で「文面提示 → 承認 → 実行」を経る
