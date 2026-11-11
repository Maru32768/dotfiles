#!/bin/bash
# gh-stack スキル (home/.chezmoidata/skills.toml) が呼ぶ gh の拡張。タグを変えると再実行される
set -euo pipefail

"$HOME/.local/bin/mise" exec gh -- gh extension install github/gh-stack --pin v0.3.0 --force
