#!/bin/bash
# 対象のユーザーで実行する: dotfiles の取得、mise と chezmoi の導入、設定の適用。
# 使い方: user.sh <プロファイル> <取得元> [ブランチ]
#   取得元は git の URL か、コピーするディレクトリ
set -euo pipefail

# mise 本体のバージョン。更新の手順は docs/tools.md
MISE_VERSION="v2026.11.0"

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
  curl -fsSL https://mise.run | MISE_VERSION="$MISE_VERSION" sh
fi
mise="$HOME/.local/bin/mise"

# chezmoi 自身のバージョンも mise.lock で固定するので、先に設定だけ置く
mkdir -p "$HOME/.config/mise"
cp "$repo/home/dot_config/mise/config.toml" "$repo/home/dot_config/mise/mise.lock" "$HOME/.config/mise/"

cd "$HOME"
"$mise" install --yes chezmoi
DOTFILES_PROFILE="$profile" "$mise" exec chezmoi -- \
  chezmoi init --source "$repo" --apply --no-tty
