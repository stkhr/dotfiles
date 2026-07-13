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
