#!/bin/bash
# GitHub Actions のランナーに mise と検査に使うツールを入れる。
# バージョンは provision/user.sh と mise.lock のものを使う。
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
version="$(sed -n 's/^MISE_VERSION="\(.*\)"$/\1/p' "$root/provision/user.sh")"

curl -fsSL https://mise.run | MISE_VERSION="$version" sh

mkdir -p "$HOME/.config/mise"
cp "$root/home/dot_config/mise/config.toml" "$root/home/dot_config/mise/mise.lock" "$HOME/.config/mise/"

cd "$HOME"
"$HOME/.local/bin/mise" install --yes chezmoi go shellcheck

if [ -n "${GITHUB_PATH:-}" ]; then
  printf '%s\n' "$HOME/.local/bin" "$HOME/.local/share/mise/shims" >>"$GITHUB_PATH"
fi
