# The following lines were added by compinstall
autoload -Uz compinit && compinit -u

# Lines configured by zsh-newuser-install
HISTFILE=~/.histfile
HISTSIZE=1000
SAVEHIST=10000
unsetopt beep
setopt hist_ignore_dups
setopt hist_ignore_all_dups
setopt hist_ignore_space
setopt hist_reduce_blanks
setopt hist_no_store
setopt inc_append_history
setopt auto_pushd
bindkey "^R" history-incremental-search-backward
setopt share_history

# prompt
# PROMPT='$ '
PS1='$ ' ## 相対パスのみ
RPROMPT=$GREEN'[%~]'$WHITE
setopt transient_rprompt
## promptにgitの情報を出す
autoload -Uz vcs_info
setopt prompt_subst
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' stagedstr "%F{yellow}!"
zstyle ':vcs_info:git:*' unstagedstr "%F{red}+"
zstyle ':vcs_info:*' formats "%F{green}%c%u[%b]%f"
zstyle ':vcs_info:*' actionformats '[%b|%a]'
precmd () { vcs_info }
RPROMPT=$RPROMPT'${vcs_info_msg_0_}'
## vimモード
#bindkey -v

#zshプロンプトにモード表示####################################
#function zle-line-init zle-keymap-select {
#  case $KEYMAP in
#    vicmd)
#    PROMPT="%F{red}[%f$reset_color%}%F{green}N%f%F{red}]%f%{$reset_color%}$ "
#    ;;
#    main|viins)
#    PROMPT="%F{red}[%f$reset_color%}%F{cyan}I%f%F{red}]%f%{$reset_color%}$ "
#    ;;
#  esac
#  zle reset-prompt
#}
#zle -N zle-line-init
#zle -N zle-keymap-select



# useful settings
setopt auto_cd


# ls
export LSCOLORS=gxfxcxdxbxegedabagacag
export LS_COLORS='di=36;40:ln=35;40:so=32;40:pi=33;40:ex=31;40:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;46'


# 補完
## 補完候補もLS_COLORSに合わせて色が付くようにする
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
## 補完に関するオプション
setopt auto_param_slash      # ディレクトリ名の補完で末尾の / を自動的に付加し、次の補完に備える
setopt mark_dirs             # ファイル名の展開でディレクトリにマッチした場合 末尾に / を付加
setopt list_types            # 補完候補一覧でファイルの種別を識別マーク表示 (訳注:ls -F の記号)
setopt auto_menu             # 補完キー連打で順に補完候補を自動で補完
setopt auto_param_keys       # カッコの対応などを自動的に補完
setopt interactive_comments  # コマンドラインでも # 以降をコメントと見なす
setopt magic_equal_subst     # コマンドラインの引数で --prefix=/usr などの = 以降でも補完できる
setopt complete_in_word      # 語の途中でもカーソル位置で補完
setopt always_last_prompt    # カーソル位置は保持したままファイル名一覧を順次その場で表示
setopt print_eight_bit       # 日本語ファイル名等8ビットを通す
setopt extended_glob         # 拡張グロブで補完(~とか^とか。例えばless *.txt~memo.txt ならmemo.txt 以外の *.txt にマッチ)
setopt globdots              # 明確なドットの指定なしで.から始まるファイルをマッチ
## 補完候補を矢印で選択できるようにする
zstyle ':completion:*:default' menu select=2
## 補完時に大文字小文字を無視する
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
## キャッシュの利用による補完の高速化
zstyle ':completion::complete:*' use-cache true


# ssh configを読み込む
function _ssh {
  # compadd `fgrep 'Host ' ~/.ssh/config | awk '{print $2}' | sort`;
  compadd `find ~/.ssh/* -type file | xargs fgrep 'Host ' | awk '{print $2}' | sort`;
}


# peco. brew intall pecoをする
function peco-history-selection() {
    BUFFER=`history -n 1 | tail -r  | awk '!a[$0]++' | peco`
    CURSOR=$#BUFFER
    zle reset-prompt
}
zle -N peco-history-selection
bindkey '^R' peco-history-selection


# alias
alias ls="ls -GF"
alias ll="ls -la"
alias ld='ls -ld' # Show info about the directory
alias lt='ls -ltr' # Sort by date, most recent last
alias cp="${ZSH_VERSION:+nocorrect} cp -i"
alias mv="${ZSH_VERSION:+nocorrect} mv -i"
alias mkdir="${ZSH_VERSION:+nocorrect} mkdir"
alias du='du -h'
alias job='jobs -l'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias diff='diff -u'
alias vi="vim"
alias g="git"
alias gb="git branch"
alias gc="git checkout"
alias gcm="git commit"
alias gd="git diff"
alias gl="git log"
alias gp="git pull"
alias gps="git push"
alias gr="git rebase"
alias gs="git status"
alias gst="git stash"
alias random="openssl rand -base64 12 | fold -w 16 | head -1"
## global alias
alias -g L='| less'
alias -g H='| head'
alias -g T='| tail'
alias -g G='| egrep'
alias -g W='| wc -l'
alias -g B='| base64 --decode | gpg -d'

# rbenv
# export PATH="$HOME/.rbenv/bin:$PATH"
# eval "$(rbenv init - zsh)"

# goenv
# export PATH="$HOME/.goenv/bin:$PATH"
# eval "$(goenv init -)"
# export GOPATH=~/go
# export PATH=$GOPATH/bin:$PATH
# export PATH=/usr/local/git/bin:$PATH

# nodenv
# export PATH="$HOME/.nodenv/bin:$PATH"
# eval "$(nodenv init -)"

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/stkhr/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/stkhr/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/stkhr/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/stkhr/google-cloud-sdk/completion.zsh.inc'; fi

# gcloud
source /opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc
source /opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc

export PATH="/opt/homebrew/opt/libpq/bin:/opt/homebrew/bin/:$PATH"
