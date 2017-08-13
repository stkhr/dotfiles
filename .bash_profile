# terminalのプロンプト
#PS1='\h:\W \u\$ ' ## デフォルト
## terminalにブランチを出す
#git_branch() {
#    echo $(git branch 2>/dev/null | sed -rn "s/^\* (.*)$/\1/p")
#}
#if [ "$color_prompt" = yes ]; then
#    PS1='\[\033[32m\]\h\[\033[00m\]:\[\033[01;34m\]$(git_branch)\[\033[00m\]:\w\$ '
#else
#    PS1='\h:$(git_branch):\w\$ '
#fi
PS1='\w $ ' ## 相対パスのみ

# terminalの色分け
export LSCOLORS=gxfxcxdxbxegedabagacad

# 重複履歴を無視
export HISTCONTROL=ignoredups
#空白から始めたコマンドを無視
export HISTCONTROL=ignorespace

if [ -f ~/.bashrc ] ; then
. ~/.bashrc
fi

# bash completion
[ -f /usr/local/etc/bash_completion ] && . /usr/local/etc/bash_completion