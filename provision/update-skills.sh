#!/bin/bash
# home/.chezmoidata/skills.toml で固定したコミットを、出どころの既定のブランチの最新に上げる。
# スキルはエージェントへの指示なので、表示した compare の URL で中身を読んでから反映する。
#
#   provision/update-skills.sh                  すべて
#   provision/update-skills.sh rust-skills ...  指定したものだけ
#   provision/update-skills.sh --dry-run        書き換えずに、新しいコミットがあるものを表示する
set -euo pipefail

data="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/home/.chezmoidata/skills.toml"
dry_run=false
if [ "${1:-}" = --dry-run ]; then
  dry_run=true
  shift
fi

# 書式は skills.toml の先頭のコメントのとおり。名前、repo、commit を 1 行ずつ出す
entries() {
  awk '
    /^\[skills\./ { name = $0; sub(/^\[skills\./, "", name); sub(/\]$/, "", name) }
    /^repo = /    { repo = $3; gsub(/"/, "", repo) }
    /^commit = /  { commit = $3; gsub(/"/, "", commit); print name, repo, commit }
  ' "$data"
}

if [ "$#" -gt 0 ]; then
  for want in "$@"; do
    entries | awk -v n="$want" '$1 == n { found = 1 } END { exit !found }' || { echo "skills.toml にない: $want" >&2; exit 1; }
  done
fi

declare -A latest=()
changed=0
while read -r name repo commit; do
  if [ "$#" -gt 0 ] && ! printf '%s\n' "$@" | grep -qxF "$name"; then
    continue
  fi
  if [ -z "${latest[$repo]:-}" ]; then
    latest[$repo]="$(git ls-remote "https://github.com/$repo.git" HEAD | cut -f1)"
    [ -n "${latest[$repo]}" ] || { echo "取得できない: $repo" >&2; exit 1; }
  fi
  new="${latest[$repo]}"
  [ "$new" = "$commit" ] && continue
  changed=$((changed + 1))
  printf '%s: https://github.com/%s/compare/%s...%s\n' "$name" "$repo" "$commit" "$new"
  if ! $dry_run; then
    tmp="$(mktemp)"
    awk -v n="$name" -v c="$new" '
      /^\[/ { cur = ($0 == "[skills." n "]") }
      cur && /^commit = / { $0 = "commit = \"" c "\"" }
      { print }
    ' "$data" >"$tmp"
    cat "$tmp" >"$data"
    rm -f "$tmp"
  fi
done < <(entries)

if [ "$changed" -eq 0 ]; then
  echo "すべて最新です"
elif $dry_run; then
  echo "$changed 件に新しいコミットがあります"
else
  echo "$changed 件を書き換えました。中身を確かめてから chezmoi apply で反映します"
fi
