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
されているが PATH が通っておらず、更新でパスが変わるため cask 版を正とする。認証
(`~/.codex/auth.json`)は両者で共有されるので `codex login` は一度だけでよい。

リポジトリルートで `zsh install.sh` を実行すると以下が行われる:

| 対象 | リンク先 |
|---|---|
| `codex/AGENTS.md` | `~/.codex/AGENTS.md` |
| `codex/rules/default.rules` | `~/.codex/rules/default.rules` |
| `claude/skills/<name>/` | `~/.codex/skills/`(下記の11個のみ) |

`~/.claude` と同じ理由で `~/.codex` 自体はリンクしない。Codex は履歴・キャッシュ・
認証情報(`auth.json`)・sqlite をこのディレクトリに書き込む。

## AGENTS.md

Codex は `~/.codex/AGENTS.override.md` を優先し、無ければ `~/.codex/AGENTS.md` を
読む。プロジェクトの `AGENTS.md` はグローバルの後ろに連結されるので、リポジトリ側の
指示がグローバルを上書きする。

`claude/CLAUDE.md` をそのままリンクしていないのは、crit プラグイン・superpowers・
EnterWorktree・subagent といった Codex に存在しない道具の手順が含まれるため。両者で
方針が食い違うと予備として機能しないので、共通ルールを変えたら両方に入れる。

## Skills

`claude/skills/` を単一ソースにして、Codex 側の道具立てで完結するものだけをリンクする。
Codex は `~/.codex/skills/` 配下の `SKILL.md` を持つディレクトリを自動発見するため、
config.toml への登録は不要。

共有するもの: `adr` / `aws-investigation` / `debugging` / `external-api-precheck` /
`legal-review` / `monthly-dev-report` / `org-survey` / `pdm-assist` / `pm-assist` /
`security-hardening` / `terraform-style`

共有しないもの: `code-review` / `pr-and-cleanup` / `pr-creation` / `session-start`
(worktree ツール・crit プラグイン・Draft PR フローなど Claude Code 固有の前提に依存)

third-party skills(`npx skills add`)は `~/.agents/skills/` に置かれ、インストーラが
各エージェントの skills ディレクトリへリンクする。Claude Code と共通の置き場。

## 管理しないもの

| ファイル | 所有者 | 理由 |
|---|---|---|
| `~/.codex/config.toml` | ChatGPT.app | marketplace のタイムスタンプ・plugin の有効フラグ・project の trust_level・`mcp_servers.node_repl` を自動で書き込む |
| `~/.codex/hooks.json` | herdr | `herdr integration install codex` が生成(install.sh が実行済み) |
| `~/.codex/auth.json` | Codex | 認証情報 |

config.toml のうち手動で設定した値は次の通り。マシンを移す時はこれだけ入れ直す。

```toml
model = "gpt-5.6-sol"
personality = "pragmatic"
model_reasoning_effort = "medium"

[features]
hooks = true
```

MCP サーバー(serena / context7 / playwright など)は Claude Code 側にのみ登録して
いる。Codex でも必要になったら `mcp_servers` を config.toml に足す。

## 動作確認

```bash
codex --version
ls -la ~/.codex/AGENTS.md ~/.codex/rules ~/.codex/skills
```
