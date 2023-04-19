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