#!/bin/bash
# vim をソースからビルドし、vim-plug を導入する。
# ghq が必要 (002_cli_tools.sh の後に実行)。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"

if has_cmd ghq; then
  log "パッケージ版 vim を削除してソースからビルドします"
  sudo apt remove -y vim || true
  sudo apt autoremove -y || true

  ghq get -u https://github.com/vim/vim
  (
    cd "$(ghq root)/github.com/vim/vim/src"
    "$DOTFILES_DIR/build_vim.sh" && make && sudo make install
  )
else
  warn "ghq が見つからないため vim のソースビルドをスキップします (先に scripts/002_cli_tools.sh を実行してください)"
fi

if [ ! -f "$HOME/.vim/autoload/plug.vim" ]; then
  log "vim-plug (vim用) をインストール"
  curl -fLo "$HOME/.vim/autoload/plug.vim" --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
fi

# プラグインインストールは .vimrc が symlink された後でないと意味がないので
# 006_dotfile_links.sh の後にもう一度このスクリプトを実行するか、以下を手動で実行してください:
#   vim +PlugInstall +qall
