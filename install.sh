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

# herdr agent integrations(エージェント状態検知・セッション復元)
# hook 本体はマシンローカル配置。integration install は settings.json 等を
# 再整形して書き込むため、未導入・要更新のときだけ実行して作業ツリーを汚さない
if command -v herdr &> /dev/null; then
    herdr_integrations=$(herdr integration status 2>/dev/null)
    echo "$herdr_integrations" | grep -q '^claude: current' || herdr integration install claude
    if [ -d "$HOME/.codex" ]; then
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

# crit 移行クリーンアップ(旧 kevindutra/crit → Homebrew の tomasz-tomczyk/crit)
# 全マシンの移行が済んだらこのブロックごと削除してよい
rm -f "$HOME/.claude/crit-review.sh"
# 新 crit はここにレビュー状態を書くので、実体ディレクトリは残してリンクだけ外す
if [ -L "$HOME/.crit" ]; then
    rm -f "$HOME/.crit"
fi
# ~/.local/bin は PATH 上で /opt/homebrew/bin より前(.zshrc)なので、旧バイナリを残すと
# brew 版が隠れる。ただし brew bundle 前に消すと crit が消滅するため入れ替わりを待つ
if command -v brew &> /dev/null && brew list crit &> /dev/null; then
    rm -f "$HOME/.local/bin/crit" "$HOME/.local/bin/.crit-version"
elif [ -e "$HOME/.local/bin/crit" ]; then
    echo "crit: brew 版が未導入のため旧バイナリを残した。'brew bundle' 後に install.sh を再実行すること" >&2
fi
if command -v claude &> /dev/null; then
    claude plugin uninstall crit@crit-marketplace 2>/dev/null
    claude plugin marketplace remove crit-marketplace 2>/dev/null
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
    claude plugin install context7@claude-plugins-official
    claude plugin install security-guidance@claude-plugins-official

    # HashiCorp Terraform plugins
    claude plugin install terraform-code-generation@hashicorp
    claude plugin install terraform-module-generation@hashicorp
    claude plugin install terraform-provider-development@hashicorp

    # crit review plugin
    claude plugin install crit@crit
fi
