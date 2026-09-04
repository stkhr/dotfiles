# Codex グローバル設定管理

Claude Code の予備として使う Codex CLI の設定を dotfiles で管理し、`install.sh` で
`~/.codex/` 配下へシンボリックリンクを配置する。

## ディレクトリ構成

```
codex/
├── AGENTS.md           # グローバル指示(claude/CLAUDE.md の Codex 移植版)
├── rules/default.rules # コマンド承認ルール
└── README.md           # この説明ファイル
```

## セットアップ

CLI 本体は Brewfile の `cask "codex"` で導入する。ChatGPT.app にも Codex は同梱
されているが PATH が通っておらず、更新でパスが変わるため cask 版を正とする。

両者は `CODEX_HOME`(`~/.codex`)を共有する。認証(`auth.json`)だけでなく
config.toml・sqlite の状態も共通なので、`codex login` は一度だけでよい代わりに、
ChatGPT.app 側の設定変更は CLI にもそのまま効く。

リポジトリルートで `zsh install.sh` を実行すると以下が行われる:

| 対象 | リンク先 |
|---|---|
| `codex/AGENTS.md` | `~/.codex/AGENTS.md` |
| `codex/rules/default.rules` | `~/.codex/rules/default.rules` |
| `claude/skills/<name>/` | `~/.codex/skills/`(下記の14個のみ) |

`~/.claude` と同じ理由で `~/.codex` 自体はリンクしない。Codex は履歴・キャッシュ・
認証情報(`auth.json`)・sqlite をこのディレクトリに書き込む。

## AGENTS.md

Codex は `~/.codex/AGENTS.override.md` を優先し、無ければ `~/.codex/AGENTS.md` を
読む。プロジェクトの `AGENTS.md` はグローバルの後ろに連結されるので、リポジトリ側の
指示がグローバルを上書きする。

`claude/CLAUDE.md` をそのままリンクしていないのは、superpowers スキル群・
EnterWorktree・subagent 機構・`security-guidance` plugin といった Codex に存在しない
道具の手順が含まれるため。両者で方針が食い違うと予備として機能しないので、共通ルールを
変えたら両方に入れる。

worktree の置き場は Claude Code が `.claude/worktrees/`、Codex が `.worktrees/` で
意図的に分けている。どちらも `config/git/ignore` で無視される。同じディレクトリを
共有すると、片方のセッションが他方の作業ツリーを掃除しうる。

## Skills

`claude/skills/` を単一ソースにして、Codex 側の道具立てで完結するものだけをリンクする。
Codex は `~/.codex/skills/` 配下の `SKILL.md` を持つディレクトリを自動発見するため、
config.toml への登録は不要。

共有するもの: `adr` / `aws-investigation` / `code-review` / `debugging` /
`external-api-precheck` / `legal-review` / `monthly-dev-report` / `org-survey` /
`pdm-assist` / `pm-assist` / `pr-creation` / `security-hardening` / `session-start` /
`terraform-style`

共有しないもの: `pr-and-cleanup`(Claude Code の worktree ツールと
`superpowers:requesting-code-review` に依存)

共有対象の SKILL.md は特定のエージェントに固有のツール名を書かない。Claude Code 固有の
手順が必要な場合は「Claude Code では〜、それ以外では〜」の形で併記する。

`codex_skills` から名前を消しても `~/.codex/skills/` のリンクは解決し続ける(リンク先の
スキルはリポジトリに残るため)。Claude 側のような壊れたリンクにならず気付けないので、
共有をやめる時は `~/.codex/skills/<name>` を手動で削除する。

third-party skills(`npx skills add`)は `~/.agents/skills/` に置かれ、インストーラが
各エージェントの skills ディレクトリへリンクする。Claude Code と共通の置き場。

## 管理しないもの

| ファイル | 所有者 | 理由 |
|---|---|---|
| `~/.codex/config.toml` | ChatGPT.app / herdr | marketplace のタイムスタンプ・plugin の有効フラグ・project の trust_level・`notify`・`mcp_servers`・`[shell_environment_policy.set]`・`[desktop]` などを自動で書き込む。`herdr integration install codex` も hooks の有効化を書き込む |
| `~/.codex/hooks.json` | herdr | `herdr integration install codex` が生成(install.sh が実行済み) |
| `~/.codex/auth.json` | Codex | 認証情報 |

config.toml のうち手動で設定した値は次の通り。マシンを移す時はこれだけ入れ直す。

```toml
model = "gpt-5.6-sol"
personality = "pragmatic"
model_reasoning_effort = "high"

[features]
hooks = true
js_repl = false
```

MCP サーバー(serena / context7 / chrome-devtools など)は Claude Code 側にのみ登録して
いる。Codex でも必要になったら `codex mcp add` で登録する。

## rules

`prefix_rule` で危険なコマンドに承認プロンプトを出す。`decision` は
`forbidden` > `prompt` > `allow` の順に強く、複数マッチ時は最も強いものが勝つ。

`pattern` は位置ベースの前方一致のみで、任意位置のフラグ(`git push --force` の
`--force` 等)は表現できない。そこは AGENTS.md の確認手順で担保している。

`match` / `not_match` は読み込み時に評価されるアサーション。構文エラーがあると
`Error loading rules:` が出て全ルールが無効になるので、編集したら `codex exec` を
一度流して確認する。

## 動作確認

```bash
codex --version
codex doctor
ls -la ~/.codex/AGENTS.md ~/.codex/AGENTS.override.md ~/.codex/rules ~/.codex/skills
```

`AGENTS.override.md` が存在すると管理下の `AGENTS.md` は読まれない。
