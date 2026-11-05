#!/bin/bash
# 対象のユーザーで実行する: dotfiles の取得、mise と chezmoi の導入、設定の適用。
# 使い方: user.sh <プロファイル> <取得元> [ブランチ]
#   取得元は git の URL か、コピーするディレクトリ
set -euo pipefail

profile="$1"
source="$2"
branch="${3:-}"
repo="$HOME/dotfiles"

if [ ! -e "$repo" ]; then
  if [ -d "$source" ]; then
    cp -a "$source" "$repo"
  elif [ -n "$branch" ]; then
    git clone --branch "$branch" "$source" "$repo"
  else
    git clone "$source" "$repo"
  fi
fi

if [ ! -x "$HOME/.local/bin/mise" ]; then
  curl -fsSL https://mise.run | sh
fi
mise="$HOME/.local/bin/mise"

"$mise" install --yes chezmoi@latest
DOTFILES_PROFILE="$profile" "$mise" exec chezmoi@latest -- \
  chezmoi init --source "$repo" --apply --no-tty
