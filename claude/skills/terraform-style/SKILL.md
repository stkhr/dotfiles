---
name: terraform-style
description: |
  Terraform コード(*.tf)を書く・修正する・レビューする際に必ず使用。
  count/for_each の条件式の書き方、fmt の実行範囲、plan 結果の扱いなどの
  スタイル規範を規定。「Terraformを書いて」「tfファイルを修正して」
  「plan結果を確認して」などの Terraform 作業全般で起動。
---

# Terraform スタイル規範

- `count` / `for_each` の三項演算子は肯定形を使う(OK: `var.env_name == "stg" ? 1 : 0` / NG: `var.env_name != "prd" ? 1 : 0`)
- `terraform fmt` は変更ファイル単位で実行する(`-recursive` でスコープ外まで整形しない)
- `terraform plan` に replace / destroy が含まれる場合、apply を提案する前にその理由を明示する
- apply は CI または人間が実行する。エージェントは plan の確認と apply の提案まで
- 既存リソースの import は、plan の `N to import, 0 to add, 0 to destroy` を確認してから apply を提案する。apply 後は import block を削除する
- `removed` ブロックは count / for_each の条件分岐と併用できない
- plan が意味論まで検証しない設定値(CloudWatch Metrics Insights のクエリ構文、Chatbot のイベント対応可否等)は、apply 前に公式ドキュメントで確認する
- 監視閾値を他環境から移植する時は、値をそのまま写さず対象システムの実態(タスク数・キャパシティ)と突き合わせる
