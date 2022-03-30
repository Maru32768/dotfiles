export TERM=xterm-256color
export PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

export MYVIMRC=$HOME/.vimrc

export DENO_INSTALL=$HOME/.deno
export PATH=$PATH:$DENO_INSTALL/bin

export PATH=$PATH:/usr/local/go/bin
export PATH=$PATH:$HOME/.local/bin
export PATH=$PATH:$HOME/go/bin

source $HOME/.cargo/env

source ~/.bashrc
