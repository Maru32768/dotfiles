export TERM=xterm-256color
export PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

export PATH=$PATH:/usr/local/go/bin
export PATH=$PATH:$HOME/.local/bin
export PATH=$PATH:$HOME/go/bin
. "$HOME/.cargo/env"
MYVIMRC="$HOME/.vimrc"
export PATH=$PATH:/opt/gradle/gradle-7.2/bin

if [[ -t 0 ]]; then
    stty stop undef
    stty start undef
fi

export DENO_INSTALL=$HOME/.deno
export PATH=$PATH:$DENO_INSTALL/bin
