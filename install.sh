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
ln -snfv "$DIR"/starship.toml "$HOME"/.config/starship.toml