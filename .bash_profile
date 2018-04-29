# terminalのプロンプト
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

# rbenv
eval "$(rbenv init -)"

# git branchをプロンプトに表示させる
<< comment
以下を実行する必要がある
curl -o "/usr/local/etc/bash_completion.d/git-prompt.sh" https://raw.githubusercontent.com/git/git/master/contrib/completion/git-prompt.sh
comment
if type __git_ps1 > /dev/null 2>&1 ; then
  PROMPT_COMMAND="__git_ps1 '\w' '\\\$ '; $PROMPT_COMMAND"
  GIT_PS1_SHOWDIRTYSTATE=true
  GIT_PS1_SHOWSTASHSTATE=true
  GIT_PS1_SHOWUNTRACKEDFILES=true
  GIT_PS1_SHOWUPSTREAM="auto"
  GIT_PS1_SHOWCOLORHINTS=true
fi
