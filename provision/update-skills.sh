#!/bin/bash
# home/.chezmoidata/skills.tomlで固定したスキルと、home/.claude-settings.jsonでコミットに固定した
# プラグインのマーケットプレイスを、出どころの既定のブランチの最新に上げる。
# どちらもエージェントへの指示なので、表示したcompareのURLで中身を読んでから反映する。
#
#   provision/update-skills.sh                  すべて
#   provision/update-skills.sh rust-skills ...  指定したものだけ(スキルかマーケットプレイスの名前)
#   provision/update-skills.sh --dry-run        書き換えずに、新しいコミットがあるものを表示する
set -euo pipefail

home="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/home"
skills="$home/.chezmoidata/skills.toml"
settings="$home/.claude-settings.json"
dry_run=false
if [ "${1:-}" = --dry-run ]; then
  dry_run=true
  shift
fi

# CIのランナーにはmiseが無く、手元のjqはバージョンを決めていないmiseのshimのことがある
jq=(jq)
"${jq[@]}" --version >/dev/null 2>&1 || jq=(mise exec jq@1.8.2 -- jq)

# 名前、repo、commit、種類を1行ずつ出す。スキルの書式はskills.tomlの先頭のコメントのとおり。
# マーケットプレイスは、sourceがgithubで、refがコミットのハッシュのものだけ。Windowsのjqは行末をCRLFにする
entries() {
  awk '
    /^\[skills\./ { name = $0; sub(/^\[skills\./, "", name); sub(/\]$/, "", name) }
    /^repo = /    { repo = $3; gsub(/"/, "", repo) }
    /^commit = /  { commit = $3; gsub(/"/, "", commit); print name, repo, commit, "skill" }
  ' "$skills" &&
    "${jq[@]}" -r '
      .extraKnownMarketplaces // {} | to_entries[]
      | select(.value.source | .source == "github" and (.ref // "" | test("^[0-9a-f]{40}$")))
      | "\(.key) \(.value.source.repo) \(.value.source.ref) marketplace"
    ' "$settings" | tr -d '\r'
}
rows="$(entries)"

for want in "$@"; do
  awk -v n="$want" '$1 == n { found = 1 } END { exit !found }' <<<"$rows" || { echo "固定したスキルにもマーケットプレイスにもない: $want" >&2; exit 1; }
done

declare -A latest=()
changed=0
while read -r name repo commit kind; do
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
    if [ "$kind" = skill ]; then
      file="$skills"
      awk -v n="$name" -v c="$new" '
        /^\[/ { cur = ($0 == "[skills." n "]") }
        cur && /^commit = / { $0 = "commit = \"" c "\"" }
        { print }
      ' "$file" >"$tmp"
    else
      file="$settings"
      # jqで書き直すと書式と行末が変わるので、そのマーケットプレイスのrefの行にある古いハッシュだけを置き換える
      awk -v key="^[ \t]*\"$name\"[ \t]*:" -v o="$commit" -v c="$new" '
        $0 ~ key { cur = 1 }
        cur && /"ref"/ && index($0, o) { sub(o, c); cur = 0 }
        { print }
      ' "$file" >"$tmp"
    fi
    cmp -s "$tmp" "$file" && { rm -f "$tmp"; echo "書き換えられない: $name" >&2; exit 1; }
    cat "$tmp" >"$file"
    rm -f "$tmp"
  fi
done <<<"$rows"

if [ "$changed" -eq 0 ]; then
  echo "すべて最新です"
elif $dry_run; then
  echo "$changed 件に新しいコミットがあります"
else
  echo "$changed 件を書き換えました。中身を確かめてから chezmoi apply で反映します"
fi
