---
name: lt-slides
description: |
  セッションで得た学びを LT(ライトニングトーク)の Marp スライドにする際に使用。
  `/lt-slides` で明示的に呼び出した時だけ起動する。
disable-model-invocation: true
argument-hint: "[タイトル案・話したい流れ]"
---

# セッションの学びを LT スライドにする

成果物は Marp の markdown(`slide.md`)。PDF / PPTX は頼まれた時だけ書き出す。

## 1. 素材を集める

- 会話に加えて、セッション中に書いた scratchpad のレポートと memory も読む。圧縮で会話から消えた数値や経緯がそこに残っている
- 引数にタイトル案や話の流れがあれば、それを骨格にする
- 事実を「実出力で確認済み」「推定・未確認」「撤回済み」に分ける。スライドに載せるのは確認済みだけにする

## 2. 最初にまとめて聞く

次を 1 回の番号付きリストで聞く。引数や会話で既に分かっている項目は省く。

1. 聞き手と見せる具体性
   - A. 社内
   - B. 社外・仕組みまで話す。顧客名・個人名・IP・ドメイン・閾値は伏せ、数値は丸める(社外の推奨)
   - C. 社外・再現手順やコードの要点まで見せる
   - D. 社外・事例を一般化し、自社の話だと分からない形にする
2. 出力先ディレクトリ
3. 持ち時間(既定 5 分)、イベント名と開催日(未定なら仮の値で進める)

伝えたいメッセージは聞かず、手順 4 の構成案で案を出す。

## 3. 書く前に確かめる

- 会話内で実出力を見ていない主張(製品の仕様・対応状況・規約の条文・既定値)は一次情報で確かめる
- 確かめられない主張は載せないか、「(YYYY-MM 時点)」「未確認」を付ける

## 4. 構成案を出して承認を得る

- 1 枚 1 行で、話す内容と秒数を書く。合計を持ち時間に収める
- 伝えたいメッセージを 1 文で添える
- 伏せる情報の方針を 1 行で書く。社内向けでも顧客名・個人名を出すかを明記する
- 承認を得るまで slide.md を書き始めない

## 5. slide.md を書く

- 置き場所は `<出力先>/<ディレクトリ名>/slide.md`。ディレクトリ名は出力先の過去スライドの命名に合わせ、無ければ `YYYYMM_<slug>`(発表月)にする。既存のディレクトリは上書きしない
- 出力先に過去のスライドがあれば、最新のものから `themes/`・`marp.config.mjs`・ロゴなどの素材をコピーし、frontmatter と言い回しを合わせる。無ければ Marp の `default` テーマで書く
- 各スライドの末尾に、話す内容をスピーカーノート(`<!-- -->`)で書く

## 6. 画像に書き出して確認する

PNG に書き出し、全ページを Read で見る。はみ出しと要素の重なり(特にフッターと下端の囲み)を直し、書き出し直す。

```bash
cd <スライドのディレクトリ>
npx -y @marp-team/marp-cli@4.5.1 --no-stdin --config-file marp.config.mjs slide.md --images png --allow-local-files -o <scratchpad>/slide-png/slide.png
```

- `--no-stdin` が無いと標準入力を待って止まる
- `marp.config.mjs` が無い時は `--config-file` を外す
- ノートの文字数 ÷ 350 字/分で話す時間を見積もる。持ち時間を超えたら、どのノートを削るかの案を添えて報告する

## 7. PDF / PPTX を書き出す(頼まれた時だけ)

```bash
npx -y @marp-team/marp-cli@4.5.1 --no-stdin --config-file marp.config.mjs slide.md --pdf --allow-local-files -o slide.pdf
npx -y @marp-team/marp-cli@4.5.1 --no-stdin --config-file marp.config.mjs slide.md --pptx --allow-local-files -o slide.pptx
```

- PDF に `--pdf-notes` を付けない。全ページの左下に付箋アイコンが出る
- PPTX はノート付きで、各スライドが 1 枚の画像になる。PowerPoint 上で文字は直せない
- 同じディレクトリに `~$slide.pptx` があれば PowerPoint で開かれている。上書きせず、閉じてもらってから書き出す
