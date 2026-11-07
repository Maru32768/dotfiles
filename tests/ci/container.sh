#!/bin/bash
# 使い捨てのコンテナで環境を作り、doctor と再適用まで確かめる。作業ツリーの内容を使う。
# コンテナには systemd も WSL もないので、wsl.conf の効果や隔離は確かめられない (lab.ps1 で確かめる)。
#
# 使い方: container.sh <main|agent>
# shellcheck disable=SC2016
set -uo pipefail

profile="${1:?使い方: container.sh <main|agent>}"
case "$profile" in
  main) user=maru ;;
  agent) user=agent ;;
  *) echo "不明なプロファイル: $profile" >&2; exit 2 ;;
esac

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
image="ubuntu:26.04"
name="dotfiles-ci-$profile-$$"

user_log="$(mktemp)"

cleanup() {
  docker rm -f "$name" >/dev/null 2>&1
  rm -f "$user_log"
}
trap cleanup EXIT

as_user() { docker exec -u "$user" -w "/home/$user" -e "HOME=/home/$user" "$name" bash -lc "$1"; }
step() { printf '\n==> %s\n' "$1"; }

docker run -d --name "$name" "$image" sleep 7200 >/dev/null || exit 1

step "作業ツリーをコピー"
# 資格情報に触れないよう、マウントせずに追跡対象のファイルだけを渡す
(cd "$root" && git ls-files -co --exclude-standard | while IFS= read -r file; do
  [ -e "$file" ] && printf '%s\n' "$file"
done | tar -cf - -T -) | docker exec -i "$name" sh -c 'mkdir -p /tmp/src && tar -xf - -C /tmp/src && chmod -R a+rX /tmp/src' || exit 1

step "root.sh"
docker exec "$name" bash /tmp/src/provision/root.sh "$user" /tmp/src/packages/apt.txt "$profile" || exit 1

step "user.sh"
docker exec -u "$user" -w "/home/$user" -e "HOME=/home/$user" "$name" bash /tmp/src/provision/user.sh "$profile" /tmp/src 2>&1 | tee "$user_log" || exit 1

failures=0
# 導入のスクリプトは構築を止めないので、ここで警告を拾う
if grep -q "警告がありました" "$user_log"; then
  echo "FAIL user.sh が警告を出した"
  failures=$((failures + 1))
fi
if [ "$profile" = main ]; then
  step "doctor.sh"
  # TODO (資格情報の登録) は失敗に数えない
  as_user 'bash ~/dotfiles/tests/doctor.sh --container' || failures=$((failures + 1))
else
  step "agent の確認"
  as_user '
    set -u
    failed=0
    want() { if eval "$2" >/dev/null 2>&1; then echo "PASS $1"; else echo "FAIL $1"; failed=1; fi; }
    want "Claude Code が固定したバージョン" "[ \"\$(claude --version | cut -d\" \" -f1)\" = \"\$(cat /etc/claude-code/claude-version)\" ]"
    want "プロファイルが agent" "chezmoi data --format json | jq -e \".profile == \\\"agent\\\"\""
    want "署名の鍵を設定していない" "! git config --global user.signingkey"
    want ".claude の共通設定がない" "[ ! -e ~/.claude/settings.json ]"
    want "フックをビルドしていない" "[ ! -e ~/.claude/hooks/block-signing-bypass ]"
    want "管理設定が root 所有" "[ \"\$(stat -c %U /etc/claude-code/managed-settings.json)\" = root ]"
    want "管理設定で更新を止めている" "jq -e \".env.DISABLE_AUTOUPDATER == \\\"1\\\"\" /etc/claude-code/managed-settings.json"
    want "起動スクリプトが root 所有" "[ \"\$(stat -c %U /usr/local/bin/agent-claude)\" = root ]"
    exit "$failed"
  ' || failures=$((failures + 1))
fi

step "もう一度適用しても差分が出ない"
as_user '
  chezmoi apply --no-tty || exit 1
  changes="$(chezmoi status)"
  [ -z "$changes" ] || { printf "%s\n" "$changes"; exit 1; }
  echo "PASS 差分なし"
' || failures=$((failures + 1))

if [ "$failures" -gt 0 ]; then
  printf '\n%s 件の検査が失敗しました\n' "$failures"
  exit 1
fi
printf '\nすべての検査に通りました\n'
