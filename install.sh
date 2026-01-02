#!/bin/zsh

DIR=`pwd`
for f in .??*
do
    [[ "$f" == ".git" ]] && continue
    [[ "$f" == ".gitignore" ]] && continue
    [[ "$f" == ".DS_Store" ]] && continue

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
ln -snfv "$DIR"/claude/config.json "$HOME"/.claude/config.json
ln -snfv "$DIR"/claude/CLAUDE.md "$HOME"/.claude/CLAUDE.md
ln -snfv "$DIR"/claude/mcp.json "$HOME"/.claude/mcp.json

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

# aws amazonq
mkdir -p "$HOME"/.aws/amazonq
ln -snfv "$DIR"/.aws/amazonq/mcp.json "$HOME"/.aws/amazonq/mcp.json
