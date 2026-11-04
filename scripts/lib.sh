#!/bin/bash
# 各 scripts/*.sh から source して使う共通ヘルパー。単体でこのファイルだけ実行しても何もしない。

set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { echo -e "\033[1;32m==>\033[0m $*"; }
warn() { echo -e "\033[1;33m!!\033[0m $*" >&2; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }
is_wsl() { grep -qi microsoft /proc/version 2>/dev/null; }

# 冪等なシンボリックリンク作成。
# リンク先が既に正しければ何もしない。既存のファイル/ディレクトリがあればタイムスタンプ付きで退避する。
link() {
  local src="$1" dst="$2"

  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    return 0
  fi

  if [ -e "$dst" ] || [ -L "$dst" ]; then
    local backup="${dst}.bak.$(date +%s)"
    warn "既存の $dst を $backup に退避します"
    mv "$dst" "$backup"
  fi

  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst"
  log "linked $dst -> $src"
}
