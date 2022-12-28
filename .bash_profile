export TERM=xterm-256color
export PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

export MYVIMRC=$HOME/.vimrc

export DENO_INSTALL=$HOME/.deno
export PATH=$DENO_INSTALL/bin:$PATH

export PATH=/usr/local/go/bin:$PATH
export PATH=$HOME/.local/bin:$PATH
export PATH=$HOME/go/bin:$PATH

export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"

WATCHPACK_POLLING=true

# checks to see if we are in a windows or linux dir
function isWinDir {
  case $(pwd -P) in
    /mnt/*) return $(true);;
    *) return $(false);;
  esac
}

# wrap the git command to either run windows git or linux
function git {
  type git.exe &> /dev/null
  if isWinDir && [ $? -eq 0 ]
    then
      git.exe "$@"
    else
      /usr/bin/git "$@"
  fi
}

source $HOME/.cargo/env
source ~/.bashrc
