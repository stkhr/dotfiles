#!/bin/zsh

DIR=`pwd`
for f in .??*
do
    [[ "$f" == ".git" ]] && continue
    [[ "$f" == ".gitignore" ]] && continue
    [[ "$f" == ".DS_Store" ]] && continue
    [[ "$f" == ".agents" ]] && continue

    #echo "$DIR"/"$f"
    ln -snfv "$DIR"/"$f" "$HOME"/"$f"
done

# starship
mkdir "$HOME"/.config
mkdir "$HOME"/.config/sheldon
ln -snfv "$DIR"/config/starship.toml "$HOME"/.config/starship.toml
ln -snfv "$DIR"/config/sheldon/plugins.toml "$HOME"/.config/sheldon/plugins.toml

# claude
mkdir -p "$HOME"/.claude
ln -snfv "$DIR"/claude/settings.json "$HOME"/.claude/settings.json
ln -snfv "$DIR"/claude/CLAUDE.md "$HOME"/.claude/CLAUDE.md
ln -snfv "$DIR"/claude/mcp.json "$HOME"/.claude/mcp.json
ln -snfv "$DIR"/claude/statusline.sh "$HOME"/.claude/statusline.sh

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
    claude plugin install superpowers@claude-plugins-official
    # HashiCorp Terraform plugins
    claude plugin marketplace add hashicorp/agent-skills 2>/dev/null || true
    claude plugin install terraform-code-generation@hashicorp
    claude plugin install terraform-module-generation@hashicorp
    claude plugin install terraform-provider-development@hashicorp
    claude plugin install frontend-design@claude-plugins-official
    claude plugin install context7@claude-plugins-official
fi

# aws amazonq
mkdir -p "$HOME"/.aws/amazonq
ln -snfv "$DIR"/.aws/amazonq/mcp.json "$HOME"/.aws/amazonq/mcp.json
