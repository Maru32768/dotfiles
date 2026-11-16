#!/bin/bash
# 対象のユーザーで実行する: dotfiles の取得、mise と chezmoi の導入、設定の適用。
# 使い方: user.sh <プロファイル> <取得元> [ブランチ]
#   取得元は git の URL か、コピーするディレクトリ
#   DOTFILES_PREVIEW=1 なら適用せずに、書き換わる今のファイルと、mise がホームで読む設定を出す (docs/mac.md)
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

if [ -n "${DOTFILES_PREVIEW:-}" ]; then
  # ~/.config/mise/ を書き換えず、mise install がリポジトリの mise.lock に書き込まないように、写しを読ませる
  preview_dir="$(mktemp -d)"
  trap 'rm -rf "$preview_dir"' EXIT
  cp "$repo/home/dot_config/mise/config.toml" "$repo/home/dot_config/mise/mise.lock" "$preview_dir/"
  export MISE_GLOBAL_CONFIG_FILE="$preview_dir/config.toml"
  cd "$HOME"
  "$mise" install --yes chezmoi
  DOTFILES_PROFILE="$profile" "$mise" exec chezmoi -- chezmoi init --source "$repo" --no-tty
  status="$("$mise" exec chezmoi -- chezmoi status --exclude=scripts)"
  configs="$("$mise" config ls --no-header)"
  echo "==> 適用すると書き換わる、今あるファイル (M)"
  grep '^.M' <<<"$status" || echo "(なし)"
  echo "==> ホームにある mise の設定 (dotfiles の設定より優先されるので、移すか消す)"
  grep -vF "$MISE_GLOBAL_CONFIG_FILE" <<<"$configs" || echo "(なし)"
  exit 0
fi

# chezmoi 自身のバージョンも mise.lock で固定するので、先に設定だけ置く
mkdir -p "$HOME/.config/mise"
cp "$repo/home/dot_config/mise/config.toml" "$repo/home/dot_config/mise/mise.lock" "$HOME/.config/mise/"

cd "$HOME"
"$mise" install --yes chezmoi
DOTFILES_PROFILE="$profile" "$mise" exec chezmoi -- \
  chezmoi init --source "$repo" --apply --no-tty
