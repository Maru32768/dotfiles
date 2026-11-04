alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias youtube-dl='yt-dlp --no-check-certificates'

if [[ -t 0 ]]; then
    stty stop undef
    stty start undef
fi

. "$HOME/.cargo/env"

eval "$(~/.local/bin/mise activate bash)"
