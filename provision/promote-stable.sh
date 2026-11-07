#!/bin/bash
# 復元テストと CI に通ったコミットに stable タグを付ける。署名するので dev の端末で実行する。
# stable は作り直しの起点になる (docs/ci.md)。
#
# 使い方: promote-stable.sh [--dry-run]
set -euo pipefail

dry_run=false
case "${1:-}" in
  "") ;;
  --dry-run) dry_run=true ;;
  *) echo "不明な引数: $1" >&2; exit 2 ;;
esac

die() { echo "$1" >&2; exit 1; }

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"

# 結果は Windows 側に lab.ps1 restore-test が残す
result=""
for candidate in /mnt/c/Users/*/AppData/Local/dotfiles-lab/restore-test.json; do
  [ -f "$candidate" ] && result="$candidate"
done
[ -n "$result" ] || die "復元テストの結果がありません。Windows で lab.ps1 restore-test を実行してください"

jq -e '.passed == true' "$result" >/dev/null || die "最後の復元テストが通っていません: $result"
commit="$(jq -r '.commit' "$result")"
tested_at="$(jq -r '.time' "$result")"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || die "結果のコミットが不正です: $commit"

git fetch --quiet origin
git merge-base --is-ancestor "$commit" origin/master || die "$commit は origin/master にありません"

runs="$(curl -fsS "https://api.github.com/repos/Maru32768/dotfiles/actions/runs?head_sha=$commit&event=push")"
jq -e '[.workflow_runs[] | select(.name == "CI" and .conclusion == "success")] | length > 0' <<<"$runs" >/dev/null ||
  die "$commit で通った CI がありません"

if ! jq -e '.claude == true' "$result" >/dev/null; then
  echo "注意: この復元テストでは Claude を動かす検査をしていません" >&2
fi

echo "stable を $commit に付けます (復元テスト: $tested_at)"
if [ "$(git rev-parse -q --verify 'refs/tags/stable^{commit}' || true)" = "$commit" ]; then
  echo "すでに付いています"
  exit 0
fi
"$dry_run" && exit 0

git tag --sign --force --message "復元テストと CI に通ったコミット ($tested_at)" stable "$commit"
git push --force origin refs/tags/stable
