#!/bin/bash
# dotfiles 配下の設定ファイルを $HOME にシンボリックリンクし、エディタのプラグインを入れる。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

link "$DOTFILES_DIR/.bashrc" "$HOME/.bashrc"
link "$DOTFILES_DIR/.bash_profile" "$HOME/.bash_profile"
link "$DOTFILES_DIR/vim/.vimrc" "$HOME/.vimrc"
link "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"

# JetBrains を WSL 側 (Gateway 等) で使う場合向け。通常は Windows 側で動くので
# 005_wsl_windows.sh が $WINHOME/.ideavimrc に別途コピーしている。
link "$DOTFILES_DIR/idea/.ideavimrc" "$HOME/.ideavimrc"

if has_cmd vim && [ -f "$HOME/.vim/autoload/plug.vim" ]; then
  log "vim のプラグインをインストール"
  vim +PlugInstall +qall || true
fi
