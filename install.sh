#!/bin/zsh

DIR=`pwd`
for f in .??*
do
    [[ "$f" == ".git" ]] && continue
    [[ "$f" == ".gitignore" ]] && continue
    [[ "$f" == ".DS_Store" ]] && continue
    [[ "$f" == ".agents" ]] && continue
    # ~/.claude はディレクトリ丸ごとリンクすると Claude Code の実行時ファイルが
    # リポジトリ内に書き込まれてしまう。必要なファイルだけ後続セクションで個別にリンクする
    [[ "$f" == ".claude" ]] && continue
    # ~/.crit は crit がレビュー状態を書き込むディレクトリ。同じ理由でリンクしない
    [[ "$f" == ".crit" ]] && continue

    #echo "$DIR"/"$f"
    ln -snfv "$DIR"/"$f" "$HOME"/"$f"
done

# ssh conf.d
mkdir -p "$HOME"/.ssh/conf.d
chmod 700 "$HOME"/.ssh/conf.d
ln -snfv "$DIR"/ssh/conf.d/general.conf "$HOME"/.ssh/conf.d/general.conf
# ~/.ssh/config の先頭に Include がなければ追記
if ! grep -q "Include conf.d/\*.conf" "$HOME/.ssh/config" 2>/dev/null; then
    if [ -f "$HOME/.ssh/config" ]; then
        printf "Include conf.d/*.conf\n\n" | cat - "$HOME/.ssh/config" > "$HOME/.ssh/config.tmp"
        mv "$HOME/.ssh/config.tmp" "$HOME/.ssh/config"
    else
        printf "Include conf.d/*.conf\n" > "$HOME/.ssh/config"
    fi
    chmod 600 "$HOME/.ssh/config"
fi

# user-local binaries(.zshrc が PATH に入れている ~/.local/bin へ)
mkdir -p "$HOME"/.local/bin
if [ -d "$DIR"/bin ]; then
    for bin_file in "$DIR"/bin/*; do
        if [ -f "$bin_file" ]; then
            bin_name=$(basename "$bin_file")
            ln -snfv "$bin_file" "$HOME/.local/bin/$bin_name"
            chmod +x "$HOME/.local/bin/$bin_name"
        fi
    done
fi

# starship
mkdir -p "$HOME"/.config/sheldon
ln -snfv "$DIR"/config/starship.toml "$HOME"/.config/starship.toml
ln -snfv "$DIR"/config/sheldon/plugins.toml "$HOME"/.config/sheldon/plugins.toml

# herdr
mkdir -p "$HOME"/.config/herdr
ln -snfv "$DIR"/config/herdr/config.toml "$HOME"/.config/herdr/config.toml

# git global ignore (core.excludesFile のデフォルト位置)
mkdir -p "$HOME"/.config/git
ln -snfv "$DIR"/config/git/ignore "$HOME"/.config/git/ignore

# claude
mkdir -p "$HOME"/.claude
ln -snfv "$DIR"/claude/settings.json "$HOME"/.claude/settings.json
ln -snfv "$DIR"/claude/CLAUDE.md "$HOME"/.claude/CLAUDE.md
ln -snfv "$DIR"/claude/statusline.sh "$HOME"/.claude/statusline.sh

# claude mcp servers
if command -v claude &> /dev/null; then
    zsh "$DIR"/claude/mcp-setup.sh
fi

# claude hooks
mkdir -p "$HOME"/.claude/hooks
if [ -d "$DIR"/claude/hooks ]; then
    for hook_file in "$DIR"/claude/hooks/*.sh; do
        if [ -f "$hook_file" ]; then
            hook_name=$(basename "$hook_file")
            ln -snfv "$hook_file" "$HOME/.claude/hooks/$hook_name"
            chmod +x "$HOME/.claude/hooks/$hook_name"
        fi
    done
fi

# claude skills
mkdir -p "$HOME"/.claude/skills
if [ -d "$DIR"/claude/skills ]; then
    for skill_dir in "$DIR"/claude/skills/*/; do
        if [ -d "$skill_dir" ]; then
            skill_name=$(basename "$skill_dir")
            ln -snfv "$skill_dir" "$HOME/.claude/skills/$skill_name"
        fi
    done
fi

# claude agents
mkdir -p "$HOME"/.claude/agents
if [ -d "$DIR"/claude/agents ]; then
    for agent_file in "$DIR"/claude/agents/*.md; do
        if [ -f "$agent_file" ]; then
            agent_name=$(basename "$agent_file")
            ln -snfv "$agent_file" "$HOME/.claude/agents/$agent_name"
        fi
    done
fi

# codex
# ~/.codex は Codex が auth.json・履歴・sqlite を書き込むため、~/.claude と同じく
# ディレクトリ丸ごとではなくファイル単位でリンクする。config.toml は ChatGPT.app が
# 書き換えるので管理対象外(codex/README.md 参照)
mkdir -p "$HOME"/.codex/rules
ln -snfv "$DIR"/codex/AGENTS.md "$HOME"/.codex/AGENTS.md
ln -snfv "$DIR"/codex/rules/default.rules "$HOME"/.codex/rules/default.rules

# codex skills(claude/skills を単一ソースに、Codex の道具立てで完結するものだけ共有)
mkdir -p "$HOME"/.codex/skills
codex_skills=(
    adr
    aws-investigation
    code-review
    debugging
    external-api-precheck
    legal-review
    monthly-dev-report
    org-survey
    pdm-assist
    pm-assist
    pr-creation
    security-hardening
    session-start
    terraform-style
)
for skill_name in "${codex_skills[@]}"; do
    skill_dir="$DIR/claude/skills/$skill_name"
    if [ -d "$skill_dir" ]; then
        ln -snfv "$skill_dir" "$HOME/.codex/skills/$skill_name"
    else
        echo "[install] skip: codex skill '$skill_name' not found in claude/skills" >&2
    fi
done

# herdr agent integrations(エージェント状態検知・セッション復元)
# hook 本体はマシンローカル配置。integration install は settings.json 等を
# 再整形して書き込むため、未導入・要更新のときだけ実行して作業ツリーを汚さない
if command -v herdr &> /dev/null; then
    herdr_integrations=$(herdr integration status 2>/dev/null)
    echo "$herdr_integrations" | grep -q '^claude: current' || herdr integration install claude
    # codex セクションが ~/.codex を先に作るので、ディレクトリの有無ではなく
    # CLI の導入有無で判定する
    if command -v codex &> /dev/null; then
        echo "$herdr_integrations" | grep -q '^codex: current' || herdr integration install codex
    fi
fi

# agent skills (third-party, installed via npx)
if command -v npx &> /dev/null; then
    (cd "$HOME" && npx -y skills add supabase/agent-skills --yes)
    # Fix CLAUDE.md symlinks (installer points them to a temp dir)
    for skill_dir in "$HOME"/.agents/skills/*/; do
        if [ -L "$skill_dir/CLAUDE.md" ]; then
            rm "$skill_dir/CLAUDE.md"
            ln -s AGENTS.md "$skill_dir/CLAUDE.md"
        fi
    done
fi

# claude plugins
if command -v claude &> /dev/null; then
    # Register marketplaces first (idempotent — safe to re-run)
    claude plugin marketplace add anthropics/claude-plugins-official
    claude plugin marketplace add hashicorp/agent-skills
    claude plugin marketplace add tomasz-tomczyk/crit

    # Anthropic official plugins
    claude plugin install superpowers@claude-plugins-official
    claude plugin install frontend-design@claude-plugins-official
    claude plugin install security-guidance@claude-plugins-official
    claude plugin install gopls-lsp@claude-plugins-official

    # HashiCorp Terraform plugin
    claude plugin install terraform@hashicorp

    # crit review plugin
    claude plugin install crit@crit
fi
