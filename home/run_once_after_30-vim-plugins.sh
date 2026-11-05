#!/bin/bash
# 一部のプラグインのビルドが失敗しても、環境の構築は止めない。結果は tests/doctor.sh で確認する。
export PATH="$HOME/.local/share/mise/shims:$PATH"
vim -es -u "$HOME/.vimrc" -i NONE +PlugInstall +qall </dev/null || echo "vim のプラグインの導入で警告がありました" >&2
exit 0
