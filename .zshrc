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
alias random="openssl rand -base64 12 | fold -w 16 | head -1"
## ghq
alias g='cd $(ghq root)/$(ghq list | peco)'
alias ghb='hub browse $(ghq list | peco | cut -d "/" -f 2,3)'
## git
alias gb="git branch"
alias gs="git switch"
alias gc="git commit"
alias gd="git diff"
alias gl="git log"
alias gp="git pull"
alias gps="git push"
alias gr="git rebase"
alias gstat="git status"
alias gstash="git stash"
## pipe
alias -g L='| less'
alias -g H='| head'
alias -g T='| tail'
alias -g G='| egrep'
alias -g W='| wc -l'
alias -g B='| base64 --decode | gpg -d'

# ssh configを読み込む
function _ssh {
  # compadd `fgrep 'Host ' ~/.ssh/config | awk '{print $2}' | sort`;
  compadd `find ~/.ssh/* -type file | xargs fgrep 'Host ' | awk '{print $2}' | sort`;
}

# ctrl + r の検索を peco を使い検索しやすくする
function peco-history-selection() {
    BUFFER=`history -n 1 | tail -r  | awk '!a[$0]++' | peco`
    CURSOR=$#BUFFER
    zle reset-prompt
}
zle -N peco-history-selection
bindkey '^R' peco-history-selection

# gcloud
## The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/stkhr/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/stkhr/google-cloud-sdk/path.zsh.inc'; fi
## The next line enables shell command completion for gcloud.
if [ -f '/Users/stkhr/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/stkhr/google-cloud-sdk/completion.zsh.inc'; fi
source /opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc
source /opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc
## easy to change gcloud project 
gcp-config() {
  export config_name=$(gcloud config configurations list | tail -n +2 | awk '{print $1}' | peco)
  if [[ -z "$config_name" ]]; then return 1; fi
  gcloud config configurations activate $config_name
}

# history
export HISTSIZE=10000
export SAVEHIST=100000
setopt hist_ignore_dups

# sheldon
eval "$(sheldon source)"
