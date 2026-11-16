#!/bin/bash
# 対象のユーザーで実行する: dotfiles の取得、mise と chezmoi の導入、設定の適用。
# 使い方: user.sh <プロファイル> <取得元> [ブランチ]
#   取得元は git の URL か、コピーするディレクトリ
#   DOTFILES_PREVIEW=1 なら適用せずに、書き換わるか消える今のファイルと、ホームにある mise の設定を出す (docs/mac.md)
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

if [ "${DOTFILES_PREVIEW:-}" = 1 ]; then
  # ~/.config/mise/ とホームの chezmoi の設定を書き換えず、mise install がリポジトリの mise.lock に書き込まない
  # ように、mise の設定の写しと、chezmoi の設定、状態、キャッシュを一時ディレクトリに置く
  preview_dir="$(mktemp -d)"
  trap 'rm -rf "$preview_dir"' EXIT
  cp "$repo/home/dot_config/mise/config.toml" "$repo/home/dot_config/mise/mise.lock" "$preview_dir/"
  export MISE_GLOBAL_CONFIG_FILE="$preview_dir/config.toml"
  chezmoi=(chezmoi --config "$preview_dir/chezmoi.toml" --persistent-state "$preview_dir/chezmoistate.boltdb" --cache "$preview_dir/cache")
  cd "$HOME"
  "$mise" install --yes chezmoi
  DOTFILES_PROFILE="$profile" "$mise" exec chezmoi -- "${chezmoi[@]}" init --source "$repo" --no-tty
  status="$("$mise" exec chezmoi -- "${chezmoi[@]}" status --exclude=scripts)"
  configs="$("$mise" config ls --no-header)"
  echo "==> 適用すると書き換わる (M) か消える (D)、今あるファイル"
  grep '^.[MD]' <<<"$status" || echo "(なし)"
  echo "==> ホームにある mise の設定 (dotfiles の設定より優先されるので、移すか消す)"
  # ~/.config/mise/config.toml は、適用で dotfiles のものに置き換わる
  grep -v -e "^$preview_dir/config.toml " -e '^~/\.config/mise/config\.toml ' <<<"$configs" || echo "(なし)"
  exit 0
fi

# chezmoi 自身のバージョンも mise.lock で固定するので、先に設定だけ置く
mkdir -p "$HOME/.config/mise"
cp "$repo/home/dot_config/mise/config.toml" "$repo/home/dot_config/mise/mise.lock" "$HOME/.config/mise/"

cd "$HOME"
"$mise" install --yes chezmoi
DOTFILES_PROFILE="$profile" "$mise" exec chezmoi -- \
  chezmoi init --source "$repo" --apply --no-tty
