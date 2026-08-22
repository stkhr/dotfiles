---
name: aws-investigation
description: |
  AWS 実機調査・AWS CLI 実行を伴う作業で使用。認証状態の確認、
  失効時の再認証依頼、一時キーの安全な受け渡し、read-only 原則を規定。
  「AWSで調査して」「CloudWatchのログを見て」「ECSの設定を確認して」
  などの指示、および調査中の認証エラー(ExpiredToken /
  InvalidClientTokenId / Unable to locate credentials)で起動。
---

# AWS 実機調査の手順

## 認証

- 最初に `aws sts get-caller-identity --profile <profile>` で認証状態と対象アカウントを確認する。プロファイルと用途の対応表はローカルの個人設定ファイルを参照
- 失効時は `aws sso login --profile <profile>` の実行をユーザーに依頼する。ユーザーのターミナルで実行した結果を会話に載せてもらう仕組みがあればそれを使う
- 一時キーのチャット貼り付けを受けない。貼られたら会話ログに残ることを伝えて失効・ローテーションを案内し、profile 方式に切り替える
- 認証情報をファイルに書く必要がある場合は一時ディレクトリに置き、作業終了時に削除する

## 実行

- 調査は read-only コマンドに限定する。書き込み系(create / update / delete / put)は破壊的操作の確認ゲートに従う
- 権限不足や permission 分類器で実行できないコマンドは、コピペ可能なブロックで提示してユーザー実行に切り替える
- 出力が大きい API は `--query` / jq で絞ってから取得する
