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
ln -snfv "$DIR"/claude/crit-review.sh "$HOME"/.claude/crit-review.sh

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

# crit (AI code review TUI)
# Homebrew formula/tap は未公開、Go も前提にできないため GitHub Releases のバイナリを直接取得する
CRIT_VERSION="v0.2.2"
CRIT_MARKER="$HOME/.local/bin/.crit-version"
# 同バージョンが入っていれば skip。CRIT_VERSION を上げて再実行すると更新される
if [ "$(cat "$CRIT_MARKER" 2>/dev/null)" != "$CRIT_VERSION" ]; then
    case "$(uname -s)-$(uname -m)" in
        Darwin-arm64)  CRIT_ASSET="crit_darwin_arm64.tar.gz" ;;
        Darwin-x86_64) CRIT_ASSET="crit_darwin_amd64.tar.gz" ;;
        Linux-aarch64) CRIT_ASSET="crit_linux_arm64.tar.gz" ;;
        Linux-x86_64)  CRIT_ASSET="crit_linux_amd64.tar.gz" ;;
        *)             CRIT_ASSET="" ;;
    esac
    if [ -n "$CRIT_ASSET" ]; then
        CRIT_TMP=$(mktemp -d)
        CRIT_BASE="https://github.com/kevindutra/crit/releases/download/${CRIT_VERSION}"
        if command -v shasum &> /dev/null; then CRIT_VERIFY="shasum -a 256 -c"; else CRIT_VERIFY="sha256sum -c"; fi
        # バイナリと checksums を取得し、PATH に置く前に sha256 を検証する
        if curl -fsSL "$CRIT_BASE/$CRIT_ASSET" -o "$CRIT_TMP/$CRIT_ASSET" \
            && curl -fsSL "$CRIT_BASE/crit_${CRIT_VERSION#v}_checksums.txt" -o "$CRIT_TMP/checksums.txt" \
            && grep " ${CRIT_ASSET}\$" "$CRIT_TMP/checksums.txt" | (cd "$CRIT_TMP" && ${=CRIT_VERIFY} -) &> /dev/null; then
            tar xzf "$CRIT_TMP/$CRIT_ASSET" -C "$CRIT_TMP" crit
            mkdir -p "$HOME/.local/bin"
            mv "$CRIT_TMP/crit" "$HOME/.local/bin/crit"
            chmod +x "$HOME/.local/bin/crit"
            echo "$CRIT_VERSION" > "$CRIT_MARKER"
        else
            echo "crit: download or checksum verification failed, skipping install" >&2
        fi
        rm -rf "$CRIT_TMP"
    fi
fi

# claude plugins
if command -v claude &> /dev/null; then
    # Register marketplaces first (idempotent — safe to re-run)
    claude plugin marketplace add anthropics/claude-plugins-official
    claude plugin marketplace add hashicorp/agent-skills
    claude plugin marketplace add kevindutra/crit

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
    claude plugin install crit@crit-marketplace
fi
